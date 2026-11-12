import Foundation

// Abonelik limitleri (USAGE-01): Claude Code 5 saat / haftalık (statusLine JSON'u → yerel dinleyici) ve Codex (yerel rollout dosyası).
// Bu dosyadaki her şey saf mantıktır (ağ, dosya, zamanlayıcı yok) ve testlidir. Hesap/plan kimliği hiçbir yerde tutulmaz.

enum LimitSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case claude, codex

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

enum LimitWindowKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case fiveHour, weekly

    var id: String { rawValue }
    var label: String {
        switch self {
        case .fiveHour: "5 saat"
        case .weekly: "Haftalık"
        }
    }

    /// Bildirim metni için ("5 saatlik limit", "haftalık limit").
    var noun: String {
        switch self {
        case .fiveHour: "5 saatlik limit"
        case .weekly: "haftalık limit"
        }
    }
}

struct LimitWindow: Codable, Equatable, Sendable {
    /// 0–100 (kullanılan yüzde).
    var usedPercent: Double
    var resetsAt: Date?

    /// Yenilenme anı geçtiyse pencere sıfırlanmıştır; eski yüzde artık geçerli değildir.
    func isReset(now: Date) -> Bool { resetsAt.map { $0 <= now } ?? false }
}

struct ProviderLimits: Codable, Equatable, Sendable {
    var source: LimitSource
    var fiveHour: LimitWindow?
    var weekly: LimitWindow?
    /// Değerin kaynağında gözlendiği an (Claude: dinleyiciye ulaştığı an; Codex: olayın zaman damgası).
    var observedAt: Date
    /// Yalnızca Codex: ChatGPT kredisi bakiyesi (varsa, sınırsız değilse). API kredisi DEĞİLDİR.
    var creditsBalance: Double?

    static let staleAfter: TimeInterval = 30 * 60

    func window(_ kind: LimitWindowKind) -> LimitWindow? {
        switch kind {
        case .fiveHour: fiveHour
        case .weekly: weekly
        }
    }

    func isStale(now: Date) -> Bool { now.timeIntervalSince(observedAt) > Self.staleAfter }
}

// MARK: Claude (dinleyiciye gelen gövde)

/// statusLine sarmalayıcısının gönderdiği düz gövde: yalnızca dört sayı
/// (`five_hour_used`, `five_hour_resets_at`, `seven_day_used`, `seven_day_resets_at`). Başka alan okunmaz.
enum ClaudeLimitsPayload {
    static func parse(_ data: Data, now: Date) -> ProviderLimits? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let five = window(used: object["five_hour_used"], resets: object["five_hour_resets_at"])
        let week = window(used: object["seven_day_used"], resets: object["seven_day_resets_at"])
        guard five != nil || week != nil else { return nil }
        return ProviderLimits(source: .claude, fiveHour: five, weekly: week, observedAt: now)
    }

    static func window(used: Any?, resets: Any?) -> LimitWindow? {
        guard let used = number(used), used.isFinite, (-1...1000).contains(used) else { return nil }
        return LimitWindow(usedPercent: min(100, max(0, used)), resetsAt: epoch(resets))
    }

    static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        return value.doubleValue
    }

    /// Makul epoch saniyesi (2001–2286); değilse nil.
    static func epoch(_ value: Any?) -> Date? {
        guard let seconds = number(value), seconds.isFinite, seconds > 1_000_000_000, seconds < 10_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

// MARK: Codex (rollout dosyasının kuyruğu)

/// `~/.codex/sessions/**/rollout-*.jsonl` belgesiz biçim. En son `token_count` olayının `rate_limits` alanından yalnızca
/// `used_percent`, `window_minutes`, `resets_at` (ya da eski `resets_in_seconds`) ve kredi bakiyesi okunur; `limit_id`/`plan_type`
/// gibi alanlar çözülmez bile. Herhangi bir uyumsuzlukta nil (gösterge sessizce gizlenir).
enum CodexRolloutParser {
    private struct Line: Decodable {
        let timestamp: String?
        let payload: Payload?
    }

    private struct Payload: Decodable {
        let type: String?
        let rate_limits: RateLimits?
    }

    private struct RateLimits: Decodable {
        let primary: Window?
        let secondary: Window?
        let credits: Credits?
    }

    private struct Window: Decodable {
        let used_percent: Double?
        let window_minutes: Int?
        let resets_at: Double?
        let resets_in_seconds: Double?
    }

    private struct Credits: Decodable {
        let has_credits: Bool?
        let unlimited: Bool?
        let balance: Double?

        private enum CodingKeys: String, CodingKey { case has_credits, unlimited, balance }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            has_credits = try? c.decodeIfPresent(Bool.self, forKey: .has_credits)
            unlimited = try? c.decodeIfPresent(Bool.self, forKey: .unlimited)
            if let number = try? c.decodeIfPresent(Double.self, forKey: .balance) {
                balance = number
            } else if let text = try? c.decodeIfPresent(String.self, forKey: .balance) {
                balance = Double(text.trimmingCharacters(in: .whitespaces))
            } else {
                balance = nil
            }
        }
    }

    /// `tail`: dosyanın son baytları. `truncated`: kuyruk dosyanın ortasından başlıyorsa ilk (yarım) satır atlanır.
    /// `fallbackDate`: olayın zaman damgası okunamazsa (ör. dosya değişiklik zamanı).
    static func latest(tail: Data, truncated: Bool, fallbackDate: Date) -> ProviderLimits? {
        var lines = tail.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if truncated, !lines.isEmpty { lines.removeFirst() }
        let marker = Data("token_count".utf8), rateMarker = Data("rate_limits".utf8)
        let decoder = JSONDecoder()
        for line in lines.reversed() {
            guard line.range(of: marker) != nil, line.range(of: rateMarker) != nil else { continue }
            guard let decoded = try? decoder.decode(Line.self, from: Data(line)),
                  decoded.payload?.type == "token_count", let limits = decoded.payload?.rate_limits else { continue }
            let observed = decoded.timestamp.flatMap(parseTimestamp) ?? fallbackDate
            if let result = build(limits, observed: observed) { return result }
        }
        return nil
    }

    private static func build(_ limits: RateLimits, observed: Date) -> ProviderLimits? {
        var result = ProviderLimits(source: .codex, observedAt: observed)
        for (index, raw) in [limits.primary, limits.secondary].enumerated() {
            guard let raw, let used = raw.used_percent, used.isFinite, (-1...1000).contains(used) else { continue }
            let resets: Date? = if let at = raw.resets_at, at > 1_000_000_000, at < 10_000_000_000 {
                Date(timeIntervalSince1970: at)
            } else if let seconds = raw.resets_in_seconds, seconds >= 0, seconds < 60 * 86_400 {
                observed.addingTimeInterval(seconds)
            } else {
                nil
            }
            let window = LimitWindow(usedPercent: min(100, max(0, used)), resetsAt: resets)
            let kind: LimitWindowKind = if let minutes = raw.window_minutes {
                minutes <= 12 * 60 ? .fiveHour : .weekly
            } else {
                index == 0 ? .fiveHour : .weekly
            }
            switch kind {
            case .fiveHour where result.fiveHour == nil: result.fiveHour = window
            case .weekly where result.weekly == nil: result.weekly = window
            default: break
            }
        }
        guard result.fiveHour != nil || result.weekly != nil else { return nil }
        if let credits = limits.credits, credits.has_credits == true, credits.unlimited != true,
           let balance = credits.balance, balance.isFinite, balance >= 0 {
            result.creditsBalance = balance
        }
        return result
    }

    static func parseTimestamp(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}

// MARK: Eşikler ve bildirim

enum LimitLevel: Int, Codable, Comparable, Sendable {
    case normal, warning, critical

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

struct LimitAlertThresholds: Codable, Equatable, Sendable {
    var notificationsEnabled = true
    var fiveHourWarn: Double = 80
    var fiveHourCritical: Double = 95
    var weeklyWarn: Double = 80
    var weeklyCritical: Double = 95

    static let range: ClosedRange<Double> = 5...100

    func level(for used: Double, kind: LimitWindowKind) -> LimitLevel {
        let (warn, critical) = switch kind {
        case .fiveHour: (fiveHourWarn, fiveHourCritical)
        case .weekly: (weeklyWarn, weeklyCritical)
        }
        if used >= max(critical, warn) { return .critical }
        if used >= min(warn, critical) { return .warning }
        return .normal
    }
}

struct LimitAlert: Equatable, Sendable {
    var source: LimitSource
    var kind: LimitWindowKind
    var level: LimitLevel
    var usedPercent: Double
    var resetsAt: Date?

    func title() -> String {
        let percent = LimitFormat.percent(usedPercent)
        return switch level {
        case .critical: "\(source.displayName) \(kind.noun) neredeyse doldu: \(percent)"
        default: "\(source.displayName) \(kind.noun): \(percent) kullanıldı"
        }
    }

    func body(now: Date) -> String {
        resetsAt.map { LimitFormat.resetText($0, now: now) } ?? "Yenilenme zamanı bilinmiyor."
    }
}

/// Pencere başına (kaynak + tür + yenilenme anı) gönderilen en yüksek seviye. Her pencerede uyarı ve kritik en çok birer kez;
/// kritik gönderildiyse uyarı bir daha gönderilmez. Yenilenme anı ±10 dk oynarsa aynı pencere sayılır.
struct LimitAlertTracker: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var source: LimitSource
        var kind: LimitWindowKind
        var resetsAt: Date?
        var level: LimitLevel
    }

    static let sameWindowTolerance: TimeInterval = 10 * 60
    var entries: [Entry] = []

    mutating func evaluate(_ limits: ProviderLimits, thresholds: LimitAlertThresholds, now: Date) -> [LimitAlert] {
        // Bir günden eski pencereleri unut.
        entries.removeAll { ($0.resetsAt ?? .distantFuture) < now.addingTimeInterval(-86_400) }
        guard thresholds.notificationsEnabled, !limits.isStale(now: now) else { return [] }
        var alerts: [LimitAlert] = []
        for kind in LimitWindowKind.allCases {
            // Yenilenme anı bilinmeyen pencere kullanım eşiğin altına inince (ya da kalkınca) yeniden silahlanır.
            func rearmUnknownReset() {
                entries.removeAll { $0.source == limits.source && $0.kind == kind && $0.resetsAt == nil }
            }
            guard let window = limits.window(kind), !window.isReset(now: now) else { rearmUnknownReset(); continue }
            let level = thresholds.level(for: window.usedPercent, kind: kind)
            guard level > .normal else { rearmUnknownReset(); continue }
            let index = entries.firstIndex { entry in
                guard entry.source == limits.source, entry.kind == kind else { return false }
                switch (entry.resetsAt, window.resetsAt) {
                case (nil, nil): return true
                case let (a?, b?): return abs(a.timeIntervalSince(b)) <= Self.sameWindowTolerance
                default: return false
                }
            }
            if let index {
                guard level > entries[index].level else { continue }
                entries[index].level = level
            } else {
                entries.append(Entry(source: limits.source, kind: kind, resetsAt: window.resetsAt, level: level))
            }
            alerts.append(LimitAlert(source: limits.source, kind: kind, level: level, usedPercent: window.usedPercent, resetsAt: window.resetsAt))
        }
        return alerts
    }
}

// MARK: Biçim

enum LimitFormat {
    static func percent(_ value: Double) -> String { "%\(Int(value.rounded()))" }

    /// "2 sa 10 dk sonra yenilenir", "3 gün 4 sa sonra yenilenir", "1 dk içinde yenilenir"; geçmişse "Yenilendi".
    static func resetText(_ date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "Yenilendi" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes <= 1 { return "1 dk içinde yenilenir" }
        return "\(duration(minutes: minutes)) sonra yenilenir"
    }

    /// "şimdi", "5 dk önce", "2 sa önce", "3 gün önce".
    static func ageText(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "şimdi" }
        if minutes < 60 { return "\(minutes) dk önce" }
        if minutes < 24 * 60 { return "\(minutes / 60) sa önce" }
        return "\(minutes / (24 * 60)) gün önce"
    }

    static func duration(minutes: Int) -> String {
        let days = minutes / (24 * 60), hours = (minutes % (24 * 60)) / 60, mins = minutes % 60
        if days > 0 { return hours > 0 ? "\(days) gün \(hours) sa" : "\(days) gün" }
        if hours > 0 { return mins > 0 ? "\(hours) sa \(mins) dk" : "\(hours) sa" }
        return "\(mins) dk"
    }
}
