import CoreGraphics
import Foundation
import ImageIO

/// Ofis v3 kodla çizilen piksel-art ve ışık dokuları: iMac / MacBook (kapalı + 3 ekran karesi), rol aksesuarları, masa lambası, fincan, kitap,
/// "zzz", paspas, koli ve önceden pişirilmiş radyal ışık sprite'ları. Tek doğruluk kaynağı burasıdır: SpriteKit dokuları ve tarayıcıya
/// giden `/v1/layout` data URI'leri aynı tanımdan üretilir (web'de yeniden çizim yok).
enum OfficeArt {
    struct Def: Sendable {
        var rows: [String]
        var palette: [Character: UInt32]
    }

    /// Işık sprite'ı meta bilgisi (tarayıcı da aynısını kullanır).
    struct Glow: Sendable {
        var name: String
        var width: Int
        var height: Int
        var r: Int
        var g: Int
        var b: Int
        var alpha: Double
    }

    static let glows: [Glow] = [
        Glow(name: "glow_bulb", width: 64, height: 64, r: 255, g: 208, b: 110, alpha: 0.55),
        Glow(name: "glow_pool", width: 40, height: 24, r: 255, g: 214, b: 120, alpha: 0.75),
        Glow(name: "glow_screen", width: 24, height: 16, r: 150, g: 200, b: 255, alpha: 0.7),
        Glow(name: "glow_trail", width: 16, height: 16, r: 200, g: 245, b: 255, alpha: 0.5),
    ]

    // MARK: Bilgisayarlar

    private static let imacTints: [OfficeComputer.Color: (chin: UInt32, neck: UInt32)] = [
        .blue: (0x6F9BEF, 0x5F86D6), .green: (0x8FD18F, 0x7CBB7C), .pink: (0xF2A7BC, 0xDB90A6), .silver: (0xD5D9DF, 0xB9BEC6),
    ]
    private static let macbookBodies: [OfficeComputer.Color: (body: UInt32, key: UInt32)] = [.silver: (0xD2D6DC, 0xA9AFB8), .gray: (0x7C828C, 0x5E646E)]

    private static func canvas(_ w: Int, _ h: Int) -> [[Character]] { [[Character]](repeating: [Character](repeating: ".", count: w), count: h) }

    private static func put(_ c: inout [[Character]], _ row: Int, _ col: Int, _ s: String) {
        for (i, ch) in s.enumerated() where col + i >= 0 && col + i < c[row].count { c[row][col + i] = ch }
    }

    /// Ekran satırları (kare 0…2): yeşil/mavi "kod" çizgileri. Her öğe: (satır sapması, sütun sapması, uzunluk, renk).
    private static let screenLines: [[(Int, Int, Int, Character)]] = [
        [(1, 1, 6, "g"), (3, 1, 8, "h"), (5, 1, 4, "g")],
        [(1, 1, 8, "g"), (2, 1, 5, "h"), (4, 1, 7, "g"), (6, 1, 3, "h")],
        [(1, 1, 4, "g"), (2, 1, 8, "g"), (3, 1, 6, "h"), (5, 1, 8, "g"), (6, 1, 5, "h")],
    ]

    private static func imacRows(frame: Int?) -> [String] {
        var c = canvas(16, 32)
        put(&c, 0, 0, "..kkkkkkkkkkkk..")
        put(&c, 1, 0, ".kwwwwwwwwwwwwk.")
        for r in 2...9 { put(&c, r, 0, ".kw" + String(repeating: "s", count: 10) + "wk.") }
        put(&c, 10, 0, ".kwwwwwwwwwwwwk.")
        put(&c, 11, 0, ".kcccccccccccck.")
        put(&c, 12, 0, ".kcccccccccccck.")
        put(&c, 13, 0, "..kkkkkkkkkkkk..")
        put(&c, 14, 0, ".......nnnn.....")
        put(&c, 15, 0, ".......nnnn.....")
        put(&c, 16, 0, "....kbbbbbbbbk..")
        put(&c, 18, 0, "kkkkkkkkkkk..kk.")
        put(&c, 19, 0, "kwtwtwtwtwk.kwwk")
        put(&c, 20, 0, "ktwtwtwtwtk.kwwk")
        put(&c, 21, 0, "kwwwwwwwwwk..kk.")
        put(&c, 22, 0, "kkkkkkkkkkk.....")
        if let frame {
            for (dr, dc, len, ch) in screenLines[frame % 3] { put(&c, 2 + dr, 3 + dc, String(repeating: ch, count: len)) }
        } else {
            put(&c, 3, 4, "qq")   // ekran yansıması
            put(&c, 4, 3, "q")
        }
        return c.map { String($0) }
    }

    private static func macbookRows(frame: Int?) -> [String] {
        var c = canvas(16, 32)
        put(&c, 2, 0, "..kkkkkkkkkkkk..")
        put(&c, 3, 0, "..kzzzzzzzzzzk..")
        for r in 4...10 { put(&c, r, 0, "..kz" + String(repeating: "s", count: 8) + "zk..") }
        put(&c, 11, 0, "..kzzzzzzzzzzk..")
        put(&c, 12, 0, "..kkkkkkkkkkkk..")
        put(&c, 13, 0, ".kbbbbbbbbbbbbk.")
        put(&c, 14, 0, "kbbbbbbbbbbbbbbk")
        put(&c, 15, 0, "kbtbtbtbtbtbtbbk")
        put(&c, 16, 0, "kbbbbbbppbbbbbbk")
        put(&c, 17, 0, ".kkkkkkkkkkkkkk.")
        if let frame {
            for (dr, dc, len, ch) in screenLines[frame % 3] { put(&c, 4 + dr, 4 + dc, String(repeating: ch, count: min(len, 7))) }
        } else {
            put(&c, 5, 5, "qq")
        }
        return c.map { String($0) }
    }

    static func computerDef(_ computer: OfficeComputer, frame: Int?) -> Def {
        var p: [Character: UInt32] = ["k": 0x4A4F57, "g": 0x60C677, "h": 0x6CA8FF, "t": 0xBFC4CC, "q": 0x2B3A4D]
        if computer.kind == .imac {
            let t = imacTints[computer.color] ?? imacTints[.silver]!
            p["w"] = 0xF2F3F6; p["c"] = t.chin; p["n"] = t.neck; p["b"] = t.neck
            p["s"] = frame == nil ? 0x15202B : 0x1B2C3D
            return Def(rows: imacRows(frame: frame), palette: p)
        }
        let t = macbookBodies[computer.color] ?? macbookBodies[.silver]!
        p["z"] = 0x16181D; p["b"] = t.body; p["t"] = t.key; p["p"] = t.key
        p["s"] = frame == nil ? 0x15202B : 0x1B2C3D
        return Def(rows: macbookRows(frame: frame), palette: p)
    }

    static func computerName(_ computer: OfficeComputer, frame: Int?) -> String {
        frame.map { "\(computer.artName)_on\($0 + 1)" } ?? "\(computer.artName)_off"
    }

    /// Tüm bilgisayar varyantları (4 iMac rengi + 2 MacBook rengi) × (kapalı + 3 kare).
    static let allComputers: [OfficeComputer] =
        OfficeComputer.imacColors.map { OfficeComputer(kind: .imac, color: $0) } + OfficeComputer.macbookColors.map { OfficeComputer(kind: .macbook, color: $0) }

    // MARK: Küçük sprite'lar

    static let small: [String: Def] = [
        "role_binoculars": Def(rows: [".kk.kk.", "kddkddk", "kddkddk", ".kk.kk."], palette: ["k": 0x222222, "d": 0x4A4A55]),
        "role_book": Def(rows: ["kkkkkk", "kbbbbk", "kbwwbk", "kbbbbk", "kbwwbk", "kkkkkk"], palette: ["k": 0x3B2412, "b": 0xB5651D, "w": 0xF2E6C9]),
        "role_hood": Def(rows: ["hhh....hhh", "hdhh..hhdh", ".hdhhhhdh.", "..hhhhhh.."], palette: ["h": 0xE8ECF5, "d": 0x9AA3B8]),
        "role_headphones": Def(rows: ["..kkkkkkkk..", ".k........k.", "kk........kk", "kdk......kdk", "kdk......kdk", ".k........k."], palette: ["k": 0x222222, "d": 0xB04CE8]),
        "role_glasses": Def(rows: ["kkkkkkkk", "kwwkkwwk", ".kk..kk."], palette: ["k": 0x222222, "w": 0xCDE8FF]),
        "role_magnifier": Def(rows: [".kkk..", "klllk.", "klllk.", ".kkk..", "...kk.", "....kk"], palette: ["k": 0x333333, "l": 0xBFE6FF]),
        "role_vest": Def(rows: ["vv....vv", "vvv..vvv", "vwv..vwv", "vvv..vvv"], palette: ["v": 0xFF8A1E, "w": 0xF5F5C8]),
        "role_compass": Def(rows: [".kkkk.", "kwwrwk", "kwwrwk", "kwwbwk", "kwwbwk", ".kkkk."], palette: ["k": 0x2A3B3A, "w": 0xF4F4F0, "r": 0xE0262B, "b": 0x2F6FDE]),
        "role_clipboard": Def(rows: ["..kk..", "kkkkkk", "kwwwwk", "kwkkwk", "kwwwwk", "kwkkwk", "kwwwwk", "kkkkkk"], palette: ["k": 0x3A3A44, "w": 0xF4F4F0]),
        "role_tie": Def(rows: ["bbb", ".b.", ".b.", "bbb", ".b."], palette: ["b": 0x555A66]),
        "role_ruler": Def(rows: ["yyy", "yky", "yyy", "yky", "yyy", "yky", "yyy", "yky", "yyy"], palette: ["y": 0xE8C55A, "k": 0x7A5A10]),
        "role_tag": Def(rows: ["kkkk", "kwwk", "kwwk", "kkkk"], palette: ["k": 0x44484F, "w": 0xDDE1E8]),
        "cup": Def(rows: ["wwwww.", "wcccwk", "wwwwwk", ".www.."], palette: ["w": 0xF4F4F4, "c": 0x6B3E1E, "k": 0x8A8A8A]),
        "zzz": Def(rows: ["zzzz....", "..z.....", ".z......", "zzzz.zzz", "....z...", "...z....", "...zzz.."], palette: ["z": 0x3A5BA8]),
        "mop": Def(rows: ["..h...", "..h...", "..h...", "..h...", "..h...", "..h...", "..h...", "..h...", "..h...", "..h...", "..h...", "..h...", "mmmmmm", "mwmwmw", "mwmwmw", ".w.w.w"],
                   palette: ["h": 0x8A6A3A, "m": 0xC9D6E8, "w": 0xFFFFFF]),
        "box": Def(rows: ["kkkkkkkkkk", "kbbbbbbbbk", "kbbbttbbbk", "kbbbbbbbbk", "kbbbbbbbbk", "kkkkkkkkkk"], palette: ["k": 0x6B4A1E, "b": 0xC8964B, "t": 0xE6C98A]),
        "lamp": Def(rows: ["..kk..", ".kyyk.", "..ky..", "..k...", "..k...", ".kkk.."], palette: ["k": 0x3A3F4A, "y": 0xFFE08A]),
        "bulb": Def(rows: ["..k..", "..k..", ".yyy.", "yyyyy", ".yyy."], palette: ["k": 0x3A3F4A, "y": 0xFFE9A8]),
    ]

    /// Tüm adlandırılmış piksel-art tanımları (bilgisayarlar dahil).
    static let defs: [String: Def] = {
        var out = small
        for pc in allComputers {
            out[computerName(pc, frame: nil)] = computerDef(pc, frame: nil)
            for f in 0..<3 { out[computerName(pc, frame: f)] = computerDef(pc, frame: f) }
        }
        return out
    }()

    static func roleAccessoryName(_ a: OfficeRoleAccessory) -> String? { a == .none ? nil : "role_\(a.rawValue)" }

    // MARK: Görüntüler

    static func image(_ name: String) -> CGImage? {
        guard let d = defs[name] else { return glowImage(name) }
        return OfficePixelArt.image(d.rows, palette: d.palette)
    }

    /// Radyal yumuşak ışık (premultiplied alfa): merkez `alpha`, kenar 0; eliptik (genişlik × yükseklik).
    static func glowImage(_ name: String) -> CGImage? {
        guard let g = glows.first(where: { $0.name == name }) else { return nil }
        var px = OfficePixels(width: g.width, height: g.height)
        for y in 0..<g.height { for x in 0..<g.width {
            let dx = (Double(x) + 0.5) / Double(g.width) * 2 - 1, dy = (Double(y) + 0.5) / Double(g.height) * 2 - 1
            let d = min(1, (dx * dx + dy * dy).squareRoot())
            let a = g.alpha * pow(1 - d, 1.6)
            let i = (y * g.width + x) * 4
            px.data[i] = UInt8(Double(g.r) * a); px.data[i + 1] = UInt8(Double(g.g) * a); px.data[i + 2] = UInt8(Double(g.b) * a); px.data[i + 3] = UInt8(255 * a)
        } }
        return px.cgImage()
    }

    static func pngData(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// `/v1/layout` için: "data:image/png;base64,…".
    static func dataURI(_ name: String) -> String? {
        guard let img = image(name), let data = pngData(img) else { return nil }
        return "data:image/png;base64," + data.base64EncodedString()
    }
}
