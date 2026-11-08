import Foundation

/// Oda şablonları: default-layout-1.json'daki ofisin masa/PC/bank/kanepe/masa-sandalye kalıplarından türetilmiş küçük odalar.
/// Her oda: üstte duvar (2 karo yüksekliğinde, üst satır boşluk), solda ve sağda duvar sütunu, altı açık (kesit görünüm),
/// sağ duvarın en alt satırında kapı. Üst ortada ana ajanın YÖNETİCİ ALANI: duvarda ortada beyaz tahta, önünde boş bir halı şeridi
/// (yönetici bölgesi: satır 2-4, ayakta yazma ve volta için), şeridin sağ ucunda küçük yönetici masası + yastıklı sandalye
/// (yönetici koltuğu, id 0). Alt ajan masaları (satır 6'dan) bölgeden ayrıdır; yönetici bölgeden çıkmaz. Koltuk sayısı yönetici
/// dahil: küçük 4, orta 8, büyük 12 (bkz. `OfficeRoomTier.capacity`):
///   küçük  = 1 yönetici + 2 masa (1 masa)               + 1 salon  (yastıklı koltuk)      zemin 8 × 8
///   orta   = 1 yönetici + 6 masa (3 masa)               + 1 salon                           zemin 11 × 8
///   büyük  = 1 yönetici + 10 masa (3 masa + ortak masa) + 1 salon  (+ kahve makinesi)       zemin 13 × 13
enum OfficeRoomTemplates {
    /// Yönetici şeridinin satırları (duvarın hemen altından): 2 tahta önü, 3 volta, 4 yönetici sandalyesi.
    static let zoneRows = 2...4
    /// Alt ajan masalarının ilk satırı (şeritle arada 1 satır boşluk).
    static let deskRow = 6
    /// Yönetici halısı: zemin renginden ayrı, mavimsi.
    static let carpet = OfficeTileColor(h: 214, s: 34, b: -30, c: -80)

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

        /// 4 koltuklu ortak masa: iki yanda ikişer sandalye ve yan PC. (col, row) masanın sol-üstü; sandalyeler col-1 ve col+3.
        mutating func table(_ col: Int, _ row: Int) {
            add("TABLE_FRONT", col, row)
            add("WOODEN_CHAIR_SIDE", col - 1, row); add("WOODEN_CHAIR_SIDE", col - 1, row + 2)
            add("WOODEN_CHAIR_SIDE:left", col + 3, row); add("WOODEN_CHAIR_SIDE:left", col + 3, row + 2)
            add("PC_SIDE", col, row); add("PC_SIDE", col, row + 2)
            add("PC_SIDE:left", col + 2, row); add("PC_SIDE:left", col + 2, row + 2)
        }

        /// Yönetici alanı: duvarda ortada beyaz tahta (`boardCol`, 2 karo), sağ uçta (`deskCol`, 2 karo) küçük yönetici masası ve
        /// PC'si; masanın önünde (deskCol, 4) yastıklı sandalye (yönetici koltuğu). Tahta önü ve volta şeridi masanın solundadır.
        mutating func executive(deskCol: Int, boardCol: Int) {
            add("WHITEBOARD", boardCol, 0)
            add("SMALL_TABLE_FRONT", deskCol, OfficeRoomTemplates.zoneRows.lowerBound)
            add("PC_FRONT_OFF", deskCol, OfficeRoomTemplates.zoneRows.lowerBound)
            add("CUSHIONED_CHAIR_BACK", deskCol, OfficeRoomTemplates.zoneRows.upperBound)
        }

        /// Üst kanepe, ortada sehpa, alt kanepe → 4 salon koltuğu. (col, row) üst kanepenin sol-üstü.
        mutating func loungeStack(_ col: Int, _ row: Int) {
            add("SOFA_FRONT", col, row)
            add("COFFEE_TABLE", col, row + 1)
            add("SOFA_BACK", col, row + 3)
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
        let d = deskRow
        switch tier {
        case .small:
            // 4 koltuk: yönetici + 1 masa (2) + yastıklı koltuk (1).
            var b = Builder(floorW: 8, floorH: 8)
            b.executive(deskCol: 7, boardCol: 4)
            b.desk(3, d)
            b.add("CUSHIONED_CHAIR_SIDE:left", 8, d + 1)
            b.add("PLANT", 1, d); b.add("PLANT_2", 8, 4)
            b.add("DOUBLE_BOOKSHELF", 1, 0); b.add("CLOCK", 7, 0); b.add("SMALL_PAINTING", 8, 0)
            return b.layout(floor: floor, wall: wall)
        case .medium:
            // 8 koltuk: yönetici + 3 masa (6) + yastıklı koltuk (1).
            var b = Builder(floorW: 11, floorH: 8)
            b.executive(deskCol: 10, boardCol: 5)
            b.desk(1, d); b.desk(5, d); b.desk(9, d)
            b.add("CUSHIONED_CHAIR_SIDE", 1, d - 1)
            b.add("PLANT_2", 11, 4)
            b.add("DOUBLE_BOOKSHELF", 2, 0); b.add("CLOCK", 8, 0); b.add("LARGE_PAINTING", 9, 0); b.add("SMALL_PAINTING", 11, 0)
            return b.layout(floor: floor, wall: wall)
        case .large:
            // 12 koltuk: yönetici + 3 masa (6) + ortak masa (4) + yastıklı koltuk (1); sehpada kahve makinesi.
            var b = Builder(floorW: 13, floorH: 13)
            b.executive(deskCol: 12, boardCol: 6)
            b.desk(1, d); b.desk(5, d); b.desk(9, d)
            b.table(4, 10)
            b.add("CUSHIONED_CHAIR_FRONT", 10, 10); b.add("COFFEE_TABLE", 10, 11); b.add("COFFEE", 10, 11)
            b.add("PLANT", 1, 10); b.add("PLANT_2", 13, 4)
            b.add("DOUBLE_BOOKSHELF", 1, 0); b.add("CLOCK", 4, 0); b.add("LARGE_PAINTING", 9, 0); b.add("SMALL_PAINTING_2", 12, 0)
            return b.layout(floor: floor, wall: wall)
        }
    }
}
