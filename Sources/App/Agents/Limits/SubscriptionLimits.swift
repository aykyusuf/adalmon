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

/// Sunucunun bildirdiği ücretsiz sıfırlama hakkı (salt bilgi). `id` alanı bilerek yoktur.
struct LimitResetCredit: Codable, Equatable, Sendable {
    var title: String?
    var detail: String?
    /// Ham tür ("codexRateLimits" …); ekranda `LimitResetCreditDisplay.typeText` ile Türkçeleştirilir.
    var resetType: String?
    /// "available", "redeeming", "redeemed", "unknown".
    var status: String
    var grantedAt: Date?
    var expiresAt: Date?
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
    /// Yalnızca Codex: değer `codex app-server`'dan (canlı) geldi. Rollout dosyasından gelenlerde nil.
    var isLive: Bool?
    /// Yalnızca Codex (canlı): ücretsiz sıfırlama hakları (yalnızca bilgi; hiçbir yerde kullanılmaz/tüketilmez). Hak kimliği tutulmaz.
    var resetCreditCount: Int?
    var resetCredits: [LimitResetCredit]?
    /// Yalnızca Codex (canlı): sunucu "limit doldu" bildirdi (`rateLimitReachedType` dolu).
    var limitReached: Bool?

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

/// Dinleyiciye gelen tek Claude limit mesajı: dört sayı + (yeni sarmalayıcıda) gönderen Claude Code oturumunun kimliği.
struct ClaudeLimitsMessage: Equatable, Sendable {
    var limits: ProviderLimits
    /// Doğrulanmış `session_id` (yalnızca `[A-Za-z0-9-]`, en çok 64 karakter). Eski sarmalayıcı gövdesinde ya da geçersizse nil.
    var sessionID: String?
}

/// statusLine sarmalayıcısının gönderdiği gövde. İki biçim kabul edilir:
/// - yeni: `{"session_id":"…","rate_limits":{…}}`
/// - eski (oturumsuz): Claude Code'un `rate_limits` nesnesinin ham JSON metni.
/// Yalnızca `five_hour`/`seven_day` altındaki `used_percentage` ve `resets_at` çözülür (dört sayı) ve oturum kimliği; başka alan
/// çözülmez ve saklanmaz.
enum ClaudeLimitsPayload {
    /// Sarmalayıcı `rate_limits` metnini 4096 karakterle sınırlar; zarf (session_id + anahtarlar) için küçük pay.
    static let maxBytes = 4 * 1024 + 256
    static let maxSessionIDLength = 64

    private struct Body: Decodable {
        let session_id: String?
        let rate_limits: RateLimits?
        let five_hour: Window?
        let seven_day: Window?

        private enum CodingKeys: String, CodingKey { case session_id, rate_limits, five_hour, seven_day }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            session_id = try? c.decodeIfPresent(String.self, forKey: .session_id)
            rate_limits = try c.decodeIfPresent(RateLimits.self, forKey: .rate_limits)
            five_hour = try c.decodeIfPresent(Window.self, forKey: .five_hour)
            seven_day = try c.decodeIfPresent(Window.self, forKey: .seven_day)
        }
    }

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

    static func parse(_ data: Data, now: Date) -> ProviderLimits? { parseMessage(data, now: now)?.limits }

    static func parseMessage(_ data: Data, now: Date) -> ClaudeLimitsMessage? {
        guard data.count <= maxBytes, let decoded = try? JSONDecoder().decode(Body.self, from: data) else { return nil }
        // Zarf varsa pencereler yalnızca `rate_limits` içinden okunur; yoksa eski biçim (gövdenin kendisi `rate_limits`).
        let fiveRaw = decoded.rate_limits.map(\.five_hour) ?? decoded.five_hour
        let weekRaw = decoded.rate_limits.map(\.seven_day) ?? decoded.seven_day
        let five = window(used: fiveRaw?.used, resets: fiveRaw?.resets)
        let week = window(used: weekRaw?.used, resets: weekRaw?.resets)
        guard five != nil || week != nil else { return nil }
        let session = decoded.rate_limits == nil ? nil : decoded.session_id.flatMap(validSessionID)
        return ClaudeLimitsMessage(limits: ProviderLimits(source: .claude, fiveHour: five, weekly: week, observedAt: now), sessionID: session)
    }

    /// Yalnızca ASCII harf/rakam ve `-`, 1…64 karakter; aksi halde nil (mesaj oturumsuz sayılır).
    static func validSessionID(_ text: String) -> String? {
        guard !text.isEmpty, text.utf8.count <= maxSessionIDLength,
              text.utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x2D })
        else { return nil }
        return text
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

/// Pencere başına birleştirme kuralları. Claude'da yalnızca oturum kimliği OLMAYAN (eski sarmalayıcı) mesajlar için kullanılır
/// (bkz. `ClaudeSessionLimits`); Codex'te pasif (rollout) kaynak için.
/// Monoton kural: aynı yenilenme anı (±60 sn) için kullanılan yüzde yalnızca ARTABİLİR (`allowDecrease` hariç); daha yeni (ileri)
/// yenilenme anı yeni pencere sayılır ve değer kabul edilir; daha eski yenilenme anı yok sayılır. 5 saatlik ve haftalık ayrı değerlendirilir.
/// Not: "yalnızca artar" kuralı tek başına yanlıştır: kullanıcı limit sıfırlama hakkı kullanınca yüzde, yenilenme anı aynı kalarak düşer
/// (gözlendi: haftalık %79 → %27, `resets_at` birebir aynı). Bu yüzden düşüşü ayırt edebilen bir sinyal varsa (`allowDecrease`) kabul edilir.
enum LimitMerge {
    static let resetTolerance: TimeInterval = 60

    /// Gelen değerin mevcutla birleşmiş hali. Hiçbir pencere kabul edilmediyse (hepsi daha düşük/eski) nil: mevcut değer ve `observedAt` değişmez.
    /// `allowDecrease`: gelen değer kesin olarak daha yeni bir gözlemse aynı penceredeki düşüş de kabul edilir (limit sıfırlama).
    static func monotonic(current: ProviderLimits, incoming: ProviderLimits, allowDecrease: Bool = false) -> ProviderLimits? {
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
                } else if new.usedPercent >= old.usedPercent || allowDecrease {
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
        if result.resetCreditCount == nil { result.resetCreditCount = current.resetCreditCount; result.resetCredits = current.resetCredits }
        return result
    }

    /// Codex kaynak önceliği. app-server (canlı) yetkili kaynaktır: değeri HER ZAMAN kabul edilir (rollout'taki eski %100'ü, hatta aynı
    /// yenilenme anında bile, geçer). Rollout/pasif kaynak: canlı değerden eski ya da aynı anlıksa yok sayılır; aksi halde `monotonic`.
    /// Rollout değerinin `observedAt`'i olayın kendi zaman damgasıdır (okuma anı değil): kesin olarak daha yeni bir olay aynı pencerede
    /// daha düşük yüzde bildiriyorsa bu bir limit sıfırlamasıdır ve kabul edilir; aynı/eski olay düşüremez.
    /// Nil dönerse mevcut değer değişmez.
    static func codexUpdate(current: ProviderLimits?, incoming: ProviderLimits) -> ProviderLimits? {
        if incoming.isLive == true { return incoming }
        guard let current else { return incoming }
        if current.isLive == true, incoming.observedAt <= current.observedAt { return nil }
        return monotonic(current: current, incoming: incoming, allowDecrease: incoming.observedAt > current.observedAt)
    }

    static func set(_ limits: inout ProviderLimits, _ kind: LimitWindowKind, _ window: LimitWindow) {
        switch kind {
        case .fiveHour: limits.fiveHour = window
        case .weekly: limits.weekly = window
        }
    }
}

/// Claude: oturum başına son değer ve gösterilecek değerin seçimi (saf, testli; yalnızca bellekte).
///
/// Her Claude Code oturumu statusLine'da kendi SON gördüğü `rate_limits`'i taşır. Bir oturumun değeri yalnızca o oturum API çağrısı
/// yapınca değişir; bu yüzden değeri EN SON DEĞİŞEN oturum en tazedir. Boşta oturum eski değeri tekrar tekrar yollasa da değeri
/// değişmediği için kazanamaz (7↔11 zıplaması olmaz); limit sıfırlamasında (yüzde düşer, yenilenme anı aynı) aktif oturumun düşen
/// değeri bir değişiklik olduğu için kazanır.
///
/// Pencere başına seçim: (1) en ileri yenilenme anı (±60 sn) grubu: yeni pencere her zaman kazanır; (2) grup içinde değeri en son
/// değişen oturum; eşitlikte yüksek yüzde, sonra en son duyulan. Oturumsuz (eski sarmalayıcı) mesajlar ve kalıcı son değer en düşük
/// önceliktir (`legacy`): o pencere için herhangi bir oturum değeri varsa kullanılmaz; kendi aralarında `LimitMerge.monotonic`.
///
/// Bir oturumun İLK mesajı (ör. Adalmon yeniden açılınca her oturum değerini yeniden yollar) gösterilen değerden düşükse değişiklik
/// sayılmaz (`changedAt` = distantPast): yeniden başlatmada boşta oturumun eski değeri aktif oturumu geri saramaz. Düşük değilse
/// değişiklik sayılır (yeni açılan oturumun ilk değeri tazedir).
struct ClaudeSessionLimits: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var limits: ProviderLimits
        /// Bu oturumun değerinin son DEĞİŞTİĞİ an (ilk mesajı düşükse distantPast).
        var changedAt: Date
        /// Bu oturumdan son mesaj ya da (değer değişmeden) son hook etkinliği: gösterilen değerin tazeliği.
        var heardAt: Date
        /// Sarmalayıcıdan gelen son MESAJ. Unutma (24 sa) buna göredir: hook etkinliği oturumu tek başına canlı tutamaz
        /// (sarmalayıcı kaldırılır/bozulursa değer süresiz "taze" görünmesin). 5 saatlik pencere en geç ~5 sa'te bir yenilendiği için
        /// gerçekten aktif oturum bu süre içinde mutlaka yeni mesaj yollar.
        var messageAt: Date
    }

    static let pruneAfter: TimeInterval = 24 * 3600
    static let maxSessions = 16

    private(set) var sessions: [String: Entry] = [:]
    /// Oturumsuz mesajlar + uygulamanın kalıcı son değeri.
    private(set) var legacy: ProviderLimits?

    init(legacy: ProviderLimits? = nil) { self.legacy = legacy }

    /// Gelen mesajı kaydeder. Dönen değer: gösterilecek birleşik değer (hiç veri yoksa nil).
    @discardableResult
    mutating func ingest(_ limits: ProviderLimits, sessionID: String?, now: Date) -> ProviderLimits? {
        prune(now: now)
        guard let sessionID else {
            if let legacy {
                if let merged = LimitMerge.monotonic(current: legacy, incoming: limits) { self.legacy = merged }
            } else {
                legacy = limits
            }
            return display()
        }
        if var entry = sessions[sessionID] {
            if entry.limits.fiveHour != limits.fiveHour || entry.limits.weekly != limits.weekly { entry.changedAt = now }
            entry.limits = limits
            entry.heardAt = now
            entry.messageAt = now
            sessions[sessionID] = entry
        } else {
            let shown = display(sessions: sessions)
            let lower = shown.map { Self.isLower(limits, than: $0) } ?? false
            sessions[sessionID] = Entry(limits: limits, changedAt: lower ? .distantPast : now, heardAt: now, messageAt: now)
        }
        if sessions.count > Self.maxSessions,
           let oldest = sessions.min(by: { $0.value.messageAt < $1.value.messageAt })?.key, oldest != sessionID {
            sessions[oldest] = nil
        }
        return display()
    }

    /// Hook etkinliği: oturum canlı ve API çağrısı yapıyor; değeri değişseydi sarmalayıcı yollardı, yani bildiği değer hâlâ güncel.
    /// Yalnızca sarmalayıcıdan zaten duyulmuş oturumlar için; gösterilen değerin tazeliğini (`observedAt`) ilerletir. Bilinmeyen oturumda nil.
    mutating func noteActivity(sessionID: String, now: Date) -> ProviderLimits? {
        prune(now: now)
        guard var entry = sessions[sessionID], now > entry.heardAt else { return nil }
        entry.heardAt = now
        sessions[sessionID] = entry
        return display()
    }

    func display() -> ProviderLimits? { display(sessions: sessions) ?? legacy }

    /// Pencere başına oturumlardan seçilen değer; o pencerede oturum değeri yoksa `legacy` penceresi. Oturum değeri hiç yoksa nil.
    private func display(sessions: [String: Entry]) -> ProviderLimits? {
        guard !sessions.isEmpty else { return nil }
        var result = ProviderLimits(source: .claude, observedAt: .distantPast)
        var observed: Date?
        for kind in LimitWindowKind.allCases {
            let candidates = sessions.values.compactMap { entry in entry.limits.window(kind).map { (entry, $0) } }
            guard !candidates.isEmpty else {
                if let window = legacy?.window(kind) { LimitMerge.set(&result, kind, window) }
                continue
            }
            let latestReset = candidates.compactMap(\.1.resetsAt).max()
            let group = candidates.filter { _, window in
                guard let latestReset else { return true }
                guard let reset = window.resetsAt else { return false }
                return latestReset.timeIntervalSince(reset) <= LimitMerge.resetTolerance
            }
            let winner = group.max { a, b in
                if a.0.changedAt != b.0.changedAt { return a.0.changedAt < b.0.changedAt }
                if a.1.usedPercent != b.1.usedPercent { return a.1.usedPercent < b.1.usedPercent }
                return a.0.heardAt < b.0.heardAt
            }
            guard let winner else { continue }
            LimitMerge.set(&result, kind, winner.1)
            observed = max(observed ?? winner.0.heardAt, winner.0.heardAt)
        }
        guard result.fiveHour != nil || result.weekly != nil else { return nil }
        result.observedAt = observed ?? legacy?.observedAt ?? .distantPast
        return result
    }

    /// Aynı pencerede (yenilenme anı ±60 sn ya da ikisi de bilinmiyor) gösterilenden düşük ya da daha eski pencereye ait mi?
    private static func isLower(_ incoming: ProviderLimits, than shown: ProviderLimits) -> Bool {
        LimitWindowKind.allCases.contains { kind in
            guard let new = incoming.window(kind), let old = shown.window(kind) else { return false }
            switch (old.resetsAt, new.resetsAt) {
            case let (oldReset?, newReset?):
                if oldReset.timeIntervalSince(newReset) > LimitMerge.resetTolerance { return true }
                if newReset.timeIntervalSince(oldReset) > LimitMerge.resetTolerance { return false }
                return new.usedPercent < old.usedPercent
            case (nil, nil): return new.usedPercent < old.usedPercent
            default: return false
            }
        }
    }

    /// 24 saattir duyulmayan oturumlar unutulur. Hepsi unutulursa son gösterilen değer `legacy` olur (eski bir değere geri dönülmez).
    private mutating func prune(now: Date) {
        let kept = sessions.filter { now.timeIntervalSince($0.value.messageAt) < Self.pruneAfter }
        guard kept.count != sessions.count else { return }
        if kept.isEmpty, let shown = display(sessions: sessions) { legacy = shown }
        sessions = kept
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
