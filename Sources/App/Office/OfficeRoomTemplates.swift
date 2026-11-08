import Foundation

/// Oda şablonları: default-layout-1.json'daki ofisin masa/PC/bank/kanepe/masa-sandalye kalıplarından türetilmiş küçük odalar.
/// Her oda: üstte duvar (2 karo yüksekliğinde, üst satır boşluk), solda ve sağda duvar sütunu, altı açık (kesit görünüm),
/// sağ duvarın en alt satırında kapı. Koltuk sayısı: küçük 4, orta 8, büyük 12 (bkz. `OfficeRoomTier.capacity`).
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
            // 4 koltuk: 1 masa (2) + kanepe (2).
            var b = Builder(floorW: 7, floorH: 7)
            b.desk(3, 3)
            b.add("SOFA_FRONT", 2, 7)
            b.add("PLANT", 6, 7)
            b.add("DOUBLE_BOOKSHELF", 2, 0); b.add("CLOCK", 5, 0); b.add("SMALL_PAINTING", 7, 0)
            return b.layout(floor: floor, wall: wall)
        case .medium:
            // 8 koltuk: 2 masa (4) + üst/alt kanepe (4).
            var b = Builder(floorW: 9, floorH: 9)
            b.desk(2, 3); b.desk(6, 3)
            b.loungeStack(4, 7)
            b.add("PLANT", 1, 9); b.add("PLANT_2", 9, 2)
            b.add("DOUBLE_BOOKSHELF", 2, 0); b.add("CLOCK", 5, 0); b.add("WHITEBOARD", 6, 0); b.add("SMALL_PAINTING", 9, 0)
            return b.layout(floor: floor, wall: wall)
        case .large:
            // 12 koltuk: 3 masa (6) + ortak masa (4) + kanepe (2); sehpada kahve makinesi.
            var b = Builder(floorW: 13, floorH: 9)
            b.desk(2, 3); b.desk(6, 3); b.desk(10, 3)
            b.table(4, 7)
            b.add("SOFA_FRONT", 10, 7); b.add("COFFEE_TABLE", 10, 8); b.add("COFFEE", 10, 9)
            b.add("PLANT", 1, 9); b.add("PLANT_2", 13, 2)
            b.add("DOUBLE_BOOKSHELF", 2, 0); b.add("CLOCK", 5, 0); b.add("LARGE_PAINTING", 7, 0); b.add("WHITEBOARD", 10, 0); b.add("SMALL_PAINTING_2", 13, 0)
            return b.layout(floor: floor, wall: wall)
        }
    }
}
