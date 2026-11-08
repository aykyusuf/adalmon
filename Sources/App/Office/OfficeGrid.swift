import Foundation

struct OfficeTile: Hashable, Sendable {
    var col: Int
    var row: Int
    init(_ col: Int, _ row: Int) { self.col = col; self.row = row }

    func manhattan(to other: OfficeTile) -> Int { abs(col - other.col) + abs(row - other.row) }
}

/// Karo dikdörtgeni (kapsayıcı): yönetici bölgesi gibi alanlar.
struct OfficeRect: Equatable, Sendable {
    var minCol: Int
    var minRow: Int
    var maxCol: Int
    var maxRow: Int

    func contains(_ t: OfficeTile) -> Bool { t.col >= minCol && t.col <= maxCol && t.row >= minRow && t.row <= maxRow }
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

    /// Yalnızca `rect` içindeki karoları yürünür bırakan kopya: bu ızgarada bulunan yollar bölgeden çıkmaz.
    func restricted(to rect: OfficeRect) -> OfficeGrid {
        var w = walkable
        for r in 0..<rows { for c in 0..<cols where !rect.contains(OfficeTile(c, r)) { w[r * cols + c] = false } }
        return OfficeGrid(cols: cols, rows: rows, walkable: w)
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
    /// `executive`: ana ajanın (oturumun) yönetici köşesindeki koltuğu; odada tek, üye sayısına dahil.
    enum Kind: Equatable, Sendable { case executive, desk, lounge }
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
    /// Yönetici beyaz tahtasının önünde durulan karo (yukarı bakar) ve tahtanın yerleşim dizini (`layout.furniture`).
    var board: OfficeTile?
    var boardIndex: Int?
    /// Yönetici bölgesi (üst orta şerit: tahta önü + yönetici masası) ve içindeki ulaşılabilir yürünür karolar (volta rotası).
    /// Yönetici bu bölgeden çıkmaz; şablon `OfficeLayout.executiveZone` verir.
    var zone: OfficeRect?
    var zoneTiles: [OfficeTile] = []

    var executiveSeat: OfficeSeat? { seats.first { $0.kind == .executive } }
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
            let kind = seatKind(for: a)
            for dr in min(a.backgroundTiles, a.footprintH)..<a.footprintH { for dc in 0..<a.footprintW {
                let tile = OfficeTile(f.col + dc, f.row + dr)
                let facing = facing(of: f, asset: a, tile: tile, layout: layout, assets: assets)
                let pc = pcIndex(from: tile, facing: facing, layout: layout, assets: assets)
                let neighbours = [(0, -1), (1, 0), (0, 1), (-1, 0)].map { OfficeTile(tile.col + $0.0, tile.row + $0.1) }
                // Ulaşılamayan (örn. çevresi tamamen engelli) koltuk listelenmez.
                guard neighbours.contains(where: { reachable.contains($0) }) else { continue }
                seats.append(OfficeSeat(id: 0, tile: tile, facing: facing, kind: kind, pcIndex: pc))
            } }
        }
        // Yönetici koltuğu (id 0), sonra masa koltukları (önce satır, sonra sütun), sonra salon koltukları. Kimlikler sıradan.
        func rank(_ k: OfficeSeat.Kind) -> Int { switch k { case .executive: 0; case .desk: 1; case .lounge: 2 } }
        seats.sort { (rank($0.kind), $0.tile.row, $0.tile.col) < (rank($1.kind), $1.tile.row, $1.tile.col) }
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

        // Beyaz tahta: duvardaki WHITEBOARD'un hemen altındaki ulaşılabilir karo (yönetici orada ayakta yazar).
        var board: OfficeTile?
        var boardIndex: Int?
        for (i, f) in layout.furniture.enumerated() where f.assetID == "WHITEBOARD" {
            guard let a = assets[f.assetID] else { continue }
            let t = OfficeTile(f.col, f.row + a.footprintH)
            if reachable.contains(t) { board = t; boardIndex = i; break }
        }
        var zone: OfficeRect?
        var zoneTiles: [OfficeTile] = []
        if let z = layout.executiveZone {
            zone = z
            // Mobilya ayak izinin tamamı (arka plan satırı dahil) dışında kalan, ulaşılabilir karolar: masanın arkasında yürünmez.
            func covered(_ t: OfficeTile) -> Bool {
                layout.furniture.contains { f in
                    guard let a = assets[f.assetID], !a.onWall, !a.onSurface else { return false }
                    return t.col >= f.col && t.col < f.col + a.footprintW && t.row >= f.row && t.row < f.row + a.footprintH
                }
            }
            for r in z.minRow...z.maxRow { for c in z.minCol...z.maxCol where reachable.contains(OfficeTile(c, r)) && !covered(OfficeTile(c, r)) { zoneTiles.append(OfficeTile(c, r)) } }
        }
        return OfficeSpots(seats: seats, entrance: entrance, door: door, coffee: coffee, coffeeFacing: coffeeFacing, board: board, boardIndex: boardIndex,
                           zone: zone, zoneTiles: zoneTiles)
    }

    /// Koltuk türü varlıktan: arkadan görünen yastıklı sandalye (CUSHIONED_CHAIR_BACK) yönetici koltuğu, kanepe ve yastıklı ön/yan
    /// koltuklar salon, diğerleri (bank, ahşap sandalye) masa koltuğudur. Şablonlar bu eşlemeye göre kurulur.
    static func seatKind(for a: OfficeAsset) -> OfficeSeat.Kind {
        if a.id == "CUSHIONED_CHAIR_BACK" { return .executive }
        if a.id.hasPrefix("SOFA") || a.id.hasPrefix("CUSHIONED_CHAIR") { return .lounge }
        return .desk
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
