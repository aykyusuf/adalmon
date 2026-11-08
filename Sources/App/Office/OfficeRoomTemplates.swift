import Foundation

/// Oda şablonları: default-layout-1.json'daki ofisin masa/PC/bank/kanepe/masa-sandalye kalıplarından türetilmiş küçük odalar.
/// Her oda: üstte duvar (2 karo yüksekliğinde, üst satır boşluk), solda ve sağda duvar sütunu, altı açık (kesit görünüm),
/// sağ duvarın en alt satırında kapı. Üst kısımda (duvar tarafı) ana ajanın YÖNETİCİ KÖŞESİ: duvarda beyaz tahta, altında büyük masa
/// (iki DESK_FRONT, iki PC) ve masanın önünde yastıklı sandalye (yönetici koltuğu, id 0); alt ajanlar köşenin altındaki sıralı masalara
/// oturur. Koltuk sayısı yönetici dahil: küçük 4, orta 8, büyük 12 (bkz. `OfficeRoomTier.capacity`):
///   küçük  = 1 yönetici + 2 masa (1 masa)               + 1 salon  (yastıklı koltuk)
///   orta   = 1 yönetici + 6 masa (3 masa)               + 1 salon
///   büyük  = 1 yönetici + 10 masa (3 masa + ortak masa) + 1 salon  (+ kahve makinesi)
enum OfficeRoomTemplates {
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

        /// Yönetici köşesi: duvarda beyaz tahta (`boardCol`), altında 6 geniş büyük masa (iki DESK_FRONT, iki PC), ana PC'nin önünde
        /// yastıklı sandalye (yönetici koltuğu). (deskCol, 3) masanın sol-üstü; sandalye (deskCol + 1, 5).
        mutating func executive(deskCol: Int, boardCol: Int) {
            add("WHITEBOARD", boardCol, 0)
            add("DESK_FRONT", deskCol, 3); add("DESK_FRONT", deskCol + 3, 3)
            add("PC_FRONT_OFF", deskCol + 1, 3); add("PC_FRONT_OFF", deskCol + 4, 3)
            add("CUSHIONED_CHAIR_BACK", deskCol + 1, 5)
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
                colors[r * cols + c] = isWall ? wall : floor
            } }
            return OfficeLayout(cols: cols, rows: rows, tiles: tiles, tileColors: colors, furniture: furniture)
        }
    }

    static func layout(_ tier: OfficeRoomTier, floor: OfficeTileColor?, wall: OfficeTileColor?) -> OfficeLayout {
        switch tier {
        case .small:
            // 4 koltuk: yönetici + 1 masa (2) + yastıklı koltuk (1).
            var b = Builder(floorW: 8, floorH: 9)
            b.executive(deskCol: 2, boardCol: 4)
            b.desk(3, 7)
            b.add("CUSHIONED_CHAIR_SIDE:left", 8, 9)
            b.add("PLANT", 1, 9); b.add("PLANT_2", 8, 2)
            b.add("DOUBLE_BOOKSHELF", 1, 0); b.add("CLOCK", 7, 0); b.add("SMALL_PAINTING", 8, 0)
            return b.layout(floor: floor, wall: wall)
        case .medium:
            // 8 koltuk: yönetici + 3 masa (6) + yastıklı koltuk (1).
            var b = Builder(floorW: 11, floorH: 9)
            b.executive(deskCol: 3, boardCol: 5)
            b.desk(1, 7); b.desk(5, 7); b.desk(9, 7)
            b.add("CUSHIONED_CHAIR_SIDE:left", 11, 4)
            b.add("PLANT", 1, 2); b.add("PLANT_2", 11, 2)
            b.add("DOUBLE_BOOKSHELF", 2, 0); b.add("CLOCK", 8, 0); b.add("LARGE_PAINTING", 9, 0); b.add("SMALL_PAINTING", 11, 0)
            return b.layout(floor: floor, wall: wall)
        case .large:
            // 12 koltuk: yönetici + 3 masa (6) + ortak masa (4) + yastıklı koltuk (1); sehpada kahve makinesi.
            var b = Builder(floorW: 13, floorH: 13)
            b.executive(deskCol: 4, boardCol: 6)
            b.desk(1, 7); b.desk(5, 7); b.desk(9, 7)
            b.table(4, 11)
            b.add("CUSHIONED_CHAIR_FRONT", 10, 11); b.add("COFFEE_TABLE", 10, 12); b.add("COFFEE", 10, 12)
            b.add("PLANT", 1, 11); b.add("PLANT_2", 13, 2)
            b.add("DOUBLE_BOOKSHELF", 1, 0); b.add("CLOCK", 4, 0); b.add("LARGE_PAINTING", 9, 0); b.add("SMALL_PAINTING_2", 12, 0)
            return b.layout(floor: floor, wall: wall)
        }
    }
}
