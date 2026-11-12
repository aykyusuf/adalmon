import AppKit
import Foundation
import Observation

/// En yeni Codex rollout dosyasını ucuzca bulur ve yalnızca kuyruğunu okur. Ağaç taranmaz: en yeni yıl/ay/gün klasörlerinden
/// en yeni iki gün klasörüne bakılır (dünden süren oturum dünün klasörüne yazmaya devam eder), dosya değişiklik zamanına göre seçilir.
struct CodexRolloutReader: Sendable {
    static let tailBytes = 128 * 1024
    var root: URL

    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/sessions", directoryHint: .isDirectory)
    }

    init(root: URL = Self.defaultRoot) { self.root = root }

    struct Candidate: Equatable, Sendable {
        var url: URL
        var modified: Date
        var size: Int
    }

    /// Değişiklik zamanına göre en yeni birkaç rollout dosyası (en yenisi önce).
    func newestRollouts(limit: Int = 3) -> [Candidate] {
        let manager = FileManager.default
        func numericChildren(_ url: URL) -> [URL] {
            ((try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
                .filter { Int($0.lastPathComponent) != nil }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        var dayDirs: [URL] = []
        outer: for year in numericChildren(root).prefix(2) {
            for month in numericChildren(year) {
                for day in numericChildren(month) {
                    dayDirs.append(day)
                    if dayDirs.count >= 2 { break outer }
                }
            }
        }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        var candidates: [Candidate] = []
        for dir in dayDirs {
            let files = (try? manager.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            for file in files where file.lastPathComponent.hasPrefix("rollout-") && file.pathExtension == "jsonl" {
                guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                      let modified = values.contentModificationDate else { continue }
                candidates.append(Candidate(url: file, modified: modified, size: values.fileSize ?? 0))
            }
        }
        return Array(candidates.sorted { $0.modified > $1.modified }.prefix(limit))
    }

    static func readTail(_ url: URL, maxBytes: Int = tailBytes) -> (data: Data, truncated: Bool)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
        return (data, start > 0)
    }

    /// En yeni dosyadan başlayarak `rate_limits` içeren son `token_count` olayını döner; hiçbiri yoksa nil.
    func latest() -> ProviderLimits? {
        for candidate in newestRollouts() {
            guard let tail = Self.readTail(candidate.url),
                  let limits = CodexRolloutParser.latest(tail: tail.data, truncated: tail.truncated, fallbackDate: candidate.modified) else { continue }
            return limits
        }
        return nil
    }
}

/// Abonelik limitleri: Claude (dinleyiciden gelen son değer, UserDefaults'ta kalıcı) + Codex (yerel dosya, istek üzerine okunur),
/// eşik ayarları ve bildirim takibi. Zamanlayıcı yalnızca bir limit görünümü (panel kartı) açıkken çalışır (en sık 3 dk'da bir);
/// ayrıca uygulama öne gelince okunur. Testte (AppEnvironment.isRunningTests) gözlemci kurulmaz, gerçek ~/.codex okunmaz.
@MainActor @Observable
final class SubscriptionLimitsModel {
    static let codexInterval: TimeInterval = 180
    /// Model kullanımı taraması: en sık dakikada bir (zorlama hariç); sayfa görünürken döngü 2 dk'da bir dener.
    static let usageMinInterval: TimeInterval = 60
    static let usageLoopInterval: TimeInterval = 120
    /// Sayfa açıldıktan sonra ilk model kullanımı taramasının gecikmesi (giriş animasyonu süresi).
    static let usageFirstDelay: Duration = .milliseconds(900)
    /// Değişmeyen Claude değerinde kalıcı zaman damgasının en sık yenilenme aralığı.
    static let unchangedRefresh: TimeInterval = 60
    private enum Key {
        static let claude = "subscriptionLimits.claude"
        static let thresholds = "subscriptionLimits.thresholds"
        static let tracker = "subscriptionLimits.alertTracker"
        static let codexEnabled = "subscriptionLimits.codexEnabled"
        static let forecastSensitivity = "subscriptionLimits.forecastSensitivity"
        static let forecastWarnings = "subscriptionLimits.forecastWarnings"
    }

    private(set) var claude: ProviderLimits?
    private(set) var codex: ProviderLimits?
    private(set) var claudeConnected = false
    private(set) var lastMessage: String?
    /// Claude planı (`~/.claude.json` → `oauthAccount`, yalnızca beş alan). Bellekte; yalnızca limit görünümü açıkken okunur.
    private(set) var claudePlan: ClaudeAccountPlan?
    /// Model bazında kullanım (yalnızca Limitler sayfası görünürken hesaplanır; sayfa kapanınca son değer kalır).
    private(set) var modelUsage: [LimitSource: ProviderModelUsage] = [:]
    var thresholds: LimitAlertThresholds { didSet { store(thresholds, Key.thresholds) } }
    /// Tahmin uyarısı duyarlılığı (USAGE-02). Ayrı anahtarda: eşik yapısının kayıtlı biçimi değişmesin.
    var forecastSensitivity: LimitForecastSensitivity {
        didSet { defaults.set(forecastSensitivity.rawValue, forKey: Key.forecastSensitivity) }
    }
    /// Örnek geçmişi yalnızca bellekte; değer gelince güncellenir (kart buradan okur, zamanlayıcı yok).
    private(set) var forecaster = LimitForecastEngine()
    var codexEnabled: Bool {
        didSet {
            defaults.set(codexEnabled, forKey: Key.codexEnabled)
            if codexEnabled { refreshCodex(force: true) } else { codex = nil }
        }
    }

    /// Bildirim gönderici (AppModel → AlertCenter.notify). Atanmamışsa bildirim gönderilmez.
    @ObservationIgnored var notify: ((String, String) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let binder: ClaudeStatusLineBinder
    @ObservationIgnored private let codexReader: CodexRolloutReader
    @ObservationIgnored private let planReader: ClaudePlanReader
    @ObservationIgnored private let usageStore: ModelUsageStore
    @ObservationIgnored private var usageViewers = 0
    @ObservationIgnored private var usageLoop: Task<Void, Never>?
    @ObservationIgnored private var usageWork: Task<[LimitSource: ProviderModelUsage], Never>?
    @ObservationIgnored private var lastUsageRefresh: Date?
    @ObservationIgnored private var planStamp: ClaudePlanReader.Stamp?
    @ObservationIgnored private var planReading = false
    @ObservationIgnored private var tracker: LimitAlertTracker
    @ObservationIgnored private var lastCodexCheck: Date?
    @ObservationIgnored private var codexReading = false
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var viewerLoop: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private let live: Bool

    init(defaults: UserDefaults = .standard, binder: ClaudeStatusLineBinder = ClaudeStatusLineBinder(),
         codexReader: CodexRolloutReader = CodexRolloutReader(), planReader: ClaudePlanReader = ClaudePlanReader(),
         usageStore: ModelUsageStore = ModelUsageStore(), live: Bool = !AppEnvironment.isRunningTests) {
        self.defaults = defaults
        self.binder = binder
        self.codexReader = codexReader
        self.planReader = planReader
        self.usageStore = usageStore
        self.live = live
        thresholds = Self.load(LimitAlertThresholds.self, Key.thresholds, defaults) ?? LimitAlertThresholds()
        tracker = Self.load(LimitAlertTracker.self, Key.tracker, defaults) ?? LimitAlertTracker()
        claude = Self.load(ProviderLimits.self, Key.claude, defaults)
        forecastSensitivity = defaults.string(forKey: Key.forecastSensitivity).flatMap(LimitForecastSensitivity.init(rawValue:)) ?? .medium
        codexEnabled = defaults.object(forKey: Key.codexEnabled) as? Bool ?? true
        forecaster.warnings = Self.load(LimitForecastWarnings.self, Key.forecastWarnings, defaults) ?? LimitForecastWarnings()
        guard live else { return }
        binder.repairWrapperIfNeeded()
        claudeConnected = binder.isConnected
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshCodex(force: false) }
        }
    }

    /// Kartta gösterilecek sağlayıcılar (verisi olanlar).
    var providers: [ProviderLimits] { [claude, codexEnabled ? codex : nil].compactMap { $0 } }

    // MARK: Claude

    /// Dinleyiciden gelen değer (yalnızca dört sayı). Değişmediyse yalnızca zaman damgası yenilenir.
    func ingestClaude(_ limits: ProviderLimits, now: Date = .now) {
        var limits = limits
        limits.observedAt = now
        // Birden çok oturum eski değeri yollayabilir: daha düşük/eski değer yok sayılır (observedAt da güncellenmez).
        if let current = claude {
            guard let merged = LimitMerge.monotonic(current: current, incoming: limits) else { return }
            limits = merged
        }
        // Sayılar aynıysa yeniden atama/yazma yok (kart yeniden çizilmesin); zaman damgası en çok dakikada bir tazelenir.
        if let current = claude, current.fiveHour == limits.fiveHour, current.weekly == limits.weekly,
           now.timeIntervalSince(current.observedAt) < Self.unchangedRefresh {
            evaluate(limits, now: now)
            return
        }
        claude = limits
        store(limits, Key.claude)
        evaluate(limits, now: now)
        evaluateForecast(limits, now: now)
    }

    func connectClaude() {
        do {
            switch try binder.connect() {
            case .connected(let backup):
                lastMessage = backup.map { "Bağlandı. Yedek: \($0.path)" } ?? "Bağlandı."
            case .alreadyConnected:
                lastMessage = "Zaten bağlı."
            default: break
            }
        } catch ClaudeStatusLineTransform.TransformError.invalidJSON {
            lastMessage = "~/.claude/settings.json okunamadı (geçerli JSON değil); dosyaya dokunulmadı."
        } catch {
            lastMessage = "Bağlanamadı: \(error.localizedDescription)"
        }
        claudeConnected = binder.isConnected
    }

    func disconnectClaude() {
        do {
            switch try binder.disconnect() {
            case .disconnected: lastMessage = "Bağlantı kaldırıldı; statusLine eski haline döndü."
            case .notOurs: lastMessage = "statusLine bu arada değiştirilmiş; settings.json'a dokunulmadı."
            case .notConnected: lastMessage = "Bağlı değildi."
            default: break
            }
        } catch {
            lastMessage = "Kaldırılamadı: \(error.localizedDescription)"
        }
        claudeConnected = binder.isConnected
    }

    var backupDirectory: URL { binder.backupDirectory }

    // MARK: Codex

    /// En sık `codexInterval`'da bir (force hariç) arka planda okur; dosya yoksa/biçim uymazsa gösterge sessizce gizlenir.
    func refreshCodex(force: Bool, now: Date = .now) {
        guard codexEnabled, !codexReading else { return }
        if !force, let last = lastCodexCheck, now.timeIntervalSince(last) < Self.codexInterval { return }
        lastCodexCheck = now
        codexReading = true
        let reader = codexReader
        Task {
            let result = await Task.detached(priority: .utility) { reader.latest() }.value
            codexReading = false
            guard codexEnabled else { return }
            guard var result else { codex = nil; return }
            if let current = codex {
                // Birden çok Codex oturumu: eski/düşük değer göstergeyi geri sarmasın.
                guard let merged = LimitMerge.monotonic(current: current, incoming: result) else { return }
                result = merged
            }
            codex = result
            evaluate(result, now: .now)
            evaluateForecast(result, now: .now)
        }
    }

    /// Kart görünürken çağrılır: hemen bir kez okur, görünür kaldıkça 3 dk'da bir yeniler.
    func addViewer() {
        viewers += 1
        guard live, viewers == 1 else { return }
        refreshCodex(force: false)
        refreshPlan()
        viewerLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.codexInterval), tolerance: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.refreshCodex(force: false)
                self?.refreshPlan()
            }
        }
    }

    func removeViewer() {
        viewers = max(0, viewers - 1)
        if viewers == 0 { viewerLoop?.cancel(); viewerLoop = nil }
    }

    // MARK: Model kullanımı

    /// Limitler sayfası görünürken çağrılır: hemen bir kez hesaplar, görünür kaldıkça 2 dk'da bir dener (en çok dakikada bir tarar).
    /// Sayfa kapanınca döngü ve süren tarama iptal edilir. Testte/önizlemede (live == false) hiçbir şey okunmaz.
    func addUsageViewer() {
        usageViewers += 1
        guard live, usageViewers == 1 else { return }
        usageLoop = Task { [weak self] in
            // Sayfanın giriş animasyonu (~1 sn) bitsin: ilk tarama (disk okuma + ayrıştırma) animasyonla çekişmesin.
            // Tarama zaten `.utility` arka plan görevinde; bu bekleme yalnızca ana iş parçacığındaki sonuç atamasını kaydırır.
            try? await Task.sleep(for: Self.usageFirstDelay)
            while !Task.isCancelled {
                self?.refreshModelUsage(force: false)
                try? await Task.sleep(for: .seconds(Self.usageLoopInterval), tolerance: .seconds(20))
            }
        }
    }

    func removeUsageViewer() {
        usageViewers = max(0, usageViewers - 1)
        guard usageViewers == 0 else { return }
        usageLoop?.cancel()
        usageLoop = nil
        usageWork?.cancel()
    }

    /// Pencereleri güncel limit verisinden çıkarır; dosyaları `.utility` öncelikli arka plan görevinde artımlı okur.
    func refreshModelUsage(force: Bool, now: Date = .now) {
        Task { await refreshModelUsageNow(force: force, now: now) }
    }

    func refreshModelUsageNow(force: Bool, now: Date = .now) async {
        guard usageWork == nil else { return }
        if !force, let last = lastUsageRefresh, now.timeIntervalSince(last) < Self.usageMinInterval { return }
        var jobs: [(LimitSource, [ModelUsageBuilder.Range])] = []
        for limits in providers { jobs.append((limits.source, ModelUsageBuilder.ranges(for: limits, now: now))) }
        guard !jobs.isEmpty else { return }
        lastUsageRefresh = now
        let store = usageStore
        let work = Task.detached(priority: .utility) { () -> [LimitSource: ProviderModelUsage] in
            var result: [LimitSource: ProviderModelUsage] = [:]
            for (source, ranges) in jobs {
                guard let since = ranges.map(\.start).min() else { continue }
                store.refresh(source, since: since, now: now, isCancelled: { Task.isCancelled })
                if Task.isCancelled { break }
                result[source] = ModelUsageBuilder.build(source: source, ranges: ranges, now: now) { store.aggregate(source, from: $0, to: $1) }
            }
            return result
        }
        usageWork = work
        let result = await work.value
        usageWork = nil
        for (source, usage) in result where modelUsage[source] != usage { modelUsage[source] = usage }
        if !codexEnabled { modelUsage[.codex] = nil }
    }

    // MARK: Plan

    /// Claude planını okur: önce yalnızca stat; dosya değişmediyse okunmaz. Okuma arka planda (`.utility`). Sürekli çalışmaz:
    /// yalnızca limit görünümü açılınca ve görünür kaldıkça mevcut 3 dk'lık döngüyle çağrılır.
    func refreshPlan() {
        guard !planReading else { return }
        planReading = true
        let reader = planReader, previous = planStamp
        Task {
            let result = await Task.detached(priority: .utility) { () -> (ClaudePlanReader.Stamp?, ClaudeAccountPlan?)? in
                let stamp = reader.stamp()
                if let stamp, stamp == previous { return nil }
                return (stamp, stamp == nil ? nil : reader.read())
            }.value
            planReading = false
            guard let (stamp, plan) = result else { return }
            planStamp = stamp
            if plan != claudePlan { claudePlan = plan }
        }
    }

    /// Ekranlar için plan rozetleri (Codex planı son rollout olayından gelir).
    var plans: [LimitSource: LimitPlan] {
        var result: [LimitSource: LimitPlan] = [:]
        if let claudePlan, let plan = LimitPlanMapper.claude(claudePlan) { result[.claude] = plan }
        if codexEnabled, let plan = LimitPlanMapper.codex(planType: codex?.planType) { result[.codex] = plan }
        return result
    }

    // MARK: Bildirim

    private func evaluate(_ limits: ProviderLimits, now: Date) {
        let before = tracker
        let alerts = tracker.evaluate(limits, thresholds: thresholds, now: now)
        if tracker != before { store(tracker, Key.tracker) }
        for alert in alerts { notify?(alert.title(), alert.body(now: now)) }
    }

    /// Geçmişe örnek ekler; tahmin uyarısı koşulları sağlanırsa pencere başına bir kez bildirir.
    /// Codex aynı olayı yeniden okursa (aynı `observedAt`) örnek eklenmez.
    private func evaluateForecast(_ limits: ProviderLimits, now: Date) {
        var engine = forecaster
        let alerts = engine.ingest(limits, sensitivity: forecastSensitivity, alertsEnabled: thresholds.notificationsEnabled, now: now)
        if engine.warnings != forecaster.warnings { store(engine.warnings, Key.forecastWarnings) }
        if engine != forecaster { forecaster = engine }
        for alert in alerts { notify?(alert.title(), alert.body(now: now)) }
    }

    /// Kart için: bu pencere için gösterilecek tahmin (yoksa nil). Veri eskiyse gösterilmez.
    func forecast(for provider: ProviderLimits, _ kind: LimitWindowKind, now: Date) -> LimitForecast? {
        guard !provider.isStale(now: now) else { return nil }
        return forecaster.forecast(provider.source, kind, sensitivity: forecastSensitivity, now: now)
    }

    // MARK: Kalıcılık

    private func store<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
