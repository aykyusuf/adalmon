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
    @ObservationIgnored private var tracker: LimitAlertTracker
    @ObservationIgnored private var lastCodexCheck: Date?
    @ObservationIgnored private var codexReading = false
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var viewerLoop: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private let live: Bool

    init(defaults: UserDefaults = .standard, binder: ClaudeStatusLineBinder = ClaudeStatusLineBinder(),
         codexReader: CodexRolloutReader = CodexRolloutReader(), live: Bool = !AppEnvironment.isRunningTests) {
        self.defaults = defaults
        self.binder = binder
        self.codexReader = codexReader
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
            codex = result
            if let result { evaluate(result, now: .now); evaluateForecast(result, now: .now) }
        }
    }

    /// Kart görünürken çağrılır: hemen bir kez okur, görünür kaldıkça 3 dk'da bir yeniler.
    func addViewer() {
        viewers += 1
        guard live, viewers == 1 else { return }
        refreshCodex(force: false)
        viewerLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.codexInterval), tolerance: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.refreshCodex(force: false)
            }
        }
    }

    func removeViewer() {
        viewers = max(0, viewers - 1)
        if viewers == 0 { viewerLoop?.cancel(); viewerLoop = nil }
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
