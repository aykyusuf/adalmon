import Foundation

/// Oda şablonları: default-layout-1.json'daki ofisin masa/PC/bank kalıplarından türetilmiş PARAMETRİK odalar (ofis v3).
/// Her oda: üstte duvar (2 karo yüksekliğinde, üst satır boşluk), solda ve sağda duvar sütunu, altı açık (kesit görünüm),
/// sağ duvarın en alt satırında kapı. Üst ortada ana ajanın YÖNETİCİ ALANI: duvarda ortada beyaz tahta, önünde boş bir halı şeridi
/// (yönetici bölgesi: satır 2-4), şeridin sağ ucunda küçük yönetici masası + yastıklı sandalye (yönetici koltuğu, id 0).
/// Alt ajan istasyonları 2'li masa blokları (3 geniş masa, iki uçta bilgisayar, önünde iki bank) olarak satır başına 3 blok dizilir
/// (blok i: sütun 1 + 4·(i mod 3), satır 6 + 4·(i div 3)); bu yüzden bir üst kademe her zaman alt kademenin üst kümesidir
/// (oturanlar yerinde kalır, büyüme yalnızca istasyon ekler). Her odada alt koridorda kahve makinesi vardır. Salon koltuğu yoktur.
///   istasyon: 2, 4, 6, 8, 12, 16  →  zemin genişliği 8 (≤4 istasyon) ya da 11; yüksekliği 4·satır+6 (satır = ⌈blok/3⌉).
enum OfficeRoomTemplates {
    /// Yönetici şeridinin satırları (duvarın hemen altından): 2 tahta önü, 3 volta, 4 yönetici sandalyesi.
    static let zoneRows = 2...4
    /// Alt ajan masalarının ilk satırı (şeritle arada 1 satır boşluk).
    static let deskRow = 6
    /// Yönetici halısı: zemin renginden ayrı, mavimsi.
    static let carpet = OfficeTileColor(h: 214, s: 34, b: -30, c: -80)
    static let blocksPerRow = 3

    static func blocks(stations: Int) -> Int { (stations + 1) / 2 }
    static func blockRows(stations: Int) -> Int { max(1, (blocks(stations: stations) + blocksPerRow - 1) / blocksPerRow) }
    static func floorWidth(stations: Int) -> Int { stations <= 4 ? 8 : 11 }
    static func floorHeight(stations: Int) -> Int { 4 * blockRows(stations: stations) + 6 }
    /// Blok i'nin masa sol-üst karosu.
    static func blockOrigin(_ i: Int) -> (col: Int, row: Int) { (1 + 4 * (i % blocksPerRow), deskRow + 4 * (i / blocksPerRow)) }
    /// Kahve masasının sol-üst karosu (alt koridor: sütun 3-4; bank arası cepler ve en alt koridor satırı açık kalır; makineye soldan yaklaşılır).
    static func coffeeTable(stations: Int) -> (col: Int, row: Int) { (3, 4 * blockRows(stations: stations) + 5) }
    /// Temizlikçi rotasının koridor satırları (koltuk sıraları arası + alt koridor).
    static func laneRows(stations: Int) -> [Int] {
        let r = blockRows(stations: stations)
        return [5] + (0..<(r - 1)).map { 4 * $0 + 9 } + [4 * r + 7]
    }

    private struct Builder {
        let floorW: Int
        let floorH: Int
        var furniture: [OfficeFurniturePlacement] = []

        mutating func add(_ type: String, _ col: Int, _ row: Int) { furniture.append(OfficeFurniturePlacement(type: type, col: col, row: row)) }

        /// 3 geniş masa, iki uçta PC, önünde iki bank → 2 masa koltuğu. (col, row) masanın sol-üstü.
        mutating func desk(_ col: Int, _ row: Int) {
            add("DESK_FRONT", col, row)
            add("PC_FRONT_OFF", col, row); add("PC_FRONT_OFF", col + 2, row)
            add("CUSHIONED_BENCH", col, row + 2); add("CUSHIONED_BENCH", col + 2, row + 2)
        }

        /// Yönetici alanı: duvarda ortada beyaz tahta (`boardCol`, 2 karo), sağ uçta (`deskCol`, 2 karo) küçük yönetici masası ve
        /// PC'si; masanın önünde (deskCol, 4) yastıklı sandalye (yönetici koltuğu). Tahta önü ve volta şeridi masanın solundadır.
        mutating func executive(deskCol: Int, boardCol: Int) {
            add("WHITEBOARD", boardCol, 0)
            add("SMALL_TABLE_FRONT", deskCol, OfficeRoomTemplates.zoneRows.lowerBound)
            add("PC_FRONT_OFF", deskCol, OfficeRoomTemplates.zoneRows.lowerBound)
            add("CUSHIONED_CHAIR_BACK", deskCol, OfficeRoomTemplates.zoneRows.upperBound)
        }

        func layout(floor: OfficeTileColor?, wall: OfficeTileColor?) -> OfficeLayout {
            let cols = floorW + 2, rows = floorH + 2
            var tiles = [Int](repeating: 255, count: cols * rows)
            var colors = [OfficeTileColor?](repeating: nil, count: cols * rows)
            for c in 0..<cols { tiles[1 * cols + c] = 0; colors[1 * cols + c] = wall }
            for r in 2..<rows { for c in 0..<cols {
                let isWall = c == 0 || c == cols - 1
                tiles[r * cols + c] = isWall ? 0 : 7
                colors[r * cols + c] = isWall ? wall : (OfficeRoomTemplates.zoneRows.contains(r) ? OfficeRoomTemplates.carpet : floor)
            } }
            let zone = OfficeRect(minCol: 1, minRow: OfficeRoomTemplates.zoneRows.lowerBound, maxCol: floorW, maxRow: OfficeRoomTemplates.zoneRows.upperBound)
            return OfficeLayout(cols: cols, rows: rows, tiles: tiles, tileColors: colors, furniture: furniture, executiveZone: zone)
        }
    }

    static func layout(_ tier: OfficeRoomTier, floor: OfficeTileColor?, wall: OfficeTileColor?) -> OfficeLayout {
        let n = tier.stations
        let w = floorWidth(stations: n), h = floorHeight(stations: n)
        var b = Builder(floorW: w, floorH: h)
        b.executive(deskCol: w - 1, boardCol: w / 2)
        for i in 0..<blocks(stations: n) { let o = blockOrigin(i); b.desk(o.col, o.row) }
        let ct = coffeeTable(stations: n)
        b.add("COFFEE_TABLE", ct.col, ct.row); b.add("COFFEE", ct.col, ct.row)
        b.add("PLANT", 1, 4 * blockRows(stations: n) + 5)
        if w == 8 {
            b.add("PLANT_2", 8, 4)
            b.add("DOUBLE_BOOKSHELF", 1, 0); b.add("CLOCK", 7, 0); b.add("SMALL_PAINTING", 8, 0)
        } else {
            b.add("PLANT_2", 11, 4)
            b.add("DOUBLE_BOOKSHELF", 2, 0); b.add("CLOCK", 8, 0); b.add("LARGE_PAINTING", 9, 0); b.add("SMALL_PAINTING", 11, 0)
        }
        return b.layout(floor: floor, wall: wall)
    }
}
