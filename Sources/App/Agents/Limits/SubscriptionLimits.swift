import Foundation

// Abonelik limitleri (USAGE-01): Claude Code 5 saat / haftalık (statusLine JSON'u → yerel dinleyici) ve Codex (yerel rollout dosyası).
// Bu dosyadaki her şey saf mantıktır (ağ, dosya, zamanlayıcı yok) ve testlidir. Hesap kimliği hiçbir yerde tutulmaz;
// yalnızca plan adı okunur (bkz. LimitPlan.swift: Claude için ~/.claude.json'dan beş alan, Codex için olaydaki `plan_type`).

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
    /// Yalnızca Codex: rollout olayındaki `plan_type` ("plus", "pro" …). Hesap kimliği değildir; yalnızca plan adı.
    var planType: String?

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

/// statusLine sarmalayıcısının gönderdiği gövde: Claude Code'un `rate_limits` nesnesinin ham JSON metni. Yalnızca
/// `five_hour`/`seven_day` altındaki `used_percentage` ve `resets_at` çözülür (dört sayı); başka alan çözülmez ve saklanmaz.
enum ClaudeLimitsPayload {
    static let maxBytes = 4 * 1024

    private struct RateLimits: Decodable {
        let five_hour: Window?
        let seven_day: Window?
    }

    private struct Window: Decodable {
        let used: Double?
        let resets: Double?

        private enum CodingKeys: String, CodingKey { case used_percentage, resets_at }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            used = try? c.decodeIfPresent(Double.self, forKey: .used_percentage)
            resets = try? c.decodeIfPresent(Double.self, forKey: .resets_at)
        }
    }

    static func parse(_ data: Data, now: Date) -> ProviderLimits? {
        guard data.count <= maxBytes, let decoded = try? JSONDecoder().decode(RateLimits.self, from: data) else { return nil }
        let five = window(used: decoded.five_hour?.used, resets: decoded.five_hour?.resets)
        let week = window(used: decoded.seven_day?.used, resets: decoded.seven_day?.resets)
        guard five != nil || week != nil else { return nil }
        return ProviderLimits(source: .claude, fiveHour: five, weekly: week, observedAt: now)
    }

    static func window(used: Double?, resets: Double?) -> LimitWindow? {
        guard let used, used.isFinite, (-1...1000).contains(used) else { return nil }
        return LimitWindow(usedPercent: min(100, max(0, used)), resetsAt: epoch(resets))
    }

    /// Makul epoch saniyesi (2001–2286); değilse nil.
    static func epoch(_ seconds: Double?) -> Date? {
        guard let seconds, seconds.isFinite, seconds > 1_000_000_000, seconds < 10_000_000_000 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

// MARK: Codex (rollout dosyasının kuyruğu)

/// `~/.codex/sessions/**/rollout-*.jsonl` belgesiz biçim. En son `token_count` olayının `rate_limits` alanından yalnızca
/// `used_percent`, `window_minutes`, `resets_at` (ya da eski `resets_in_seconds`), kredi bakiyesi ve plan adı (`plan_type`)
/// okunur; `limit_id` gibi alanlar çözülmez bile. Herhangi bir uyumsuzlukta nil (gösterge sessizce gizlenir).
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
        let plan_type: String?

        private enum CodingKeys: String, CodingKey { case primary, secondary, credits, plan_type }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            primary = try c.decodeIfPresent(Window.self, forKey: .primary)
            secondary = try c.decodeIfPresent(Window.self, forKey: .secondary)
            credits = try c.decodeIfPresent(Credits.self, forKey: .credits)
            // Plan adı yardımcı bilgidir: beklenmedik türde olsa bile limit okumasını bozmasın.
            plan_type = try? c.decodeIfPresent(String.self, forKey: .plan_type)
        }
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
        result.planType = limits.plan_type.flatMap { LimitPlanMapper.codex(planType: $0) != nil ? $0.lowercased() : nil }
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

// MARK: Çok oturumlu birleştirme

/// Birden çok Claude Code / Codex oturumu açıkken her oturum kendi SON gördüğü `rate_limits`'i gönderir: boşta oturum eski (düşük) değeri,
/// aktif oturum güncel değeri yollar ve gösterge zıplar. Pencere başına monoton birleştirme: aynı yenilenme anı (±60 sn) için kullanılan
/// yüzde yalnızca ARTABİLİR; daha yeni (ileri) yenilenme anı yeni pencere sayılır ve değer kabul edilir; daha eski yenilenme anı yok sayılır.
/// 5 saatlik ve haftalık ayrı değerlendirilir.
enum LimitMerge {
    static let resetTolerance: TimeInterval = 60

    /// Gelen değerin mevcutla birleşmiş hali. Hiçbir pencere kabul edilmediyse (hepsi daha düşük/eski) nil: mevcut değer ve `observedAt` değişmez.
    static func monotonic(current: ProviderLimits, incoming: ProviderLimits) -> ProviderLimits? {
        var result = incoming
        var accepted = false
        for kind in LimitWindowKind.allCases {
            guard let new = incoming.window(kind) else { continue }
            guard let old = current.window(kind) else { accepted = true; continue }
            let merged: LimitWindow?
            switch (old.resetsAt, new.resetsAt) {
            case let (oldReset?, newReset?):
                if newReset.timeIntervalSince(oldReset) > resetTolerance {
                    merged = new
                } else if oldReset.timeIntervalSince(newReset) > resetTolerance {
                    merged = nil
                } else if new.usedPercent >= old.usedPercent {
                    merged = LimitWindow(usedPercent: new.usedPercent, resetsAt: max(oldReset, newReset))
                } else {
                    merged = nil
                }
            case (nil, _):
                merged = new
            case (_?, nil):
                merged = nil
            }
            if let merged { accepted = true; set(&result, kind, merged) } else { set(&result, kind, old) }
        }
        guard accepted else { return nil }
        // Gelen pencere kalmadıysa (ör. yalnızca eski pencere değeri geldi) mevcut kredi/plan bilgisi korunur.
        if result.planType == nil { result.planType = current.planType }
        return result
    }

    private static func set(_ limits: inout ProviderLimits, _ kind: LimitWindowKind, _ window: LimitWindow) {
        switch kind {
        case .fiveHour: limits.fiveHour = window
        case .weekly: limits.weekly = window
        }
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
