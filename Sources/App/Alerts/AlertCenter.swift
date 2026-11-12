import AppKit
import Foundation
import Observation

/// Mobil veride ani kullanım ve günlük limit uyarıları, limit/kural/filtre bildirimleri. Her uyarı kullanıcının seçimine göre
/// (Ayarlar › Genel › Bildirimler) uygulama içi balonla, sistem bildirimiyle ya da ikisiyle gelir. Sistem izni yalnızca kullanıcı
/// sistem bildirimi seçince istenir; izin yoksa uygulama içi gösterilir. Zamanlayıcı yok: izin durumu uygulama öne gelince okunur.
@MainActor @Observable
final class AlertCenter {
    /// "Mobilde engelle" tıklanınca çağrılır (uygulama anahtarı ile; sistem bildiriminden ya da uygulama içi balondan).
    @ObservationIgnored var onBlock: ((String) -> Void)?
    /// Kullanıcının seçimi (AppModel → Preferences.alertDelivery).
    @ObservationIgnored var delivery: () -> AlertDelivery = { .inApp }
    /// Uygulama içi balon (AppModel → pil uyarılarıyla aynı sunucu). Atanmamışsa uygulama içi yol sessizdir.
    @ObservationIgnored var presentInApp: ((AlertMessage, InAppAlertAction?) -> Void)?

    /// Son okunan sistem bildirimi izni (ayarlardaki not için gözlenir).
    private(set) var permission: NotificationPermission = .notDetermined

    @ObservationIgnored private let notifier: any SystemNotifying
    @ObservationIgnored private var lastBurst: [String: Date] = [:]
    @ObservationIgnored private var capLevelsSent: Set<Int> = []
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var capDay: String
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    init(calendar: Calendar = UsageStore.keyCalendar, notifier: (any SystemNotifying)? = nil) {
        self.calendar = calendar
        self.capDay = UsageStore.dayKey(calendar: calendar)
        self.notifier = notifier ?? UNSystemNotifier()
        self.notifier.onBlock = { [weak self] app in self?.onBlock?(app) }
        Task { await refreshPermission() }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { Task { await self?.refreshPermission() } }
        }
    }

    // MARK: Yönlendirme

    /// Seçime ve izne göre uygulama içi ve/veya sistem bildirimi.
    func deliver(_ message: AlertMessage, action: InAppAlertAction? = nil) {
        let route = delivery().route(permission: permission)
        if route.system { notifier.post(message) }
        if route.inApp { presentInApp?(message, action) }
    }

    func refreshPermission() async {
        permission = await notifier.permission()
    }

    /// Ayarlarda sistem bildirimi içeren bir seçenek seçilince: izin hiç sorulmadıysa sorar, sonra durumu tazeler.
    func deliveryChanged(to choice: AlertDelivery) async {
        guard choice.wantsSystem else { return }
        permission = await notifier.permission()
        if permission == .notDetermined { permission = await notifier.requestPermission() }
    }

    /// Yalnızca sistem bildirimi (pil uyarısındaki "Bildirim" kutusu: uygulama içi balonu zaten kendisi gösterir).
    /// İzin hiç sorulmadıysa bu açık seçim üzerine sorulur; reddedildiyse gönderilmez.
    func postSystemOnly(title: String, body: String) {
        let message = AlertMessage(id: "info-\(title)", title: title, body: body)
        switch permission {
        case .authorized: notifier.post(message)
        case .denied: break
        case .notDetermined:
            Task {
                permission = await notifier.requestPermission()
                if permission == .authorized { notifier.post(message) }
            }
        }
    }

    // MARK: Uyarılar

    func notify(title: String, body: String, symbol: String = "bell.badge.fill") {
        deliver(AlertMessage(id: "info-\(title)", title: title, body: body, symbol: symbol))
    }

    /// Engelleme yapılınca sonucu teyit eder.
    func notifyBlocked(name: String) {
        deliver(AlertMessage(id: "blocked-\(name)", title: "\(name) mobil veride engellendi",
                             body: "Wi-Fi'de etkilenmez. Kaldırmak için Adalmon panelindeki listeyi kullan.",
                             sound: false, symbol: "nosign"))
    }

    /// Uygulama içi balondaki "Filtre ayarlarını aç" (AppDelegate → Ayarlar › Filtre). Atanmamışsa düğme yok.
    @ObservationIgnored var openFilterSettings: (@MainActor () -> Void)?

    static let filterDownMessage = AlertMessage(
        id: "filter-down", title: "Filtre bağlı değil",
        body: "Mobil verideyken sınırlar ve engeller UYGULANMIYOR, uygulama dağılımı güncellenmiyor. Ayarlar › Filtre'den kontrol et.",
        symbol: "exclamationmark.shield.fill")

    /// Mobilde filtre bağlı değil (zamanlama `FilterLinkWatch`'ta: 60 sn sonra bir kez, sürdükçe en çok 30 dk'da bir).
    func notifyFilterDown() {
        let action = openFilterSettings.map { open in InAppAlertAction(title: "Filtre ayarlarını aç") { open() } }
        deliver(Self.filterDownMessage, action: action)
    }

    /// Son 60 sn'de MOBİL byte'ı eşiği aşan uygulamalar için (uygulama başına 5 dakikada bir).
    /// Toplam değil mobil sayılır: yerel proxy'ye giden loopback trafiği Mac'ten çıkmaz (bkz. `UsageEngine.mobileShares`).
    func checkBursts(_ apps: [AppUsage], threshold: UInt64, isMobile: Bool, now: Date = .now) {
        guard isMobile else { return }
        for a in apps where a.mobileBytes >= threshold {
            if let t = lastBurst[a.app], now.timeIntervalSince(t) < 300 { continue }
            lastBurst[a.app] = now
            let name = AppCatalog.shared.name(for: a.app)
            let domain = a.domains.first.map { " · \($0.name)" } ?? ""
            let message = AlertMessage(id: "burst-\(a.app)", title: "\(name) mobil veriyi hızlı harcıyor",
                                       body: "Son 1 dakikada \(Format.bytes(a.mobileBytes))\(domain)",
                                       category: UNSystemNotifier.burstCategory, userInfo: ["app": a.app],
                                       symbol: "antenna.radiowaves.left.and.right")
            let app = a.app
            deliver(message, action: InAppAlertAction(title: "Mobilde engelle") { [weak self] in self?.onBlock?(app) })
        }
    }

    /// Günlük mobil limitin %50 / %80 / %100'ünde bir kez.
    func checkCap(used: UInt64, cap: UInt64, now: Date = .now) {
        let day = UsageStore.dayKey(now, calendar: calendar)
        if day != capDay { capDay = day; capLevelsSent = [] }
        guard cap > 0 else { return }
        let pct = Int(Double(used) / Double(cap) * 100)
        for level in [100, 80, 50] where pct >= level {
            guard !capLevelsSent.contains(level) else { break }
            capLevelsSent.formUnion([50, 80, 100].filter { $0 <= level })
            deliver(AlertMessage(id: "cap-\(level)",
                                 title: level >= 100 ? "Günlük mobil veri limiti aşıldı" : "Günlük mobil verinin %\(level)'i kullanıldı",
                                 body: "\(Format.bytes(used)) / \(Format.bytes(cap))", symbol: "chart.bar.fill"))
            break
        }
    }
}
