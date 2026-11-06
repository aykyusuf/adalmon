import Foundation
import Observation

/// Uygulamanın kök durumu: metrik örnekleme, filtre trafiği, mobil veri sayacı, uyarılar.
@MainActor @Observable
final class AppModel {
    static let historyLength = 60

    let prefs = Preferences()
    let path = PathMonitor()
    let installer = ExtensionInstaller()
    let usage: UsageEngine
    @ObservationIgnored let alerts = AlertCenter()

    private(set) var snapshot: SystemSnapshot?
    private(set) var cpuHistory: [Double] = []
    private(set) var gpuHistory: [Double] = []
    private(set) var memHistory: [Double] = []
    private(set) var downHistory: [Double] = []
    private(set) var upHistory: [Double] = []

    /// Bugün mobil yolda fiziksel arayüzden geçen gerçek toplam (limit buna göre).
    private(set) var mobileToday: UInt64 = 0
    private(set) var wifiToday: UInt64 = 0
    /// Fiziksel arayüzlerde son 60 sn'de indirilen / yüklenen byte.
    private(set) var downLast60: UInt64 = 0
    private(set) var upLast60: UInt64 = 0
    /// Uygulama açıldığından (gün değişene kadar) bugün indirilen / yüklenen.
    private(set) var downToday: UInt64 = 0
    private(set) var upToday: UInt64 = 0
    private(set) var filterConnected = false
    private(set) var proxy = ProxyDetector.Result(ports: [], ownerPaths: [])
    private(set) var lastUpdate: Date?

    var isMobile: Bool { path.isMobile(force: prefs.forceMobile) }
    /// Mobil toplamın uygulamalara yazılamayan kısmı (sistem, VPN, ölçüm farkı).
    var unattributedMobile: UInt64 { mobileToday > usage.attributedMobileToday ? mobileToday - usage.attributedMobileToday : 0 }

    @ObservationIgnored private let store = UsageStore()
    @ObservationIgnored private let sampler = MetricsSampler()
    @ObservationIgnored private let samplerQueue = DispatchQueue(label: "adalmon.metrics", qos: .utility)
    @ObservationIgnored private let filter = FilterClient()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var tick = 0
    @ObservationIgnored private var lastIn: [String: UInt64] = [:]
    @ObservationIgnored private var lastOut: [String: UInt64] = [:]
    @ObservationIgnored private var windowSamples: [(time: Date, down: UInt64, up: UInt64)] = []
    @ObservationIgnored private var lastConfig: FilterConfig?
    @ObservationIgnored private var dayKey = UsageStore.dayKey()
    @ObservationIgnored private var pendingIface: (mobile: UInt64, wifi: UInt64) = (0, 0)

    init() {
        usage = UsageEngine(store: store)
        alerts.onBlock = { [weak self] app in self?.setBlocked(app, true, fromNotification: true) }
        installer.onFilterEnabled = { [weak self] in self?.startFilterWatchdog() }
    }

    func start() {
        Task {
            await usage.loadToday()
            mobileToday = await store.interfaceBytes(day: dayKey, mobile: true)
            wifiToday = await store.interfaceBytes(day: dayKey, mobile: false)
            await installer.refresh()
            installer.observeSystemChanges()
            installer.setProxyWanted(!prefs.appLimits.isEmpty)
            installer.updateIfInstalled()
            if installer.state == .active { startFilterWatchdog() }
        }
        refreshProxy()
        scheduleTimer()
        observeInterval()
    }

    /// Güncelleme aralığı ayarı değişince zamanlayıcıyı hemen yeniden kur ve bir ölçüm al.
    private func observeInterval() {
        withObservationTracking {
            _ = prefs.updateInterval
        } onChange: { @Sendable [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.scheduleTimer()
                await self.step()
                self.observeInterval()
            }
        }
    }

    /// Zamanlayıcı doğrudan gereken aralıkta çalışır: panel açıkken 1 sn, kapalıyken ayar (varsayılan 2 sn).
    /// Boşa uyanma yok (pil).
    private func scheduleTimer() {
        let interval = TimeInterval(panelVisible || mainWindowVisible ? 1 : max(1, prefs.updateInterval))
        if let timer, timer.isValid, timer.timeInterval == interval { return }
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.timerFired() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Panelde kısa süre görünen geri bildirim (engelleme vb.).
    struct Toast: Equatable {
        var message: String
        var undoApp: String?
        var undoBlocked: Bool
        var action: Action?

        /// Toast'ta "Geri al"ın yanında gösterilebilen isteğe bağlı eylem.
        enum Action: Equatable { case restart(app: String) }
    }
    private(set) var toast: Toast?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    func setBlocked(_ app: String, _ blocked: Bool, fromNotification: Bool = false) {
        let isBlocked = prefs.blockedOnMobile.contains(app)
        guard blocked != isBlocked else { return }
        prefs.toggleBlocked(app)
        pushConfig(force: true)
        let name = AppCatalog.shared.name(for: app)
        let message = blocked
            ? "\(name) mobil veride engellendi" + (isMobile ? "" : " (şu an Wi-Fi'desin, etkilenmez)")
            : "\(name) engeli kaldırıldı"
        showToast(Toast(message: message, undoApp: app, undoBlocked: !blocked))
        if fromNotification { alerts.notifyBlocked(name: name) }
        if blocked && isMobile { scheduleReset(app, reason: .block) }
    }

    func undoToast() {
        guard let t = toast, let app = t.undoApp else { return }
        setBlocked(app, t.undoBlocked)
    }

    // MARK: Filtre emniyeti

    @ObservationIgnored private var watchdogTask: Task<Void, Never>?

    /// Filtre açıldıktan sonra 60 sn boyunca 3 sn'de bir internet testi. İki başarısız test üst üste
    /// (ve ağ bağlıyken) → filtre otomatik kapatılır. Böylece hatalı bir filtre interneti uzun süre kesemez.
    func startFilterWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            var failures = 0
            for _ in 0..<20 {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                guard self.path.medium != .offline else { failures = 0; continue }
                let ok = await AppModel.probeInternet()
                failures = ok ? 0 : failures + 1
                if failures >= 2 {
                    NSLog("Adalmon watchdog: internet testi başarısız, filtre kapatılıyor")
                    await self.installer.safetyDisable(reason: "İnternet kesildiği için filtre otomatik kapatıldı")
                    self.showToast(Toast(message: "Filtre interneti kesti, otomatik kapatıldı", undoApp: nil, undoBlocked: false))
                    self.alerts.notify(title: "Ağ filtresi kapatıldı",
                                       body: "Filtre açıldıktan sonra internet testi başarısız oldu; güvenlik için filtre kapatıldı.")
                    return
                }
            }
        }
    }

    /// Sistem proxy ayarlarına uyan (SpoofDPI dahil) küçük bir HTTPS isteği.
    nonisolated static func probeInternet() async -> Bool {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 4
        cfg.timeoutIntervalForResource = 4
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel() }
        guard let url = URL(string: "https://www.apple.com/library/test/success.html") else { return true }
        do {
            let (_, response) = try await session.data(from: url)
            return ((response as? HTTPURLResponse)?.statusCode ?? 0) < 500
        } catch {
            return false
        }
    }

    private func showToast(_ t: Toast) {
        toast = t
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func isBlocked(_ app: String) -> Bool { prefs.blockedOnMobile.contains(app) }

    // MARK: Hız sınırı

    /// Sınırlı uygulamalar, ada göre sıralı.
    var limitedApps: [String] {
        prefs.appLimits.keys.sorted { AppCatalog.shared.name(for: $0).localizedCaseInsensitiveCompare(AppCatalog.shared.name(for: $1)) == .orderedAscending }
    }

    func limit(for app: String) -> AppLimit? { prefs.appLimits[app] }

    /// Saydam proxy (hız sınırı) şu an açık mı.
    var throttleActive: Bool { installer.proxyActive }

    /// Uygulamanın sınırını ayarla; `nil` ya da her iki yön boşsa kaldırır.
    func setLimit(_ app: String, _ limit: AppLimit?) {
        let new = (limit?.hasCap ?? false) ? limit : nil
        let old = prefs.appLimits[app]
        guard new != old else { return }
        prefs.appLimits[app] = new
        pushConfig(force: true)
        installer.setProxyWanted(!prefs.appLimits.isEmpty)
        let name = AppCatalog.shared.name(for: app)
        let message: String
        if let new {
            let parts = [new.downBytesPerSec.map { "↓ \(Self.rateText($0))" }, new.upBytesPerSec.map { "↑ \(Self.rateText($0))" }]
                .compactMap { $0 }.joined(separator: " ")
            var m = "\(name) hız sınırı: \(parts)"
            if new.onlyOnMobile { m += isMobile ? " (mobil veride)" : " (yalnızca mobilde, şu an Wi-Fi)" }
            if installer.state != .active { m += " — ağ filtresi kurulu değil" }
            message = m
        } else {
            message = "\(name) hız sınırı kaldırıldı"
        }
        showToast(Toast(message: message, undoApp: nil, undoBlocked: false))
        if let new, Self.isStricter(new, than: old), !new.onlyOnMobile || isMobile { scheduleReset(app, reason: .limit) }
    }

    /// Yeni sınır eskisinden daha kısıtlayıcı mı (yeni eklendi, düştü ya da "sadece mobilde" kalktı).
    /// Gevşetmek açık bağlantıları kesmeyi gerektirmez.
    private static func isStricter(_ new: AppLimit, than old: AppLimit?) -> Bool {
        guard let old else { return true }
        func cap(_ v: Int?) -> Int { v.flatMap { $0 > 0 ? $0 : nil } ?? .max }
        return cap(new.downBytesPerSec) < cap(old.downBytesPerSec)
            || cap(new.upBytesPerSec) < cap(old.upBytesPerSec)
            || (old.onlyOnMobile && !new.onlyOnMobile)
    }

    // MARK: Açık bağlantıları yenileme

    private enum ResetReason { case limit, block, manual }

    /// Filtre yalnızca yeni bağlantıları etkiler; uzun ömürlü bağlantıları (HTTP/2, QUIC, WebSocket) keserek
    /// uygulamanın yeniden bağlanmasını ve yeni kurala takılmasını sağlar.
    @ObservationIgnored private var resetTasks: [String: Task<Void, Never>] = [:]

    private func scheduleReset(_ app: String, reason: ResetReason) {
        guard installer.state == .active else { return }
        resetTasks[app]?.cancel()
        resetTasks[app] = Task { [weak self] in
            // Yeni yapılandırmanın uzantıya ulaşması için kısa bekleme.
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await self?.performReset(app, reason: reason)
        }
    }

    /// Uygulamanın açık bağlantılarını hemen kes (bağlam menüsü / ayarlar).
    func resetConnections(for app: String) {
        resetTasks[app]?.cancel()
        resetTasks[app] = Task { [weak self] in await self?.performReset(app, reason: .manual) }
    }

    private func performReset(_ app: String, reason: ResetReason) async {
        let result = await Task.detached(priority: .utility) { ConnectionResetter.resetConnections(forApp: app) }.value
        guard !Task.isCancelled else { return }
        let name = AppCatalog.shared.name(for: app)
        if !result.isRunning {
            if reason == .manual { showToast(Toast(message: "\(name) çalışmıyor", undoApp: nil, undoBlocked: false)) }
            return
        }
        if result.needsRestart {
            let canRestart = app.hasSuffix(".app")
            showToast(Toast(message: "\(name) açık bağlantılarını yenilemeye izin vermedi" + (canRestart ? "; yeniden başlatmak gerekiyor" : ""),
                            undoApp: nil, undoBlocked: false, action: canRestart ? .restart(app: app) : nil))
            return
        }
        let message: String
        switch reason {
        case .limit: message = "\(name) uygulamasının açık bağlantıları yenilendi, sınır hemen geçerli"
        case .block: message = "\(name) uygulamasının açık bağlantıları yenilendi, engel hemen geçerli"
        case .manual: message = "\(name) uygulamasının açık bağlantıları yenilendi"
        }
        // Engellemede "Geri al" düğmesi kaybolmasın.
        let undo = reason == .block ? Toast(message: message, undoApp: app, undoBlocked: false) : Toast(message: message, undoApp: nil, undoBlocked: false)
        showToast(undo)
    }

    /// Uygulamayı kapatıp yeniden aç (bağlantı sıfırlama yetmediğinde).
    func restartApp(_ app: String) {
        let name = AppCatalog.shared.name(for: app)
        showToast(Toast(message: "\(name) yeniden başlatılıyor…", undoApp: nil, undoBlocked: false))
        Task { [weak self] in
            let ok = await AppRestarter.restart(appKey: app)
            self?.showToast(Toast(message: ok ? "\(name) yeniden başlatıldı" : "\(name) yeniden başlatılamadı",
                                  undoApp: nil, undoBlocked: false))
        }
    }

    /// 512_000 → "500 KB/s", 1_048_576 → "1 MB/s" (1024 tabanlı).
    nonisolated static func rateText(_ bytesPerSec: Int) -> String {
        let kb = Double(bytesPerSec) / 1024
        if kb >= 1024 {
            let mb = kb / 1024
            return mb == mb.rounded() ? "\(Int(mb)) MB/s" : String(format: "%.1f MB/s", mb)
        }
        return "\(Int(kb.rounded())) KB/s"
    }

    // MARK: Loop

    /// Panel açıkken 1 sn, kapalıyken `prefs.updateInterval` sn'de bir örnekle (pil).
    /// Her ölçüm adımının sonunda çağrılır (menü çubuğu çizimi).
    @ObservationIgnored var onStep: (() -> Void)?

    /// Ana pencere (Dock modu) açıkken de saniyede bir örnekle.
    @ObservationIgnored var mainWindowVisible = false {
        didSet {
            scheduleTimer()
            if mainWindowVisible && !oldValue { Task { await step() } }
        }
    }

    @ObservationIgnored var panelVisible = false {
        didSet {
            scheduleTimer()
            if panelVisible && !oldValue { Task { await step() } }
        }
    }
    @ObservationIgnored private var seconds = 0
    @ObservationIgnored private var lastStepSecond = 0
    @ObservationIgnored private var prevTick = 0

    @ObservationIgnored private let startDate = Date()

    private func timerFired() async {
        scheduleTimer() // aralık ayarı değiştiyse uygula
        await step()
    }

    /// `period` saniyelik bir sınır son adımdan beri geçildiyse true.
    private func due(_ period: Int) -> Bool { tick / period != prevTick / period }

    private func step() async {
        seconds = Int(Date.now.timeIntervalSince(startDate))
        let elapsed = max(1, seconds - lastStepSecond)
        lastStepSecond = seconds
        prevTick = tick
        tick = seconds
        let snap = await withCheckedContinuation { (c: CheckedContinuation<SystemSnapshot, Never>) in
            samplerQueue.async { [sampler] in c.resume(returning: sampler.sample()) }
        }
        apply(snap)

        let buckets = await filter.drain()
        // Uzantı süreci reboot'a kadar çalışabilir; "aktif" için filtre ayarının da açık olması gerekir.
        filterConnected = filter.isConnected && installer.state == .active
        usage.ingest(buckets, seconds: elapsed)
        alerts.checkBursts(usage.last60, threshold: prefs.burstThresholdBytes, isMobile: isMobile)
        alerts.checkCap(used: mobileToday, cap: prefs.dailyCapBytes)

        if due(15) {
            // Ucuz kontrol; süreç taraması sadece port değişince ya da 5 dk'da bir.
            let ports = ProxyDetector.localProxyPorts()
            if ports != proxy.ports || (due(300) && !ports.isEmpty) { refreshProxy() }
        }
        if due(5) { pushConfig(force: false) }
        if due(10) { await persist() }
        lastUpdate = .now
        onStep?()
    }

    private func apply(_ s: SystemSnapshot) {
        snapshot = s
        Self.push(&cpuHistory, s.cpu.total)
        Self.push(&gpuHistory, s.gpu?.displayLoad ?? 0)
        Self.push(&memHistory, s.memory.usedFraction)
        Self.push(&downHistory, s.network.downloadBytesPerSecond)
        Self.push(&upHistory, s.network.uploadBytesPerSecond)

        // Fiziksel arayüz deltası → bugünkü mobil / Wi-Fi toplamı.
        let today = UsageStore.dayKey()
        if today != dayKey { dayKey = today; mobileToday = 0; wifiToday = 0; downToday = 0; upToday = 0 }
        var dIn: UInt64 = 0, dOut: UInt64 = 0
        for (name, inB) in s.network.cumulativeIn {
            let outB = s.network.cumulativeOut[name] ?? 0
            if let prevIn = lastIn[name], inB >= prevIn { dIn += inB - prevIn }
            if let prevOut = lastOut[name], outB >= prevOut { dOut += outB - prevOut }
            lastIn[name] = inB
            lastOut[name] = outB
        }
        let delta = dIn + dOut
        guard delta > 0, delta < 10_000_000_000 else { return }
        downToday += dIn
        upToday += dOut
        windowSamples.append((s.timestamp, dIn, dOut))
        let cutoff = s.timestamp.addingTimeInterval(-60)
        windowSamples.removeAll { $0.time < cutoff }
        downLast60 = windowSamples.reduce(0) { $0 + $1.down }
        upLast60 = windowSamples.reduce(0) { $0 + $1.up }
        if isMobile { mobileToday += delta; pendingIface.mobile += delta } else { wifiToday += delta; pendingIface.wifi += delta }
    }

    private func persist() async {
        await usage.flush()
        let p = pendingIface
        pendingIface = (0, 0)
        await store.addInterfaceBytes(day: dayKey, mobile: true, bytes: p.mobile)
        await store.addInterfaceBytes(day: dayKey, mobile: false, bytes: p.wifi)
    }

    private func refreshProxy() {
        Task.detached(priority: .utility) {
            let r = ProxyDetector.detect()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.proxy = r
                self.pushConfig(force: false)
            }
        }
    }

    private func pushConfig(force: Bool) {
        let cfg = FilterConfig(proxyPorts: proxy.ports, proxyOwnerPaths: proxy.ownerPaths,
                               blockedOnMobile: prefs.blockedOnMobile, forceMobile: prefs.forceMobile,
                               limits: prefs.appLimits)
        // Bağlantı yeniden kurulmuş olabilir; değişmese de arada bir tekrar gönder.
        guard force || cfg != lastConfig || due(30) else { return }
        lastConfig = cfg
        filter.send(cfg)
    }

    private static func push(_ arr: inout [Double], _ v: Double) {
        arr.append(v)
        if arr.count > historyLength { arr.removeFirst(arr.count - historyLength) }
    }
}
