import AppKit
import Foundation
import Observation

/// Şarj denetimi (Faz 4) görünüm modeli: yardımcı kurulumu, durum, komutlar ve "tümünü kapat".
/// Ana şalter kapalıyken hiçbir yardımcı çağrısı yapılmaz; durum yoklaması yalnızca Şarj sekmesi görünürken çalışır.
@MainActor @Observable
final class ChargingModel {
    static let shared = ChargingModel()

    private(set) var installState: HelperInstallState
    private(set) var status: HelperStatus?
    private(set) var isBusy = false
    private(set) var errorText: String?
    private(set) var reachable = false

    var featureEnabled: Bool {
        didSet {
            guard featureEnabled != oldValue else { return }
            prefs.featureEnabled = featureEnabled
            guard !suppressFeatureDidSet else { return }
            if featureEnabled { startIfNeeded() } else { Task { await resetHardware() } }
        }
    }

    var ledFeatureEnabled: Bool {
        didSet { prefs.ledFeatureEnabled = ledFeatureEnabled; if !ledFeatureEnabled, status?.ledMode != .auto { Task { await setLED(.auto) } } }
    }

    var restoreOnQuit: Bool { didSet { prefs.restoreOnQuit = restoreOnQuit } }

    /// İstenen sınır ayarları (kaydırıcı); uygulandığı an yardımcıya gider.
    private(set) var limitEnabled: Bool
    private(set) var limit: Int
    private(set) var sailingGap: Int

    @ObservationIgnored private let registration: HelperRegistering
    @ObservationIgnored private let client: ChargeHelperClienting
    @ObservationIgnored private let prefs: ChargingPreferences
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var suppressFeatureDidSet = false

    init(registration: HelperRegistering = SMAppServiceRegistration(), client: ChargeHelperClienting = XPCChargeHelperClient(),
         prefs: ChargingPreferences = ChargingPreferences()) {
        self.registration = registration
        self.client = client
        self.prefs = prefs
        installState = registration.state
        featureEnabled = prefs.featureEnabled
        ledFeatureEnabled = prefs.ledFeatureEnabled
        restoreOnQuit = prefs.restoreOnQuit
        limitEnabled = prefs.limitEnabled
        limit = prefs.limit
        sailingGap = prefs.sailingGap
    }

    // MARK: Yaşam döngüsü

    /// Uygulama açılışında: bayrak kapalıysa HİÇBİR ŞEY yapmaz (ek maliyet yok).
    func startIfNeeded() {
        guard featureEnabled, observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applicationWillTerminate() }
        }
        Task { await restoreDesiredStateAfterLaunch() }
    }

    /// Sınır yardımcıda diskte de durur; ama "kapanınca kaldır" açıksa her açılışta istenen durum yeniden uygulanır.
    private func restoreDesiredStateAfterLaunch() async {
        refreshInstallState()
        guard installState.isEnabled else { return }
        await refreshStatus()
        guard restoreOnQuit, limitEnabled, status?.supportsChargeLimit == true, status?.config.enabled != true else { return }
        await applyLimit(enabled: true)
    }

    func applicationWillTerminate() {
        guard featureEnabled, restoreOnQuit, installState.isEnabled else { return }
        _ = client.sendBlocking(.resetAll, timeout: 1.5)
    }

    // MARK: Durum

    func refreshInstallState() { installState = registration.state }

    /// Şarj sekmesi görünürken ~5 sn'de bir çağrılır.
    func refreshStatus() async {
        refreshInstallState()
        guard featureEnabled, installState.isEnabled else {
            status = nil
            reachable = false
            return
        }
        apply(await client.send(.getStatus))
    }

    // MARK: Kurulum

    func install() async {
        errorText = nil
        do {
            try registration.register()
        } catch {
            errorText = "Kurulamadı: \(error.localizedDescription)"
        }
        refreshInstallState()
        if installState.isEnabled { await refreshStatus() }
    }

    /// Önce her şeyi varsayılana döndürür, sonra kaydı siler.
    func uninstall() async {
        errorText = nil
        isBusy = true
        defer { isBusy = false }
        if installState.isEnabled { _ = await client.send(.resetAll) }
        do {
            try await registration.unregister()
        } catch {
            errorText = "Kaldırılamadı: \(error.localizedDescription)"
        }
        limitEnabled = false
        prefs.limitEnabled = false
        refreshInstallState()
        status = nil
        reachable = false
    }

    func openLoginItemsSettings() { registration.openLoginItemsSettings() }

    // MARK: Komutlar

    func setLimitEnabled(_ enabled: Bool) async {
        limitEnabled = enabled
        prefs.limitEnabled = enabled
        await applyLimit(enabled: enabled)
    }

    func setLimit(_ value: Int) async {
        limit = ChargingPreferences.clampLimit(value)
        prefs.limit = limit
        if limitEnabled { await applyLimit(enabled: true) }
    }

    func setSailingGap(_ value: Int) async {
        sailingGap = ChargingPreferences.clampGap(value)
        prefs.sailingGap = sailingGap
        if limitEnabled { await applyLimit(enabled: true) }
    }

    /// "Şarjı şimdi tamamla": sınır geçici olarak yok sayılır; pil dolunca ya da fiş çekilince kendiliğinden biter.
    func startTopUp() async { await applyLimit(enabled: true, topUp: true) }

    func cancelTopUp() async { await applyLimit(enabled: limitEnabled) }

    private func applyLimit(enabled: Bool, topUp: Bool = false) async {
        let floor = ChargingPreferences.sailingFloor(limit: limit, gap: sailingGap)
        switch HelperCommand.chargeLimit(enabled: enabled, limit: limit, sailingFloor: floor, topUp: topUp) {
        case let .success(command): await run(command)
        case let .failure(error): errorText = error.message
        }
    }

    func setLowPowerMode(_ enabled: Bool) async { await run(.setLowPowerMode(enabled)) }

    func setLED(_ mode: MagSafeLEDMode) async {
        prefs.led = mode
        await run(.setMagSafeLED(mode))
    }

    /// Büyük kapatma düğmesi: sınır kapalı, şarj serbest, LED otomatik, ana şalter kapalı.
    func disableEverything() async {
        suppressFeatureDidSet = true
        featureEnabled = false
        suppressFeatureDidSet = false
        await resetHardware()
    }

    private func resetHardware() async {
        limitEnabled = false
        prefs.limitEnabled = false
        prefs.led = .auto
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        refreshInstallState()
        if installState.isEnabled { await run(.resetAll) }
    }

    private func run(_ command: HelperCommand) async {
        isBusy = true
        defer { isBusy = false }
        apply(await client.send(command))
    }

    private func apply(_ result: Result<HelperReply, ChargeHelperError>) {
        switch result {
        case let .success(reply):
            reachable = true
            status = reply.status
            errorText = reply.error?.message
            if reply.status.protocolVersion != HelperConstants.protocolVersion { errorText = HelperErrorCode.versionMismatch.message }
        case .failure:
            reachable = false
            errorText = "Yardımcıya ulaşılamadı."
        }
    }
}
