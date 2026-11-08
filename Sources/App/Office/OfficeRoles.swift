import Foundation

// Ofis v3: crew rolleri. Alt ajanın `agentType` değeri → kıyafet tonu, 1 aksesuar, boy, etiket rengi. Saf (SpriteKit'siz) ve testli.
// Ana ajan (yönetici) bu rollerden bağımsızdır: model aksesuarını (Opus taç, Sonnet şapka, Haiku filiz, Fable yıldız) korur.

/// Rol aksesuarı (kodla çizilen küçük piksel-art, bkz. `OfficeArt`). `hood` kapüşonlu üst: ton + kapüşon yaka dokusu.
enum OfficeRoleAccessory: String, CaseIterable, Sendable {
    case none, binoculars, book, hood, headphones, glasses, magnifier, vest, compass, clipboard, tie, ruler, tag

    /// Karakter üzerinde nereye konur: baş üstü/kulak, yüz, gövde (yaka/yelek/kravat), el.
    enum Place: String, Sendable { case head, face, chest, hand }

    var place: Place {
        switch self {
        case .headphones: .head
        case .glasses: .face
        case .hood, .vest, .tie, .tag: .chest
        case .none, .binoculars, .book, .magnifier, .compass, .clipboard, .ruler: .hand
        }
    }
}

struct OfficeRoleStyle: Equatable, Sendable {
    /// Eşleme anahtarı (küçük harf, önek ayıklanmış ya da tam anahtar); bilinmeyen tipte küçük harfli ad.
    var key: String
    /// Etikette gösterilen ad: `agentType` aynen (kısaltmasız).
    var name: String
    var tintHex: String
    var tint: OfficeRGB
    var accessory: OfficeRoleAccessory
    var small: Bool
    /// Kapüşonlu (implementer, implementer-hard): ton gövdeye iki kat vurgulu uygulanır.
    var hoodie: Bool
    var known: Bool

    /// Etiket metni rengi: tonun açılmış hali (koyu levha üstünde okunur).
    var labelColor: OfficeRGB {
        OfficeRGB(r: min(1, tint.r * 0.55 + 0.45), g: min(1, tint.g * 0.55 + 0.45), b: min(1, tint.b * 0.55 + 0.45))
    }

    /// Gövde renk karışımı (SKSpriteNode.colorBlendFactor): kapüşonlular daha doygun.
    var tintBlend: Double { hoodie ? 0.72 : 0.62 }
}

enum OfficeRoles {
    private struct Entry { var hex: String; var accessory: OfficeRoleAccessory; var small = false; var hoodie = false }

    /// Bilinen roller (anahtarlar küçük harf). Eşleme sırası: tam anahtar, sonra son ":" sonrası.
    private static let table: [String: Entry] = [
        "scanner": Entry(hex: "#3FBF5F", accessory: .binoculars, small: true),
        "deep-reader": Entry(hex: "#F2A93B", accessory: .book),
        "implementer": Entry(hex: "#3B7BFF", accessory: .hood, hoodie: true),
        "implementer-hard": Entry(hex: "#8E4FE0", accessory: .headphones, hoodie: true),
        "reviewer": Entry(hex: "#E04848", accessory: .glasses),
        "ui-tester": Entry(hex: "#F28A1E", accessory: .magnifier),
        "ui-smoke": Entry(hex: "#F7B267", accessory: .vest, small: true),
        "explore": Entry(hex: "#28C7C0", accessory: .compass),
        "plan": Entry(hex: "#1F3A8A", accessory: .clipboard),
        "general-purpose": Entry(hex: "#8A8F98", accessory: .tie),
        "feature-dev:code-architect": Entry(hex: "#8C2F45", accessory: .ruler),
        "feature-dev:code-explorer": Entry(hex: "#28C7C0", accessory: .compass),
        "feature-dev:code-reviewer": Entry(hex: "#E04848", accessory: .glasses),
        "claude-code-guide": Entry(hex: "#F07AB0", accessory: .book),
        "statusline-setup": Entry(hex: "#C9CED6", accessory: .none),
    ]

    static var knownKeys: [String] { table.keys.sorted() }

    /// Küçük harf; tam anahtar bilinmiyorsa "xxx:" öneklerini (plugin adı) ayıklanmış hali. Bilinmeyen tip için küçük harfli tam ad.
    static func key(forAgentType type: String) -> String {
        let lower = type.trimmingCharacters(in: .whitespaces).lowercased()
        if table[lower] != nil { return lower }
        if let i = lower.lastIndex(of: ":") {
            let stripped = String(lower[lower.index(after: i)...])
            if table[stripped] != nil { return stripped }
        }
        return lower
    }

    static func style(forAgentType type: String) -> OfficeRoleStyle {
        let name = type.trimmingCharacters(in: .whitespaces)
        let key = key(forAgentType: type)
        if let e = table[key] {
            return OfficeRoleStyle(key: key, name: name, tintHex: e.hex, tint: rgb(hex: e.hex), accessory: e.accessory, small: e.small, hoodie: e.hoodie, known: true)
        }
        // Bilinmeyen: ad hash'inden ton (doygunluk/parlaklık sabit).
        let hue = Double(OfficeStroll.seed(for: key) % 360) / 360
        let c = OfficeRGB.fromHSL(h: hue, s: 0.55, l: 0.55)
        return OfficeRoleStyle(key: key, name: name.isEmpty ? "?" : name, tintHex: hex(c), tint: c, accessory: .tag, small: false, hoodie: false, known: false)
    }

    static func rgb(hex: String) -> OfficeRGB {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(s, radix: 16) ?? 0x888888
        return OfficeRGB(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }

    static func hex(_ c: OfficeRGB) -> String {
        func b(_ x: Double) -> Int { Int((min(1, max(0, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", b(c.r), b(c.g), b(c.b))
    }
}
