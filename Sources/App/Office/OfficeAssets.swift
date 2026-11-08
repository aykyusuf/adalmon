import CoreGraphics
import Foundation
import ImageIO
import SpriteKit

/// RGBA (premultiplied) piksel tamponu: zemin/duvar renklendirme ve birleştirme için.
struct OfficePixels {
    var width: Int
    var height: Int
    var data: [UInt8]

    init(width: Int, height: Int) {
        self.width = width; self.height = height
        data = [UInt8](repeating: 0, count: width * height * 4)
    }

    init?(cgImage: CGImage) {
        self.init(width: cgImage.width, height: cgImage.height)
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        if !ok { return nil }
    }

    func flippedHorizontally() -> OfficePixels {
        var out = OfficePixels(width: width, height: height)
        for y in 0..<height { for x in 0..<width {
            let si = (y * width + x) * 4, di = (y * width + (width - 1 - x)) * 4
            for k in 0..<4 { out.data[di + k] = data[si + k] }
        } }
        return out
    }

    func cgImage() -> CGImage? {
        var copy = data
        return copy.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    /// `src`'nin (sx, sy, w, h) bölgesini (sol-üst başlangıçlı) `dx, dy`'ye alfa ile birleştirir; renk verilirse gri değeri renklendirir.
    mutating func composite(_ src: OfficePixels, sx: Int, sy: Int, w: Int, h: Int, dx: Int, dy: Int, color: OfficeTileColor?) {
        for y in 0..<h { for x in 0..<w {
            let tx = dx + x, ty = dy + y
            guard tx >= 0, tx < width, ty >= 0, ty < height else { continue }
            let si = ((sy + y) * src.width + (sx + x)) * 4
            let a = Int(src.data[si + 3])
            if a == 0 { continue }
            var r = Double(src.data[si]), g = Double(src.data[si + 1]), b = Double(src.data[si + 2])
            if let color {
                let unp = a == 255 ? 1.0 : 255.0 / Double(a)
                let gray = (0.299 * r + 0.587 * g + 0.114 * b) * unp / 255
                let c = color.colorize(gray: gray)
                let pa = Double(a) / 255
                r = c.r * 255 * pa; g = c.g * 255 * pa; b = c.b * 255 * pa
            }
            let di = (ty * width + tx) * 4
            let inv = 1 - Double(a) / 255
            data[di] = UInt8(min(255, r + Double(data[di]) * inv))
            data[di + 1] = UInt8(min(255, g + Double(data[di + 1]) * inv))
            data[di + 2] = UInt8(min(255, b + Double(data[di + 2]) * inv))
            data[di + 3] = UInt8(min(255, Double(a) + Double(data[di + 3]) * inv))
        } }
    }
}

/// Kodla çizilen piksel-art (aksesuar, balon, kapı). Satırlar sol-üstten; '.' saydam; palet harf → 0xRRGGBB.
enum OfficePixelArt {
    static func image(_ rows: [String], palette: [Character: UInt32]) -> CGImage? {
        let h = rows.count, w = rows.map(\.count).max() ?? 0
        var px = OfficePixels(width: w, height: h)
        for (y, row) in rows.enumerated() { for (x, ch) in row.enumerated() {
            guard let rgb = palette[ch] else { continue }
            let i = (y * w + x) * 4
            px.data[i] = UInt8((rgb >> 16) & 0xFF); px.data[i + 1] = UInt8((rgb >> 8) & 0xFF); px.data[i + 2] = UInt8(rgb & 0xFF); px.data[i + 3] = 255
        } }
        return px.cgImage()
    }

    static let crown = image(["y...y...y", "yy.yyy.yy", "yyyyyyyyy", "yyyryyyyy", "ddddddddd"], palette: ["y": 0xFFD700, "d": 0xB8860B, "r": 0xE0262B])
    static let cap = image(["..bbbbbb..", ".bblbbbbb.", "bbbbbbbbbb", "dddddddddd"], palette: ["b": 0x2F6FDE, "l": 0x7FB0FF, "d": 0x1B4DA8])
    static let star = image(["...y...", "..yyy..", "yyyyyyy", ".yyyyy.", "..yyy..", ".yy.yy.", ".o...o."], palette: ["y": 0xFFC400, "o": 0xFF8A00])
    static let sprout = image([".gg.gg.", "ggg.ggg", ".ggdgg.", "...d...", "...d..."], palette: ["g": 0x4CD964, "d": 0x2E8B3D])
    static let alertBubble = image([
        "..kkkkkkk..", ".kwwwwwwwk.", "kwwwwowwwwk", "kwwwwowwwwk", "kwwwwowwwwk", "kwwwwowwwwk",
        "kwwwwwwwwwk", "kwwwwowwwwk", ".kwwwwwwwk.", "..kkkwkkk..", "....kwk....", ".....k....."],
        palette: ["k": 0x222222, "w": 0xFFFFFF, "o": 0xFF8A00])
    static let thinkBubble = image([
        "..kkkkkkk..", ".kwwwwwwwk.", "kwwwwwwwwwk", "kwwwwwwwwwk", "kwgwwgwwgwk", "kwwwwwwwwwk",
        ".kwwwwwwwk.", "..kkkwkkk..", "....kwk....", ".....k....."],
        palette: ["k": 0x222222, "w": 0xFFFFFF, "g": 0x555555])

    /// Konuşma balonu, verilen genişlikte (piksel; en az 14): koyu çerçeve, beyaz iç, yuvarlak köşe, sol altta kuyruk. Gövde `bodyHeight`
    /// satır, altında 2 satır kuyruk (toplam bodyHeight + 2). Stil mevcut "…" / "!" balonlarıyla aynı. Kuyruk ucu x ≈ 3.5, y = alt kenar.
    static func speechBubble(width w: Int, bodyHeight h: Int = 12) -> CGImage? {
        let w = max(14, w)
        func solid(_ left: Character, _ fill: Character, _ right: Character) -> String { String(left) + String(repeating: fill, count: w - 2) + String(right) }
        var rows: [String] = []
        let cap = "." + "." + String(repeating: "k", count: w - 4) + ".."
        rows.append(cap)
        rows.append(".k" + String(repeating: "w", count: w - 4) + "k.")
        for _ in 2..<(h - 2) { rows.append(solid("k", "w", "k")) }
        rows.append(rows[1])
        var bottom = Array(cap)
        bottom[3] = "w"; bottom[4] = "w"
        rows.append(String(bottom))
        rows.append(".." + "kwk" + String(repeating: ".", count: w - 5))
        rows.append("..." + "k" + String(repeating: ".", count: w - 4))
        return image(rows, palette: ["k": 0x222222, "w": 0xFFFFFF])
    }
    static let speechBubbleHeight: CGFloat = 14
    /// Kuyruk ucunun x konumu (piksel).
    static let speechBubbleTailX: CGFloat = 3.5

    /// Beyaz tahtanın yazı alanı (22×9; tahta dokusunda x 5, y 12): 3 kareli "yazıyor" animasyonu (satırlar uzar).
    static let boardWriteSize = CGSize(width: 22, height: 9)
    static let boardWriteOrigin = CGPoint(x: 5, y: 12)
    static let boardWriteFrames: [CGImage] = {
        let lines: [[(row: Int, length: Int, color: Character)]] = [
            [(1, 10, "b")],
            [(1, 18, "b"), (3, 8, "b")],
            [(1, 18, "b"), (3, 14, "b"), (5, 6, "r")],
        ]
        return lines.compactMap { frame in
            var rows = [[Character]](repeating: [Character](repeating: "w", count: 22), count: 9)
            for l in frame { for x in 1..<(1 + l.length) { rows[l.row][x] = l.color } }
            return image(rows.map { String($0) }, palette: ["w": 0xFFFFFF, "b": 0x2F6FDE, "r": 0xE0262B])
        }
    }()

    /// 16×32 kapı (duvara oturur).
    static let door: CGImage? = {
        var rows: [String] = []
        for y in 0..<32 {
            var row = ""
            for x in 0..<16 {
                if y == 0 || x == 0 || x == 15 { row.append("k") }
                else if y == 1 || x == 1 || x == 14 { row.append("d") }
                else if (x == 12 && (y == 17 || y == 18)) { row.append("y") }
                else if (y == 5 || y == 14 || y == 15 || y == 26) && x > 2 && x < 13 { row.append("l") }
                else { row.append("b") }
            }
            rows.append(row)
        }
        return image(rows, palette: ["k": 0x3A2412, "d": 0x6B4423, "b": 0x8A5A32, "l": 0x7A4D2A, "y": 0xE0B040])
    }()
}

/// Bir oda kademesinin (küçük/orta/büyük) sabit verisi: şablon düzeni, ızgara, noktalar ve TEK pişirilmiş arka plan dokusu
/// (zemin + duvar + duvar süsleri + arkası yürünemeyen/alçak mobilya). Aynı kademedeki tüm odalar aynı dokuyu paylaşır.
@MainActor
final class OfficeRoomKit {
    let tier: OfficeRoomTier
    let layout: OfficeLayout
    let grid: OfficeGrid
    let spots: OfficeSpots
    let bounds: (minCol: Int, minRow: Int, maxCol: Int, maxRow: Int)
    let background: SKTexture
    /// Önceden pişirilmeyen (karakterlerle öne-arkaya sıralanan ya da animasyonlu) mobilya: masa, PC, bitki, sandalye.
    let dynamicFurniture: [(index: Int, placement: OfficeFurniturePlacement, asset: OfficeAsset)]

    init(tier: OfficeRoomTier, layout: OfficeLayout, grid: OfficeGrid, spots: OfficeSpots,
         bounds: (minCol: Int, minRow: Int, maxCol: Int, maxRow: Int), background: SKTexture,
         dynamicFurniture: [(index: Int, placement: OfficeFurniturePlacement, asset: OfficeAsset)]) {
        self.tier = tier; self.layout = layout; self.grid = grid; self.spots = spots
        self.bounds = bounds; self.background = background; self.dynamicFurniture = dynamicFurniture
    }

    var worldWidth: Int { (bounds.maxCol - bounds.minCol + 1) * 16 }
    var worldHeight: Int { (bounds.maxRow - bounds.minRow + 1) * 16 }
}

/// Uygulama paketinden yüklenen ofis varlıkları: düzen, mobilya kataloğu, oda kademeleri, dokular. Uzun ömürlü
/// (sayfa değişince yeniden okunmaz). Dokular `.nearest`.
@MainActor
final class OfficeAssets {
    let root: URL
    /// default-layout-1.json (tek büyük ofis): oda şablonlarının zemin/duvar renk ayarının kaynağı.
    let layout: OfficeLayout
    let catalog: [String: OfficeAsset]
    let kits: [OfficeRoomTier: OfficeRoomKit]
    private var furnitureTextures: [String: SKTexture] = [:]
    private var vectorFurnitureTextures: [String: SKTexture] = [:]
    private var vectorBackgrounds: [OfficeRoomTier: SKTexture] = [:]
    /// Vektör pişirilmiş arka plan toplam bayt (RGBA8): bellek bütçesi ölçümü için.
    private(set) var vectorBackgroundBytes = 0
    private var characterTextures: [Int: [SKTexture]] = [:]

    private static var cached: OfficeAssets?

    /// Paketteki `Office` klasörü (klasör referansı olarak kopyalanır).
    static func bundleRoot() -> URL? {
        Bundle.main.url(forResource: "Office", withExtension: nil)
            ?? Bundle(for: OfficeAssetsMarker.self).url(forResource: "Office", withExtension: nil)
    }

    static var shared: OfficeAssets? {
        if let cached { return cached }
        guard let root = bundleRoot(), let assets = OfficeAssets(root: root) else { return nil }
        cached = assets
        return assets
    }

    init?(root: URL) {
        guard let data = try? Data(contentsOf: root.appending(path: "default-layout-1.json")),
              let layout = try? OfficeLayout.parse(data) else { return nil }
        let catalog = OfficeCatalog.load(furnitureDirectory: root.appending(path: "furniture"))
        // Renkler tek ofisin zemin (1,11) ve duvar (3,10) karolarından.
        let floorColor = layout.color(1, 11), wallColor = layout.color(3, 10)
        var kits: [OfficeRoomTier: OfficeRoomKit] = [:]
        for tier in OfficeRoomTier.allCases {
            let l = OfficeRoomTemplates.layout(tier, floor: floorColor, wall: wallColor)
            let grid = OfficeGrid(layout: l, assets: catalog)
            guard let spots = OfficeSpots.derive(layout: l, assets: catalog, grid: grid) else { return nil }
            let bounds = l.visibleBounds
            guard let bg = Self.bakeBackground(root: root, layout: l, catalog: catalog, bounds: bounds) else { return nil }
            var dynamic: [(index: Int, placement: OfficeFurniturePlacement, asset: OfficeAsset)] = []
            for (i, f) in l.furniture.enumerated() {
                if let a = catalog[f.assetID], !Self.isBaked(a) { dynamic.append((i, f, a)) }
            }
            kits[tier] = OfficeRoomKit(tier: tier, layout: l, grid: grid, spots: spots, bounds: bounds,
                                       background: Self.nearest(SKTexture(cgImage: bg)), dynamicFurniture: dynamic)
        }
        self.root = root; self.layout = layout; self.catalog = catalog; self.kits = kits
    }

    func kit(_ tier: OfficeRoomTier) -> OfficeRoomKit { kits[tier]! }

    static func nearest(_ t: SKTexture) -> SKTexture { t.filteringMode = .nearest; return t }

    private static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    // MARK: Zemin + duvar + sabit mobilya

    /// Duvara asılı olanlar ve arka satırı olmayan (`backgroundTiles == 0`) mobilya karakterlerin hep arkasında kalır
    /// (üstlerinde yürünebilir karo yok): arka plana pişirilir, sahnede düğüm olmaz.
    static func isBaked(_ a: OfficeAsset) -> Bool { a.onWall || (a.backgroundTiles == 0 && !isFrontChair(a)) }

    /// Yan görünümlü yastıklı koltuk: oturan karakterin bacaklarını örtecek şekilde karakterin ÖNÜNDE çizilir (arka plana pişmez);
    /// aksi halde arkada kalıp oturan karakter "ayakta" görünür.
    static func isFrontChair(_ a: OfficeAsset) -> Bool { a.id == "CUSHIONED_CHAIR_SIDE" }

    /// Tüm zemin ve duvar karolarını (renklendirilmiş) ve pişirilebilir mobilyayı tek bir görüntüye birleştirir.
    private static func bakeBackground(root: URL, layout: OfficeLayout, catalog: [String: OfficeAsset],
                                       bounds b: (minCol: Int, minRow: Int, maxCol: Int, maxRow: Int)) -> CGImage? {
        var canvas = OfficePixels(width: (b.maxCol - b.minCol + 1) * 16, height: (b.maxRow - b.minRow + 1) * 16)
        var floors: [Int: OfficePixels] = [:]
        let wall = load(root.appending(path: "walls/wall_0.png")).flatMap(OfficePixels.init(cgImage:))
        for r in b.minRow...b.maxRow { for c in b.minCol...b.maxCol {
            let dx = (c - b.minCol) * 16, dy = (r - b.minRow) * 16
            switch layout.kind(c, r) {
            case .void: continue
            case .floor(let v):
                if floors[v] == nil, let img = load(root.appending(path: "floors/floor_\(max(0, v - 1)).png")) { floors[v] = OfficePixels(cgImage: img) }
                if let f = floors[v] { canvas.composite(f, sx: 0, sy: 0, w: 16, h: 16, dx: dx, dy: dy, color: layout.color(c, r)) }
            case .wall:
                guard let wall else { continue }
                let mask = layout.wallMask(c, r)
                // Duvar sprite'ı 16×32: karonun bir üst satırına taşar.
                canvas.composite(wall, sx: (mask % 4) * 16, sy: (mask / 4) * 32, w: 16, h: 32, dx: dx, dy: dy - 16, color: layout.color(c, r))
            }
        } }
        // Mobilya: duvardakiler önce, sonra ayak izi alt kenarına göre arkadan öne; yüzeydekiler (kahve) sahibinin üstüne.
        let baked = layout.furniture.compactMap { f -> (OfficeFurniturePlacement, OfficeAsset)? in
            guard let a = catalog[f.assetID], isBaked(a) else { return nil }
            return (f, a)
        }.sorted {
            func z(_ x: (OfficeFurniturePlacement, OfficeAsset)) -> Int { (x.1.onWall ? -1000 : 0) + (x.0.row + x.1.footprintH) * 16 + (x.1.onSurface ? 1 : 0) }
            return z($0) < z($1)
        }
        for (f, a) in baked {
            guard let img = load(root.appending(path: "furniture/\(a.file)")), var px = OfficePixels(cgImage: img) else { continue }
            if f.mirrored { px = px.flippedHorizontally() }
            canvas.composite(px, sx: 0, sy: 0, w: px.width, h: px.height, dx: (f.col - b.minCol) * 16, dy: (f.row - b.minRow) * 16, color: nil)
        }
        return canvas.cgImage()
    }

    // MARK: Mobilya

    /// Vektör doku: yumuşak (linear) süzme; büyük dokularda mipmap (uzaklaşınca titreme olmaz).
    static func smooth(_ cg: CGImage, mipmaps: Bool = false) -> SKTexture {
        let t = SKTexture(cgImage: cg)
        t.filteringMode = .linear
        t.usesMipmaps = mipmaps
        return t
    }

    /// Oda kademesinin arka planı: piksel (`kit.background`) ya da vektör (tier başına BİR kez pişirilir, odalar paylaşır).
    func background(_ tier: OfficeRoomTier, theme: OfficeTheme) -> SKTexture {
        let kit = kit(tier)
        guard theme == .vector else { return kit.background }
        if let t = vectorBackgrounds[tier] { return t }
        guard let baked = OfficeVectorArt.bakeRoom(layout: kit.layout, catalog: catalog, bounds: kit.bounds) else { return kit.background }
        vectorBackgroundBytes += baked.image.width * baked.image.height * 4
        let t = Self.smooth(baked.image, mipmaps: true)
        vectorBackgrounds[tier] = t
        return t
    }

    func windowTexture(night: Bool) -> SKTexture? {
        let key = night ? "__window_night" : "__window_day"
        if let t = vectorFurnitureTextures[key] { return t }
        guard let img = OfficeVectorArt.windowImage(night: night) else { return nil }
        let t = Self.smooth(img)
        vectorFurnitureTextures[key] = t
        return t
    }

    func furnitureTexture(_ assetID: String, theme: OfficeTheme = .pixel) -> SKTexture? {
        if theme == .vector, let a = catalog[assetID], OfficeVectorArt.furnitureIDs.contains(assetID) {
            if let t = vectorFurnitureTextures[assetID] { return t }
            guard let img = OfficeVectorArt.furniture(a) else { return nil }
            let t = Self.smooth(img)
            vectorFurnitureTextures[assetID] = t
            return t
        }
        if let t = furnitureTextures[assetID] { return t }
        guard let a = catalog[assetID], let img = Self.load(root.appending(path: "furniture/\(a.file)")) else { return nil }
        let t = Self.nearest(SKTexture(cgImage: img))
        furnitureTextures[assetID] = t
        return t
    }

    // MARK: Karakterler

    /// 21 kare (7 × 3): dizin = satır * 7 + sütun. `SKTexture(rect:in:)` aynı tek dokuyu paylaşır (atlas gibi).
    func characterFrames(_ index: Int) -> [SKTexture] {
        if let t = characterTextures[index] { return t }
        let sheet: SKTexture
        if let img = Self.load(root.appending(path: "characters/char_\(index).png")) { sheet = Self.nearest(SKTexture(cgImage: img)) } else { sheet = SKTexture() }
        var frames: [SKTexture] = []
        let sw = Double(OfficeCharacterSheet.sheetWidth), sh = Double(OfficeCharacterSheet.sheetHeight)
        for row in 0..<OfficeCharacterSheet.rows { for col in 0..<OfficeCharacterSheet.columns {
            let px = OfficeCharacterSheet.pixelRect(direction: OfficeCharacterSheet.Direction(rawValue: row) ?? .down, frame: col)
            // SKTexture birim dikdörtgeni sol-ALT başlangıçlıdır.
            let unit = CGRect(x: px.minX / sw, y: (sh - px.maxY) / sh, width: px.width / sw, height: px.height / sh)
            frames.append(Self.nearest(SKTexture(rect: unit, in: sheet)))
        } }
        characterTextures[index] = frames
        return frames
    }

    func characterTexture(index: Int, direction: OfficeCharacterSheet.Direction, frame: Int) -> SKTexture {
        let row = direction == .left ? OfficeCharacterSheet.Direction.right.rawValue : direction.rawValue
        return characterFrames(index)[row * OfficeCharacterSheet.columns + frame]
    }

    // MARK: Vektör karakterler + arayüz dokuları

    private var vectorCharTextures: [String: SKTexture] = [:]
    /// Üretilen vektör karakter kareleri toplam bayt (RGBA8, 96x128): bellek bütçesi ölçümü için.
    private(set) var vectorCharacterBytes = 0
    var vectorCharacterFrameCount: Int { vectorCharTextures.count }

    /// Tema'ya göre karakter karesi: piksel → sheet dilimi; vektör → parametrik kare (tembel üretilir, `spec.key|yön|kare` anahtarlı, bellekte tutulur).
    func characterTexture(for a: OfficeAppearance, direction: OfficeCharacterSheet.Direction, frame: Int, theme: OfficeTheme, night: Bool = false) -> SKTexture {
        guard theme == .vector else { return characterTexture(index: a.characterIndex, direction: direction, frame: frame) }
        let spec = OfficeVectorCharacter.spec(for: a)
        return vectorCharacterTexture(spec, direction: direction, frame: frame, night: night)
    }

    func vectorCharacterTexture(_ spec: OfficeVectorCharacter.Spec, direction: OfficeCharacterSheet.Direction, frame: Int, night: Bool = false) -> SKTexture {
        let dir = direction == .left ? OfficeCharacterSheet.Direction.right : direction
        let key = "\(spec.key)|\(dir.rawValue)|\(frame)" + (night ? "|n" : "")
        if let t = vectorCharTextures[key] { return t }
        guard var img = OfficeVectorCharacter.image(spec: spec, direction: dir, frame: frame) else { return SKTexture() }
        if night { img = OfficeVectorCharacter.nightGrade(img) }
        vectorCharacterBytes += img.width * img.height * 4
        let t = Self.smooth(img)
        vectorCharTextures[key] = t
        return t
    }

    private var uiTextures: [String: SKTexture] = [:]

    func panelTexture(_ p: OfficeVectorUI.Panel, bodyWidth: Int) -> SKTexture? {
        let key = String(format: "panel-%06X-%d-%d", p.fill, bodyWidth, p.h)
        if let t = uiTextures[key] { return t }
        guard let img = OfficeVectorUI.panelImage(p, bodyWidth: bodyWidth) else { return nil }
        let t = Self.smooth(img)
        uiTextures[key] = t
        return t
    }

    func bubbleBodyTexture(bodyWidth: Int) -> SKTexture? {
        let key = "bubble-\(bodyWidth)"
        if let t = uiTextures[key] { return t }
        guard let img = OfficeVectorUI.bubbleImage(bodyWidth: bodyWidth) else { return nil }
        let t = Self.smooth(img)
        uiTextures[key] = t
        return t
    }

    func solidTexture(width: Int = 16, height: Int = 16) -> SKTexture? {
        let key = "solid-\(width)x\(height)"
        if let t = uiTextures[key] { return t }
        guard let img = OfficeVectorUI.solidImage(width: width, height: height) else { return nil }
        let t = Self.smooth(img)
        uiTextures[key] = t
        return t
    }

    // MARK: Kodla çizilenler

    func accessoryTexture(_ a: OfficeAccessory) -> SKTexture? {
        let img: CGImage? = switch a {
        case .none: nil
        case .crown: OfficePixelArt.crown
        case .cap: OfficePixelArt.cap
        case .star: OfficePixelArt.star
        case .sprout: OfficePixelArt.sprout
        }
        return img.map { Self.nearest(SKTexture(cgImage: $0)) }
    }

    func bubbleTexture(_ b: OfficeBehavior.Bubble, theme: OfficeTheme) -> SKTexture? {
        if theme == .vector { return artTexture(b == .alert ? "bubble_alert" : "bubble_think", theme: .vector) }
        return bubbleTexture(b)
    }

    func bubbleTexture(_ b: OfficeBehavior.Bubble) -> SKTexture? {
        let img = b == .alert ? OfficePixelArt.alertBubble : OfficePixelArt.thinkBubble
        return img.map { Self.nearest(SKTexture(cgImage: $0)) }
    }

    private var speechBubbleTextures: [Int: SKTexture] = [:]

    /// Konuşma balonu dokusu, genişliğe göre (en çok ~25 farklı genişlik; önbellekli, paylaşılır).
    func speechBubbleTexture(width: Int) -> SKTexture? {
        let w = max(14, width)
        if let t = speechBubbleTextures[w] { return t }
        guard let img = OfficePixelArt.speechBubble(width: w) else { return nil }
        let t = Self.nearest(SKTexture(cgImage: img))
        speechBubbleTextures[w] = t
        return t
    }

    /// Beyaz tahta "yazıyor" kareleri.
    private(set) lazy var boardWriteTextures: [SKTexture] = OfficePixelArt.boardWriteFrames.map { Self.nearest(SKTexture(cgImage: $0)) }

    private var artTextures: [String: SKTexture] = [:]

    /// `OfficeArt` dokusu (önbellekli; ışık sprite'ları yumuşak, piksel-art `.nearest`).
    func artTexture(_ name: String, theme: OfficeTheme = .pixel) -> SKTexture? {
        if theme == .vector, OfficeVectorArt.hasArt(name) {
            let key = "v:" + name
            if let t = artTextures[key] { return t }
            guard let img = OfficeVectorArt.art(name) else { return nil }
            let t = Self.smooth(img)
            artTextures[key] = t
            return t
        }
        if let t = artTextures[name] { return t }
        guard let img = OfficeArt.image(name) else { return nil }
        let t = SKTexture(cgImage: img)
        t.filteringMode = name.hasPrefix("glow") ? .linear : .nearest
        artTextures[name] = t
        return t
    }

    /// Bilgisayar dokuları: kapalı + 3 ekran karesi.
    func computerFrames(_ c: OfficeComputer, theme: OfficeTheme = .pixel) -> (off: SKTexture, on: [SKTexture])? {
        guard let off = artTexture(OfficeArt.computerName(c, frame: nil), theme: theme) else { return nil }
        let on = (0..<3).compactMap { artTexture(OfficeArt.computerName(c, frame: $0), theme: theme) }
        return (off, on)
    }

    func doorTexture(theme: OfficeTheme = .pixel) -> SKTexture? {
        if theme == .vector {
            if let t = vectorFurnitureTextures["__door"] { return t }
            guard let img = OfficeVectorArt.door() else { return nil }
            let t = Self.smooth(img)
            vectorFurnitureTextures["__door"] = t
            return t
        }
        return OfficePixelArt.door.map { Self.nearest(SKTexture(cgImage: $0)) }
    }

    private(set) lazy var vectorBoardFrames: [SKTexture] = OfficeVectorArt.boardFrames().map { Self.smooth($0) }

    /// Beyaz tahta "yazıyor" kareleri (tema başına).
    func boardFrames(theme: OfficeTheme) -> [SKTexture] { theme == .vector ? vectorBoardFrames : boardWriteTextures }
}

private final class OfficeAssetsMarker {}
