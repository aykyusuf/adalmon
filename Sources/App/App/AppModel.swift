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
    /// Kural motoru + kademeli limit (Faz A). Çıktısı `pushConfig` içinde elle ayarlarla birleştirilir.
    let rules = RuleEngine()
    /// Fiziksel arayüz deltaları: son dakikaların mobil hızı ve saatlik arayüz toplamları.
    @ObservationIgnored let traffic = TrafficTracker()

    private(set) var snapshot: SystemSnapshot?
    private(set) var cpuHistory: [Double] = []
    private(set) var gpuHistory: [Double] = []
    private(set) var memHistory: [Double] = []
    private(set) var downHistory: [Double] = []
    private(set) var upHistory: [Double] = []
    /// Zaman damgalı sistem metrik geçmişi (~10 dk, yalnızca sayı): Performans sekmesi açılır açılmaz çizer.
    let systemHistory = SystemHistoryBuffer()

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
    /// Dönem başından dünün sonuna kadar mobil toplam (`iface_daily`; açılışta, gün/dönem değişince bir kez okunur).
    private(set) var cycleUsedBeforeToday: UInt64 = 0

    var isMobile: Bool { path.isMobile(force: prefs.forceMobile) }
    /// Mobil toplamın uygulamalara yazılamayan kısmı (sistem, VPN, ölçüm farkı).
    var unattributedMobile: UInt64 { mobileToday > usage.attributedMobileToday ? mobileToday - usage.attributedMobileToday : 0 }

    @ObservationIgnored let store = UsageStore()
    @ObservationIgnored private(set) lazy var battery = BatteryMonitor(
        store: store, alertConfig: { [prefs] in prefs.batteryAlerts }, notify: { [alerts] in alerts.notify(title: $0, body: $1) })
    /// Pil Faz 2: Bluetooth / HID / iPhone & iPad pilleri.
    @ObservationIgnored private(set) lazy var devices = DeviceBatteryService(
        settings: { [prefs] in prefs.deviceSettings }, enabled: { [prefs] in prefs.deviceMonitoring },
        includeWifi: { [prefs] in prefs.deviceIncludeWifi }, deliver: { [weak self] in self?.battery.present($0) },
        defaults: .standard)
    /// Faz 3: süreç/kaynak geçmişi ve saatlik klasör taraması (dakikada bir arka plan örnekleyici).
    @ObservationIgnored private(set) lazy var resources = ResourceService(store: store)
    @ObservationIgnored private(set) lazy var widgets = WidgetPublisher.live()
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
    @ObservationIgnored private var cycleKey = ""
    @ObservationIgnored private var lastRuleOutput = RuleOutput()
    @ObservationIgnored private var lastPushedMobile = false
    @ObservationIgnored private var lastEffective: EffectiveConfig?
    /// Açılış durumu (bugünkü toplamlar, dönem tabanı, kural durumu) yüklenene kadar filtreye yapılandırma itilmez:
    /// uygulama yeniden başlarken filtre eski yapılandırmasını korur, sınırlar gevşemez ve sahte sıfırlama olmaz.
    @ObservationIgnored private var rulesReady = false

    init() {
        usage = UsageEngine(store: store)
        alerts.onBlock = { [weak self] app in self?.setBlocked(app, true, fromNotification: true) }
        installer.onFilterEnabled = { [weak self] in self?.startFilterWatchdog() }
    }

    func start() {
        Task {
            await usage.loadToday()
            rules.seed(today: usage.today, dayKey: dayKey)
            await store.pruneHourly()
            mobileToday = await store.interfaceBytes(day: dayKey, mobile: true)
            wifiToday = await store.interfaceBytes(day: dayKey, mobile: false)
            await refreshCycleBase()
            cycleKey = "\(prefs.billingCycleStartDay)|\(dayKey)"
            rulesReady = true
            evaluateRules([], now: .now)
            pushConfig(force: true) // ilk itme kıyas noktasıdır (sıfırlama yok)
            await installer.refresh()
            installer.observeSystemChanges()
            updateProxyWanted()
            installer.updateIfInstalled()
            if installer.state == .active { startFilterWatchdog() }
        }
        refreshProxy()
        scheduleTimer()
        observeInterval()
        resources.start()
        battery.onPowerStateChange = { [weak self] in self?.publishWidgets(forced: true) }
        battery.start()
        devices.start()
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
        // Yalnızca menü çubuğu paneli açıkken 1 sn; Dock ana penceresi görünürken de kullanıcının aralığı (pil).
        let interval = TimeInterval(panelVisible ? 1 : max(1, prefs.updateInterval))
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
        updateProxyWanted()
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

    private func scheduleReset(_ app: String, reason: ResetReason, quiet: Bool = false) {
        guard installer.state == .active else { return }
        resetTasks[app]?.cancel()
        resetTasks[app] = Task { [weak self] in
            // Yeni yapılandırmanın uzantıya ulaşması için kısa bekleme.
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await self?.performReset(app, reason: reason, quiet: quiet)
        }
    }

    /// Uygulamanın açık bağlantılarını hemen kes (bağlam menüsü / ayarlar).
    func resetConnections(for app: String) {
        resetTasks[app]?.cancel()
        resetTasks[app] = Task { [weak self] in await self?.performReset(app, reason: .manual) }
    }

    private func performReset(_ app: String, reason: ResetReason, quiet: Bool = false) async {
        let result = await Task.detached(priority: .utility) { ConnectionResetter.resetConnections(forApp: app) }.value
        guard !Task.isCancelled, !quiet else { return }
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

    // MARK: Kurallar, kademeli limit, bütçe (Faz A)

    /// Etkin hız sınırı proxy'si: yapılandırmaya göre (elle sınır, açık hız sınırı kuralı ya da kademeli limit varsa).
    /// Etkin duruma göre DEĞİL: kural tetiklenince proxy'yi ilk kez kurmak (onay istemi) ve açıp kapatmak yerine
    /// önceden hazır tutulur.
    private func updateProxyWanted() {
        let ladder = prefs.tierLadder
        let wanted = !prefs.appLimits.isEmpty
            || (ladder.enabled && ladder.slowLimit != nil)
            || prefs.usageRules.contains { $0.enabled && $0.action.isThrottle && $0.hasEffect }
        installer.setProxyWanted(wanted)
    }

    /// Her adımda: kural listesini eşitle, kovaları besle, değerlendir, olayları göster.
    private func evaluateRules(_ buckets: [UsageBucket], now: Date) {
        guard rulesReady else { return }
        let key = "\(prefs.billingCycleStartDay)|\(dayKey)"
        if key != cycleKey {
            cycleKey = key
            Task { await refreshCycleBase() }
        }
        rules.setRules(prefs.usageRules)
        rules.ingest(buckets, now: now)
        let monthly = prefs.monthlyCapBytes
        let input = RuleEngine.LadderInput(dayKey: dayKey, dailyUsed: mobileToday, dailyCap: prefs.dailyCapBytes,
                                           cycleUsed: monthly == nil ? nil : cycleUsedBeforeToday + mobileToday, monthlyCap: monthly)
        let events = rules.evaluate(now: now, tier: prefs.tierLadder, ladderInput: input,
                                    context: .init(ownAppKey: Bundle.main.bundlePath, proxyOwnerPaths: proxy.ownerPaths))
        if !events.isEmpty { handleRuleEvents(events) }
    }

    private func handleRuleEvents(_ events: [RuleEngine.Event]) {
        for event in events {
            switch event {
            case .ruleFired(let id, let app):
                guard let rule = prefs.usageRules.first(where: { $0.id == id }) else { continue }
                let title = rule.name.isEmpty ? AppCatalog.shared.name(for: app) : rule.name
                let what: String
                switch rule.action {
                case .block: what = "mobil veride engellendi"
                case .throttle:
                    let parts = [rule.action.limit(scope: rule.scope)?.downBytesPerSec.map { "↓ \(Self.rateText($0))" },
                                 rule.action.limit(scope: rule.scope)?.upBytesPerSec.map { "↑ \(Self.rateText($0))" }]
                        .compactMap { $0 }.joined(separator: " ")
                    what = "hız sınırı: \(parts)"
                }
                let name = AppCatalog.shared.name(for: app)
                showToast(Toast(message: "Kural devrede: \(name) \(what)", undoApp: nil, undoBlocked: false))
                alerts.notify(title: "Kural devrede: \(title)", body: "\(name) \(what).")
            case .ruleLifted(let id, let app):
                guard let rule = prefs.usageRules.first(where: { $0.id == id }) else { continue }
                showToast(Toast(message: "Kural kalktı: \(AppCatalog.shared.name(for: app)) (\(rule.name.isEmpty ? "kural" : rule.name))",
                                undoApp: nil, undoBlocked: false))
            case .ladderReached(let level):
                let pct = rules.ladderStatus.percent
                switch level {
                case .none: break
                case .warn:
                    alerts.notify(title: "Mobil veri uyarısı: %\(pct)",
                                  body: "Günlük mobil verinin %\(pct)'ine ulaştın (\(Format.bytes(mobileToday)) / \(Format.bytes(prefs.dailyCapBytes))).")
                case .slow:
                    alerts.notify(title: "Mobil veri yavaşlatıldı",
                                  body: "%\(pct) kullanıldı; diğer uygulamalar yavaşlatıldı.")
                case .cut:
                    let n = rules.ladderStatus.blockedApps.count
                    alerts.notify(title: "Mobil veri kesildi",
                                  body: "%\(pct) kullanıldı; en çok kullanan \(n) uygulama engellendi.")
                }
            }
        }
    }

    /// Etkin yapılandırma önceki adımdan daha kısıtlayıcıysa (kural/merdiven devreye girdi, ağ değişti) ilgili
    /// uygulamaların açık bağlantılarını yeniler. Birden çoğu ise tek özet toast (sessiz sıfırlama).
    private func resetForEffectiveChange(_ eff: EffectiveConfig) {
        let prev = lastEffective
        lastEffective = eff
        guard let prev, installer.state == .active else { return }
        let onMobile = isMobile
        var targets: [(String, ResetReason)] = []
        for (app, l) in eff.limits.sorted(by: { $0.key < $1.key })
        where EffectiveConfigBuilder.isStricter(l, than: prev.limits[app]) && (!l.onlyOnMobile || onMobile) {
            targets.append((app, .limit))
        }
        if onMobile {
            for app in eff.blocked where !prev.blocked.contains(app) { targets.append((app, .block)) }
        }
        // Her ağda engellenenler (Wi-Fi dahil): yeni eklenenin açık bağlantıları da yenilenir.
        for app in eff.blockedAlways.sorted() where !prev.blockedAlways.contains(app) && !targets.contains(where: { $0.0 == app && $0.1 == .block }) {
            targets.append((app, .block))
        }
        guard !targets.isEmpty else { return }
        let quiet = targets.count > 1
        for (app, reason) in targets { scheduleReset(app, reason: reason, quiet: quiet) }
        if quiet {
            showToast(Toast(message: "\(targets.count) uygulamanın açık bağlantıları yenileniyor (kural/limit)", undoApp: nil, undoBlocked: false))
        }
    }

    private func refreshCycleBase() async {
        let cal = UsageStore.keyCalendar
        let now = Date.now
        let start = BudgetCalculator.cycleStart(containing: now, startDay: prefs.billingCycleStartDay, calendar: cal)
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now)) ?? now
        cycleUsedBeforeToday = await store.interfaceBytes(fromDay: BudgetCalculator.dayKey(start, calendar: cal),
                                                          toDay: BudgetCalculator.dayKey(yesterday, calendar: cal), mobile: true)
    }

    /// Fatura dönemi bütçesi ve limit dolma tahmini (sorgu yok; bellek içi).
    func budget(now: Date = .now) -> BudgetSnapshot {
        BudgetCalculator.snapshot(now: now, startDay: prefs.billingCycleStartDay, monthlyCapBytes: prefs.monthlyCapBytes,
                                  dailyCapBytes: prefs.dailyCapBytes, cycleUsedBeforeToday: cycleUsedBeforeToday,
                                  todayUsed: mobileToday, recentRate: traffic.recentMobileRate(now: now),
                                  calendar: UsageStore.keyCalendar)
    }

    /// Bugünün kümülatif mobil kullanım serisi (grafik). Saatlik arayüz toplamlarından; en fazla ~10 sn gecikmeli.
    func todayMobileCumulativeSeries(now: Date = .now) async -> [CumulativePoint] {
        let cal = UsageStore.keyCalendar
        let start = cal.startOfDay(for: now)
        // Yerel gün sınırları (DST'de 23/25 saat olabilir); +86400 değil takvimle.
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let dayStart = Int(start.timeIntervalSince1970)
        let pts = await store.interfaceHourly(from: dayStart, to: Int(end.timeIntervalSince1970))
        var hourly: [Int: UInt64] = [:]
        for p in pts { hourly[p.hour] = p.mobileBytes }
        return BudgetCalculator.cumulativeSeries(hourly: hourly, now: now, calendar: cal)
    }

    /// Kural durumları (UI): sayaçlar, pencere sonuna kalan süre, uygulanıyor mu.
    func ruleStatuses(now: Date = .now) -> [RuleStatus] {
        rules.statuses(now: now, onMobile: isMobile)
    }

    /// Kural listesi UI'dan değişince hemen uygula (yoksa bir sonraki ölçümde uygulanır).
    func rulesDidChange() {
        evaluateRules([], now: .now)
        pushConfig(force: false)
    }

    // MARK: Loop

    /// Panel açıkken 1 sn, kapalıyken `prefs.updateInterval` sn'de bir örnekle (pil).
    /// Her ölçüm adımının sonunda çağrılır (menü çubuğu çizimi).
    @ObservationIgnored var onStep: (() -> Void)?

    /// Ana pencere (Dock modu) açıkken de saniyede bir örnekle.
    @ObservationIgnored var mainWindowVisible = false {
        didSet {
            scheduleTimer()
            applyBatteryVisibility()
            if mainWindowVisible && !oldValue { Task { await step() } }
        }
    }

    @ObservationIgnored var panelVisible = false {
        didSet {
            scheduleTimer()
            applyBatteryVisibility()
            if panelVisible && !oldValue { Task { await step() } }
        }
    }

    /// Açık panelin içeriği. Pil okuması ve cihaz taraması yalnızca Pil/Birleşik panelde çalışır
    /// (CPU paneli açılınca Bluetooth taranmaz); içerik değişince yeniden uygulanır.
    @ObservationIgnored var panelKind: PanelKind = .combined {
        didSet { if panelKind != oldValue { applyBatteryVisibility() } }
    }

    private func applyBatteryVisibility() {
        let panelWantsBattery = panelVisible && panelKind.needsBatterySampling
        battery.setVisible(mainWindowVisible || panelWantsBattery)
        devices.setPanelVisible(panelWantsBattery)
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
        let connected = filter.isConnected && installer.state == .active
        if connected != filterConnected { filterConnected = connected }
        usage.ingest(buckets, seconds: elapsed)
        alerts.checkBursts(usage.last60, threshold: prefs.burstThresholdBytes, isMobile: isMobile)
        // Kademeli limit açıkken uyarı bildirimlerini merdiven yönetir (çift bildirim olmasın).
        if !prefs.tierLadder.enabled { alerts.checkCap(used: mobileToday, cap: prefs.dailyCapBytes) }
        evaluateRules(buckets, now: .now)

        if due(15) {
            // Ucuz kontrol; süreç taraması sadece port değişince ya da 5 dk'da bir.
            let ports = ProxyDetector.localProxyPorts()
            // Sahip henüz bulunamadıysa (SpoofDPI geç açıldı / yol değişti) dakikada bir yeniden dene.
            if ports != proxy.ports || (!ports.isEmpty && ((proxy.ownerPaths.isEmpty && due(60)) || due(300))) { refreshProxy() }
        }
        if due(5) || rules.output != lastRuleOutput || isMobile != lastPushedMobile { pushConfig(force: false) }
        if due(10) { await persist() }
        lastUpdate = .now
        publishWidgets()
        onStep?()
    }

    // MARK: Widget anlık görüntüsü

    /// Widget'ların okuduğu özet. Yalnızca yazma zamanı geldiğinde kurulur (bkz. `WidgetPublishGate`).
    func widgetSnapshot(now: Date = .now) -> WidgetSnapshot {
        let monthly = prefs.monthlyCapBytes
        let hidden = Set(prefs.deviceSettings.filter { $0.value.hidden }.keys)
        return WidgetSnapshotBuilder.make(
            now: now, battery: battery.reading, devices: devices.devices, hiddenDeviceIDs: hidden,
            pinnedDeviceIDs: prefs.menuBar.config.components.compactMap(\.deviceID), system: snapshot,
            mobileToday: mobileToday, dailyCap: prefs.dailyCapBytes,
            cycleUsed: monthly == nil ? nil : cycleUsedBeforeToday + mobileToday, monthlyCap: monthly, isOnMobile: isMobile)
    }

    private func publishWidgets(forced: Bool = false) {
        widgets.tick(forced: forced) { [self] in widgetSnapshot() }
    }

    /// Yeni ölçümü yayınlar (testler/önizlemeler de gerçek bir ölçümü buradan verir).
    func apply(_ s: SystemSnapshot) {
        snapshot = s
        battery.setTemperature(s.temperature?.battery)
        systemHistory.append(s, notify: mainWindowVisible || panelVisible)
        Self.push(&cpuHistory, s.cpu.total)
        Self.push(&gpuHistory, s.gpu?.displayLoad ?? 0)
        Self.push(&memHistory, s.memory.usedFraction)
        Self.push(&downHistory, s.network.downloadBytesPerSecond)
        Self.push(&upHistory, s.network.uploadBytesPerSecond)

        // Fiziksel arayüz deltası → bugünkü mobil / Wi-Fi toplamı.
        let today = UsageStore.dayKey()
        if today != dayKey { dayKey = today; cycleUsedBeforeToday += mobileToday; mobileToday = 0; wifiToday = 0; downToday = 0; upToday = 0 }
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
        traffic.add(bytes: delta, mobile: isMobile, at: s.timestamp)
    }

    private func persist() async {
        await usage.flush()
        let p = pendingIface
        pendingIface = (0, 0)
        await store.addInterfaceBytes(day: dayKey, mobile: true, bytes: p.mobile)
        await store.addInterfaceBytes(day: dayKey, mobile: false, bytes: p.wifi)
        await store.addInterfaceHourly(traffic.drainHourly())
        rules.persistIfNeeded()
    }

    private func refreshProxy() {
        Task.detached(priority: .utility) {
            let r = ProxyDetector.detect()
            await MainActor.run { [weak self] in
                guard let self else { return }
                if r != self.proxy { self.proxy = r }
                self.pushConfig(force: false)
            }
        }
    }

    private func pushConfig(force: Bool) {
        guard rulesReady else { return }
        // Elle ayarlar + kural/merdiven çıktısı; prefs'e yazılmaz, en kısıtlayıcı kazanır.
        let eff = EffectiveConfigBuilder.build(manualLimits: prefs.appLimits, manualBlocked: prefs.blockedOnMobile,
                                               output: rules.output, onMobile: isMobile)
        lastRuleOutput = rules.output
        lastPushedMobile = isMobile
        updateProxyWanted()
        resetForEffectiveChange(eff)
        let cfg = FilterConfig(proxyPorts: proxy.ports, proxyOwnerPaths: proxy.ownerPaths,
                               blockedOnMobile: eff.blocked, forceMobile: prefs.forceMobile,
                               limits: eff.limits, blockedAlways: eff.blockedAlways,
                               // Proxy sahibi bilinmeden Veri Tasarrufu açılmaz: SpoofDPI'ın kendi akışı engellenebilir.
                               dataSaverActive: prefs.dataSaver.enabled && (proxy.ports.isEmpty || !proxy.ownerPaths.isEmpty),
                               dataSaverAllow: Set(prefs.dataSaver.allowlist))
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
