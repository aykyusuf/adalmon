import Foundation

struct OfficeTile: Hashable, Sendable {
    var col: Int
    var row: Int
    init(_ col: Int, _ row: Int) { self.col = col; self.row = row }

    func manhattan(to other: OfficeTile) -> Int { abs(col - other.col) + abs(row - other.row) }
}

/// Yürünebilir karo ızgarası + BFS yol bulma.
struct OfficeGrid: Equatable, Sendable {
    let cols: Int
    let rows: Int
    private(set) var walkable: [Bool]

    init(cols: Int, rows: Int, walkable: [Bool]) {
        precondition(walkable.count == cols * rows)
        self.cols = cols; self.rows = rows; self.walkable = walkable
    }

    /// Zemin karoları yürünür; mobilya ayak izi engel olur. Arka plan satırları (`backgroundTiles`), duvara asılı ve
    /// yüzeyde duran (PC, kahve) öğeler engel değildir.
    init(layout: OfficeLayout, assets: [String: OfficeAsset]) {
        var w = [Bool](repeating: false, count: layout.cols * layout.rows)
        for r in 0..<layout.rows { for c in 0..<layout.cols {
            if case .floor = layout.kind(c, r) { w[r * layout.cols + c] = true }
        } }
        for f in layout.furniture {
            guard let a = assets[f.assetID], !a.onWall, !a.onSurface else { continue }
            for dr in min(a.backgroundTiles, a.footprintH)..<a.footprintH { for dc in 0..<a.footprintW {
                let c = f.col + dc, r = f.row + dr
                if c >= 0, c < layout.cols, r >= 0, r < layout.rows { w[r * layout.cols + c] = false }
            } }
        }
        self.init(cols: layout.cols, rows: layout.rows, walkable: w)
    }

    func contains(_ t: OfficeTile) -> Bool { t.col >= 0 && t.col < cols && t.row >= 0 && t.row < rows }

    func isWalkable(_ t: OfficeTile) -> Bool { contains(t) && walkable[t.row * cols + t.col] }

    /// En kısa yol (4 komşu). Dönen liste başlangıcı İÇERMEZ, hedefi içerir. Başlangıç ve hedef engel olsa da geçerlidir (koltuk).
    /// Ulaşılamazsa `nil`; başlangıç = hedef ise boş liste.
    func path(from start: OfficeTile, to goal: OfficeTile) -> [OfficeTile]? {
        guard contains(start), contains(goal) else { return nil }
        if start == goal { return [] }
        var prev = [Int](repeating: -1, count: cols * rows)
        let s = start.row * cols + start.col, g = goal.row * cols + goal.col
        var queue = [s], head = 0
        prev[s] = s
        let deltas = [(0, -1), (1, 0), (0, 1), (-1, 0)]
        while head < queue.count {
            let cur = queue[head]; head += 1
            if cur == g { break }
            let cc = cur % cols, cr = cur / cols
            for (dc, dr) in deltas {
                let n = OfficeTile(cc + dc, cr + dr)
                guard contains(n) else { continue }
                let ni = n.row * cols + n.col
                guard prev[ni] == -1, walkable[ni] || ni == g else { continue }
                prev[ni] = cur
                queue.append(ni)
            }
        }
        guard prev[g] != -1 else { return nil }
        var out: [OfficeTile] = []
        var cur = g
        while cur != s { out.append(OfficeTile(cur % cols, cur / cols)); cur = prev[cur] }
        return out.reversed()
    }

    /// `from`'dan ulaşılabilen yürünür karolar.
    func reachable(from start: OfficeTile) -> Set<OfficeTile> {
        guard contains(start) else { return [] }
        var seen: Set<OfficeTile> = [start]
        var stack = [start]
        while let t = stack.popLast() {
            for (dc, dr) in [(0, -1), (1, 0), (0, 1), (-1, 0)] {
                let n = OfficeTile(t.col + dc, t.row + dr)
                if isWalkable(n), seen.insert(n).inserted { stack.append(n) }
            }
        }
        return seen
    }
}

struct OfficeSeat: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable { case desk, lounge }
    var id: Int
    var tile: OfficeTile
    var facing: OfficeCharacterSheet.Direction
    var kind: Kind
    /// Karşısındaki bilgisayarın yerleşim dizini (`layout.furniture`).
    var pcIndex: Int?
}

/// Ofis düzeninden türetilen sabit noktalar.
struct OfficeSpots: Equatable, Sendable {
    var seats: [OfficeSeat]
    /// Kapıdan içeri girilen/çıkılan yürünür karo.
    var entrance: OfficeTile
    /// Kapının kendisi (duvar/boşluk karosu): karakter burada belirir/kaybolur.
    var door: OfficeTile
    var coffee: OfficeTile?
    var coffeeFacing: OfficeCharacterSheet.Direction

    var deskSeats: [OfficeSeat] { seats.filter { $0.kind == .desk } }
    var loungeSeats: [OfficeSeat] { seats.filter { $0.kind == .lounge } }

    static func derive(layout: OfficeLayout, assets: [String: OfficeAsset], grid: OfficeGrid) -> OfficeSpots? {
        // Giriş: doğusunda duvar olan, en alttaki ve en sağdaki yürünür karo (kapı o duvarın içindedir); yoksa en alttaki yürünür karo.
        var entrance: OfficeTile?
        for c in stride(from: layout.cols - 1, through: 0, by: -1) {
            for r in stride(from: layout.rows - 1, through: 0, by: -1) where grid.isWalkable(OfficeTile(c, r)) && layout.kind(c + 1, r) == .wall {
                entrance = OfficeTile(c, r); break
            }
            if entrance != nil { break }
        }
        if entrance == nil {
            outer: for r in stride(from: layout.rows - 1, through: 0, by: -1) {
                for c in stride(from: layout.cols - 1, through: 0, by: -1) where grid.isWalkable(OfficeTile(c, r)) { entrance = OfficeTile(c, r); break outer }
            }
        }
        guard let entrance else { return nil }
        let door = OfficeTile(entrance.col + 1, entrance.row)
        let reachable = grid.reachable(from: entrance)

        // Koltuklar: "chairs" kategorisi; ayak izinin engel satırları koltuktur.
        var seats: [OfficeSeat] = []
        var chairs: [(OfficeFurniturePlacement, OfficeAsset, Int)] = []
        for (i, f) in layout.furniture.enumerated() {
            if let a = assets[f.assetID], a.category == "chairs" { chairs.append((f, a, i)) }
        }
        for (f, a, _) in chairs {
            let isSofa = a.id.hasPrefix("SOFA")
            for dr in min(a.backgroundTiles, a.footprintH)..<a.footprintH { for dc in 0..<a.footprintW {
                let tile = OfficeTile(f.col + dc, f.row + dr)
                let facing = facing(of: f, asset: a, tile: tile, layout: layout, assets: assets)
                let pc = pcIndex(from: tile, facing: facing, layout: layout, assets: assets)
                let neighbours = [(0, -1), (1, 0), (0, 1), (-1, 0)].map { OfficeTile(tile.col + $0.0, tile.row + $0.1) }
                // Ulaşılamayan (örn. çevresi tamamen engelli) koltuk listelenmez.
                guard neighbours.contains(where: { reachable.contains($0) }) else { continue }
                seats.append(OfficeSeat(id: 0, tile: tile, facing: facing, kind: isSofa ? .lounge : .desk, pcIndex: pc))
            } }
        }
        // Masa koltukları önce satır, sonra sütun sırasıyla; salon koltukları da öyle. Kimlikler sıradan.
        seats.sort { ($0.kind == .desk ? 0 : 1, $0.tile.row, $0.tile.col) < ($1.kind == .desk ? 0 : 1, $1.tile.row, $1.tile.col) }
        for i in seats.indices { seats[i].id = i }

        // Kahve makinesi: yüzeydeki COFFEE, yanında ulaşılabilir boş bir karo olan ilki.
        var coffee: OfficeTile?
        var coffeeFacing = OfficeCharacterSheet.Direction.down
        let dirs: [(Int, Int, OfficeCharacterSheet.Direction)] = [(0, 1, .up), (-1, 0, .right), (1, 0, .left), (0, -1, .down)]
        search: for f in layout.furniture where f.assetID == "COFFEE" {
            for (dc, dr, look) in dirs {
                let t = OfficeTile(f.col + dc, f.row + dr)
                if reachable.contains(t), !seats.contains(where: { $0.tile == t }) { coffee = t; coffeeFacing = look; break search }
            }
        }
        return OfficeSpots(seats: seats, entrance: entrance, door: door, coffee: coffee, coffeeFacing: coffeeFacing)
    }

    /// Koltuğun baktığı yön: ön/arka/yan varlık yönü; yönü olmayanlar (bank) en yakın masa/PC'ye bakar.
    private static func facing(of f: OfficeFurniturePlacement, asset a: OfficeAsset, tile: OfficeTile,
                               layout: OfficeLayout, assets: [String: OfficeAsset]) -> OfficeCharacterSheet.Direction {
        switch a.orientation {
        case "front": return .down
        case "back": return .up
        case "side": return f.mirrored ? .left : .right
        default:
            let probes: [(Int, Int, OfficeCharacterSheet.Direction)] = [(0, -1, .up), (1, 0, .right), (-1, 0, .left), (0, 1, .down)]
            for (dc, dr, d) in probes where tableIndex(at: OfficeTile(tile.col + dc, tile.row + dr), layout: layout, assets: assets) != nil { return d }
            return .down
        }
    }

    private static func tableIndex(at t: OfficeTile, layout: OfficeLayout, assets: [String: OfficeAsset]) -> Int? {
        layout.furniture.firstIndex { f in
            guard let a = assets[f.assetID], a.category == "desks" else { return false }
            return t.col >= f.col && t.col < f.col + a.footprintW && t.row >= f.row && t.row < f.row + a.footprintH
        }
    }

    /// Koltuğun baktığı yönde (en fazla 3 karo) ayak izi o karoyu içeren ilk PC.
    private static func pcIndex(from t: OfficeTile, facing: OfficeCharacterSheet.Direction,
                                layout: OfficeLayout, assets: [String: OfficeAsset]) -> Int? {
        let (dc, dr): (Int, Int) = switch facing { case .up: (0, -1); case .down: (0, 1); case .left: (-1, 0); case .right: (1, 0) }
        for step in 1...3 {
            let p = OfficeTile(t.col + dc * step, t.row + dr * step)
            if let i = layout.furniture.firstIndex(where: { f in
                guard let a = assets[f.assetID], a.category == "electronics" else { return false }
                return p.col >= f.col && p.col < f.col + a.footprintW && p.row >= f.row && p.row < f.row + a.footprintH
            }) { return i }
        }
        return nil
    }
}
