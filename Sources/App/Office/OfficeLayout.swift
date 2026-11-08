import Foundation

// Ajan ofisi: saf (SpriteKit'siz) veri katmanı. Koordinat sistemi pixel-agents ile aynı: (col, row) = 16 px'lik karo,
// başlangıç sol-üst, y aşağı. Görseller `Resources/Office/` altındadır (bkz. ATTRIBUTION.md).

/// Karo başına Photoshop tarzı "colorize" ayarı (default-layout-1.json `tileColors`). Formül kaynak depodan DOĞRULANMADI:
/// gri → HSL(h, s) ve açıklık = kontrast + parlaklık düzeltmesi.
struct OfficeTileColor: Codable, Equatable, Sendable {
    var h: Double
    var s: Double
    var b: Double
    var c: Double

    /// Gri değer (0…1) → renklendirilmiş RGB (0…1).
    func colorize(gray: Double) -> OfficeRGB {
        var l = gray
        if c != 0 { l = 0.5 + (l - 0.5) * ((100 + c) / 100) }
        if b != 0 { l += b / 200 }
        l = min(1, max(0, l))
        return OfficeRGB.fromHSL(h: h / 360, s: min(1, max(0, s / 100)), l: l)
    }
}

struct OfficeRGB: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    static func fromHSL(h: Double, s: Double, l: Double) -> OfficeRGB {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = (h - h.rounded(.down)) * 6
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double) = switch Int(hp) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        let m = l - c / 2
        return OfficeRGB(r: r1 + m, g: g1 + m, b: b1 + m)
    }
}

struct OfficeFurniturePlacement: Codable, Equatable, Sendable {
    var type: String
    var col: Int
    var row: Int

    /// "SOFA_SIDE:left" → "SOFA_SIDE".
    var assetID: String { String(type.split(separator: ":", maxSplits: 1).first ?? "") }
    /// ":left" eki: yatay yansıtılmış yerleşim (yan görünümlü varlıklar varsayılan olarak sağa bakar).
    var mirrored: Bool { type.hasSuffix(":left") }
}

enum OfficeTileKind: Equatable, Sendable {
    case void
    case wall
    case floor(Int)
}

/// default-layout-1.json: `tiles` satır-satır (cols × rows); 255 = boşluk, 0 = duvar, 1… = zemin (zemin görseli `floor_{v-1}.png`, DOĞRULANMADI).
struct OfficeLayout: Codable, Equatable, Sendable {
    var version: Int
    var cols: Int
    var rows: Int
    var tiles: [Int]
    var tileColors: [OfficeTileColor?]
    var furniture: [OfficeFurniturePlacement]
    /// Yönetici bölgesi (oda şablonları verir; JSON'da yok).
    var executiveZone: OfficeRect?

    enum LayoutError: Error, Equatable { case badTileCount(expected: Int, got: Int) }

    private enum CodingKeys: String, CodingKey { case version, cols, rows, tiles, tileColors, furniture }

    init(version: Int = 1, cols: Int, rows: Int, tiles: [Int], tileColors: [OfficeTileColor?] = [], furniture: [OfficeFurniturePlacement] = [],
         executiveZone: OfficeRect? = nil) {
        self.version = version; self.cols = cols; self.rows = rows
        self.tiles = tiles; self.tileColors = tileColors; self.furniture = furniture; self.executiveZone = executiveZone
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        cols = try c.decode(Int.self, forKey: .cols)
        rows = try c.decode(Int.self, forKey: .rows)
        tiles = try c.decode([Int].self, forKey: .tiles)
        tileColors = try c.decodeIfPresent([OfficeTileColor?].self, forKey: .tileColors) ?? []
        furniture = try c.decodeIfPresent([OfficeFurniturePlacement].self, forKey: .furniture) ?? []
        executiveZone = nil
    }

    static func parse(_ data: Data) throws -> OfficeLayout {
        let layout = try JSONDecoder().decode(OfficeLayout.self, from: data)
        guard layout.cols > 0, layout.rows > 0, layout.tiles.count == layout.cols * layout.rows else {
            throw LayoutError.badTileCount(expected: layout.cols * layout.rows, got: layout.tiles.count)
        }
        return layout
    }

    func kind(_ col: Int, _ row: Int) -> OfficeTileKind {
        guard col >= 0, col < cols, row >= 0, row < rows else { return .void }
        switch tiles[row * cols + col] {
        case 0: return .wall
        case 255: return .void
        case let v: return .floor(v)
        }
    }

    func color(_ col: Int, _ row: Int) -> OfficeTileColor? {
        let i = row * cols + col
        return i >= 0 && i < tileColors.count ? tileColors[i] : nil
    }

    /// Duvar otomatik karosu: K=1, D=2, G=4, B=8 maskesi (komşu duvarsa bit açık). Sprite sayfası 4×4 (16×32); sütun = mask % 4,
    /// satır = mask / 4 (DOĞRULANMADI; görsel olarak kontrol edildi).
    func wallMask(_ col: Int, _ row: Int) -> Int {
        var mask = 0
        if kind(col, row - 1) == .wall { mask |= 1 }
        if kind(col + 1, row) == .wall { mask |= 2 }
        if kind(col, row + 1) == .wall { mask |= 4 }
        if kind(col - 1, row) == .wall { mask |= 8 }
        return mask
    }

    /// Boş olmayan karoların kapladığı alan (duvar sprite'ı bir üst satıra taştığı için üst sınır 1 yukarı). Kapsayıcı.
    var visibleBounds: (minCol: Int, minRow: Int, maxCol: Int, maxRow: Int) {
        var minC = Int.max, minR = Int.max, maxC = Int.min, maxR = Int.min
        for r in 0..<rows { for c in 0..<cols where kind(c, r) != .void {
            minC = min(minC, c); maxC = max(maxC, c); maxR = max(maxR, r)
            minR = min(minR, kind(c, r) == .wall ? max(0, r - 1) : r)
        } }
        // Duvara asılı mobilya (tablo, saat) duvarın üst satırındadır.
        for f in furniture { minC = min(minC, f.col); minR = min(minR, f.row) }
        guard minC != Int.max else { return (0, 0, cols - 1, rows - 1) }
        return (max(0, minC), max(0, minR), min(cols - 1, maxC), min(rows - 1, maxR))
    }
}

/// Mobilya varlığı (manifest.json'daki tek bir `asset` üyesi; gruplardan kalıtım düzleştirilmiş).
struct OfficeAsset: Equatable, Sendable {
    var id: String
    /// Mobilya klasörüne göre göreli dosya ("DESK/DESK_FRONT.png").
    var file: String
    var width: Int
    var height: Int
    var footprintW: Int
    var footprintH: Int
    /// Ayak izinin üstten kaç satırı arka plan (üzerinden/arkasından geçilebilir, engel değil).
    var backgroundTiles: Int
    var category: String
    var orientation: String?
    var mirrorSide: Bool
    var onSurface: Bool
    var onWall: Bool
    var state: String?
    var frame: Int?
}

enum OfficeCatalog {
    /// Tek bir manifest.json'u düzleştirir. `group` düğümleri category/backgroundTiles/canPlace*/orientation/state'i üyelere kalıtır.
    static func parse(manifest data: Data, folder: String) throws -> [OfficeAsset] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var out: [OfficeAsset] = []
        walk(root, inherited: [:], folder: folder, into: &out)
        return out
    }

    private static let inheritedKeys = ["category", "backgroundTiles", "canPlaceOnWalls", "canPlaceOnSurfaces", "orientation", "state"]

    private static func walk(_ node: [String: Any], inherited: [String: Any], folder: String, into out: inout [OfficeAsset]) {
        var ctx = inherited
        for k in inheritedKeys { if let v = node[k] { ctx[k] = v } }
        if (node["type"] as? String) == "asset" {
            let flat = ctx.merging(node) { _, new in new }
            guard let id = flat["id"] as? String, let file = flat["file"] as? String ?? (node["id"] as? String).map({ "\($0).png" }) else { return }
            let w = flat["width"] as? Int ?? 16, h = flat["height"] as? Int ?? 16
            out.append(OfficeAsset(
                id: id, file: folder.isEmpty ? file : "\(folder)/\(file)", width: w, height: h,
                footprintW: flat["footprintW"] as? Int ?? max(1, w / 16), footprintH: flat["footprintH"] as? Int ?? max(1, h / 16),
                backgroundTiles: flat["backgroundTiles"] as? Int ?? 0, category: flat["category"] as? String ?? "",
                orientation: flat["orientation"] as? String, mirrorSide: flat["mirrorSide"] as? Bool ?? false,
                onSurface: flat["canPlaceOnSurfaces"] as? Bool ?? false, onWall: flat["canPlaceOnWalls"] as? Bool ?? false,
                state: flat["state"] as? String, frame: flat["frame"] as? Int))
        } else if let members = node["members"] as? [[String: Any]] {
            for m in members { walk(m, inherited: ctx, folder: folder, into: &out) }
        }
    }

    /// `furniture/<ADI>/manifest.json` dosyalarının tümü → varlık kimliğine göre sözlük.
    static func load(furnitureDirectory: URL) -> [String: OfficeAsset] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: furnitureDirectory.path) else { return [:] }
        var map: [String: OfficeAsset] = [:]
        for dir in dirs.sorted() {
            let manifest = furnitureDirectory.appending(path: dir).appending(path: "manifest.json")
            guard let data = try? Data(contentsOf: manifest), let assets = try? parse(manifest: data, folder: dir) else { continue }
            for a in assets { map[a.id] = a }
        }
        return map
    }
}

/// Karakter sayfası (char_N.png, 112×96): 7 kare × 3 satır, kare 16×32. Satırlar: 0 = aşağı (ön), 1 = yukarı (arka), 2 = sağ
/// (sola bakış sağın yansıması). Kareler: 0–2 yürüme (0,1,2,1 döngüsü; 1 = ayakta), 3–4 yazma, 5–6 okuma.
enum OfficeCharacterSheet {
    static let frameWidth = 16
    static let frameHeight = 32
    static let columns = 7
    static let rows = 3
    static let sheetWidth = frameWidth * columns   // 112
    static let sheetHeight = frameHeight * rows    // 96

    enum Direction: Int, CaseIterable, Sendable { case down = 0, up = 1, right = 2, left = 3 }

    enum Pose: Equatable, Sendable { case walk(Int), stand, typing(Int), reading(Int) }

    /// Yürüme döngüsü kare sırası.
    static let walkCycle = [0, 1, 2, 1]

    static func frameIndex(_ pose: Pose) -> Int {
        switch pose {
        case .walk(let i): walkCycle[((i % 4) + 4) % 4]
        case .stand: 1
        case .typing(let i): 3 + (((i % 2) + 2) % 2)
        case .reading(let i): 5 + (((i % 2) + 2) % 2)
        }
    }

    /// Sol-üst başlangıçlı piksel dikdörtgeni (sağ ve sol aynı satırı kullanır; sol = yatay yansıma).
    static func pixelRect(direction: Direction, frame: Int) -> CGRect {
        let row = direction == .left ? Direction.right.rawValue : direction.rawValue
        return CGRect(x: frame * frameWidth, y: row * frameHeight, width: frameWidth, height: frameHeight)
    }

    static func mirrorsHorizontally(_ d: Direction) -> Bool { d == .left }
}
