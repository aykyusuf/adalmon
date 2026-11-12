import Foundation

// Abonelik planı: hangi planın kullanıldığı (Limitler sayfası). Yalnızca plan adı okunur; hesap kimliği (e-posta, ad, uuid,
// kurum kimliği) hiçbir yerde okunmaz, saklanmaz ya da yazılmaz. Bu dosyadaki her şey saf mantık + tek dosya okuyucusudur.

/// Ekrana hazır plan bilgisi.
struct LimitPlan: Equatable, Sendable {
    var source: LimitSource
    /// Rozet metni: "Claude Max 20x", "ChatGPT Plus".
    var title: String
    /// Plan adı rozetin yanında ayrıca varsa ("Ultra"); rozetle aynıysa nil.
    var subtitle: String?
    /// "Stripe aboneliği" gibi faturalama kaynağı (yalnızca Claude, bilinen değerler).
    var billing: String?
    /// Claude: ek kullanım (extra usage) açık mı? Bilinmiyorsa nil.
    var extraUsage: Bool?
}

/// `~/.claude.json` içindeki `oauthAccount` nesnesinden okunan beş alan (başkası okunmaz).
struct ClaudeAccountPlan: Equatable, Sendable {
    var planDisplayName: String?
    var organizationType: String?
    var rateLimitTier: String?
    var billingType: String?
    var hasExtraUsageEnabled: Bool?

    var isEmpty: Bool {
        planDisplayName == nil && organizationType == nil && rateLimitTier == nil && billingType == nil && hasExtraUsageEnabled == nil
    }
}

enum LimitPlanMapper {
    /// Claude: organizationType + rate limit katmanı → "Claude Max 20x". Bilinmeyen tür için yalnızca `planDisplayName` kullanılır.
    static func claude(_ account: ClaudeAccountPlan) -> LimitPlan? {
        guard !account.isEmpty else { return nil }
        let display = clean(account.planDisplayName)
        let base: String? = switch account.organizationType {
        case "claude_max": "Max"
        case "claude_pro": "Pro"
        case "claude_team": "Team"
        case "claude_enterprise": "Enterprise"
        case "claude_free": "Free"
        default: nil
        }
        var title = "Claude"
        var subtitle = display
        if let base {
            title += " \(base)"
            if base == "Max", let multiplier = multiplier(account.rateLimitTier) { title += " \(multiplier)" }
            // Aynı ad iki kez görünmesin ("Max" / "Claude Max 20x").
            if let shown = display, title.lowercased().contains(shown.lowercased()) { subtitle = nil }
        } else if let display {
            title += " \(display)"
            subtitle = nil
        } else {
            return nil
        }
        return LimitPlan(source: .claude, title: title, subtitle: subtitle, billing: billing(account.billingType),
                         extraUsage: account.hasExtraUsageEnabled)
    }

    /// Codex: rollout olaylarındaki `plan_type` → "ChatGPT Plus". Bilinmeyen değer okunaklı hale getirilir; boş/uygunsuz → nil.
    static func codex(planType: String?) -> LimitPlan? {
        guard let raw = planType?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return nil }
        let known: [String: String] = ["free": "Free", "go": "Go", "plus": "Plus", "pro": "Pro", "team": "Team", "business": "Business",
                                       "enterprise": "Enterprise", "edu": "Edu"]
        if let name = known[raw] { return LimitPlan(source: .codex, title: "ChatGPT \(name)") }
        guard let name = humanized(raw) else { return nil }
        return LimitPlan(source: .codex, title: "ChatGPT \(name)")
    }

    /// `default_claude_max_20x` → "20x"; çarpan yoksa nil.
    static func multiplier(_ tier: String?) -> String? {
        guard let tier, let last = tier.split(separator: "_").last, last.hasSuffix("x"),
              let number = Int(last.dropLast()), (1...100).contains(number) else { return nil }
        return "\(number)x"
    }

    static func billing(_ type: String?) -> String? {
        switch type {
        case "stripe_subscription": "Stripe aboneliği"
        case "apple_subscription": "Apple aboneliği"
        case "google_play_subscription": "Google Play aboneliği"
        default: nil
        }
    }

    /// Kısa, yalnızca harf/rakam/boşluk içeren düz metin; aksi halde nil (ekrana beklenmedik içerik taşınmasın).
    private static func clean(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text.count <= 24,
              text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }) else { return nil }
        return text
    }

    /// `self_serve_business` → "Self serve business".
    private static func humanized(_ raw: String) -> String? {
        let words = raw.replacing("_", with: " ")
        guard let text = clean(words) else { return nil }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// `~/.claude.json` okuyucusu. Yol enjekte edilebilir (testler gerçek dosyayı okumaz). Yalnızca `oauthAccount` içindeki
/// beş alanı çözer; JSON'un geri kalanı (e-posta, ad, uuid vb.) hiçbir değişkene alınmaz.
struct ClaudePlanReader: Sendable {
    /// Bundan büyük dosya okunmaz (gerçekte ~400 KB).
    static let maxBytes = 8 * 1024 * 1024
    var url: URL

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude.json", directoryHint: .notDirectory)
    }

    init(url: URL = Self.defaultURL) { self.url = url }

    struct Stamp: Equatable, Sendable {
        var modified: Date
        var size: Int
    }

    /// Ucuz değişiklik denetimi (yalnızca stat). `URL.resourceValues` önbelleğe alır; bu yüzden FileManager kullanılır.
    func stamp() -> Stamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular, let modified = attributes[.modificationDate] as? Date else { return nil }
        return Stamp(modified: modified, size: (attributes[.size] as? NSNumber)?.intValue ?? 0)
    }

    private struct File: Decodable {
        let oauthAccount: Account?

        private enum CodingKeys: String, CodingKey { case oauthAccount }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            oauthAccount = try? c.decodeIfPresent(Account.self, forKey: .oauthAccount)
        }
    }

    private struct Account: Decodable {
        let plan: ClaudeAccountPlan

        private enum CodingKeys: String, CodingKey {
            case planDisplayName, organizationType, organizationRateLimitTier, billingType, hasExtraUsageEnabled
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            plan = ClaudeAccountPlan(
                planDisplayName: try? c.decodeIfPresent(String.self, forKey: .planDisplayName),
                organizationType: try? c.decodeIfPresent(String.self, forKey: .organizationType),
                rateLimitTier: try? c.decodeIfPresent(String.self, forKey: .organizationRateLimitTier),
                billingType: try? c.decodeIfPresent(String.self, forKey: .billingType),
                hasExtraUsageEnabled: try? c.decodeIfPresent(Bool.self, forKey: .hasExtraUsageEnabled))
        }
    }

    /// Dosya yoksa, okunamıyorsa, JSON bozuksa ya da `oauthAccount` yoksa nil.
    func read() -> ClaudeAccountPlan? {
        guard let stamp = stamp(), stamp.size <= Self.maxBytes, let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data), let plan = file.oauthAccount?.plan, !plan.isEmpty else { return nil }
        return plan
    }
}
