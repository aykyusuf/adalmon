import Foundation

/// Tarayıcı ofisi için `GET /v1/layout`: oda şablonları (zemin/duvar karoları, mobilya yerleşimi, koltuklar, yürüme yolları),
/// karakter sprite bilgisi, model görünümü ve kodla çizilen piksel-art. Tek doğruluk kaynağı Swift'tir (şablon, katalog,
/// koltuk türetme, görünüm eşlemesi); JS yalnızca çizer. Dosya okumak tek seferliktir (özellik açılırken).
@MainActor
enum OfficeWebLayout {
    struct Built {
        var json: Data
        /// Oda planlayıcı için kademe başına koltuklar (durum JSON'undaki `seat` kimlikleri bunlara bakar).
        var seats: [OfficeRoomTier: [OfficeSeat]]
    }

    static let tierKeys: [OfficeRoomTier: String] = [.small: "small", .medium: "medium", .large: "large"]

    static func build(officeRoot root: URL) -> Built? {
        guard let data = try? Data(contentsOf: root.appending(path: "default-layout-1.json")),
              let base = try? OfficeLayout.parse(data) else { return nil }
        let catalog = OfficeCatalog.load(furnitureDirectory: root.appending(path: "furniture"))
        let floorColor = base.color(1, 11), wallColor = base.color(3, 10)

        var tiers: [String: Any] = [:]
        var seatsByTier: [OfficeRoomTier: [OfficeSeat]] = [:]
        var usedAssets = Set<String>()
        for tier in OfficeRoomTier.allCases {
            let layout = OfficeRoomTemplates.layout(tier, floor: floorColor, wall: wallColor)
            let grid = OfficeGrid(layout: layout, assets: catalog)
            guard let spots = OfficeSpots.derive(layout: layout, assets: catalog, grid: grid) else { return nil }
            seatsByTier[tier] = spots.seats
            tiers[tierKeys[tier]!] = tierJSON(tier, layout: layout, grid: grid, spots: spots, catalog: catalog, used: &usedAssets)
        }

        var furniture: [String: Any] = [:]
        for id in usedAssets.sorted() {
            guard let a = catalog[id] else { continue }
            var item: [String: Any] = [
                "file": a.file, "w": a.width, "h": a.height, "fw": a.footprintW, "fh": a.footprintH, "bg": a.backgroundTiles,
                "category": a.category, "onWall": a.onWall, "onSurface": a.onSurface,
            ]
            if let o = a.orientation { item["orientation"] = o }
            if let frames = OfficeBehavior.pcOnFrames(forOffAsset: id) {
                item["pcOn"] = frames.compactMap { catalog[$0]?.file }
            }
            furniture[id] = item
        }

        var appearance: [String: Any] = [:]
        for badge in AgentModelBadge.allCases {
            let a = OfficeAppearance.appearance(for: badge)
            appearance[badge.rawValue] = [
                "label": badge.label, "character": a.characterIndex, "tint": [a.tint.r, a.tint.g, a.tint.b], "tintBlend": a.tintBlend,
                "accessory": accessoryName(a.accessory), "small": a.small, "badgeText": a.badgeText,
            ] as [String: Any]
        }

        let root: [String: Any] = [
            "v": 1, "tileSize": 16,
            "characters": [
                "file": "characters/char_%d.png", "sheetWidth": OfficeCharacterSheet.sheetWidth, "sheetHeight": OfficeCharacterSheet.sheetHeight,
                "frameWidth": OfficeCharacterSheet.frameWidth, "frameHeight": OfficeCharacterSheet.frameHeight,
                "columns": OfficeCharacterSheet.columns, "walkCycle": OfficeCharacterSheet.walkCycle,
                "frames": ["stand": OfficeCharacterSheet.frameIndex(.stand), "typing": [3, 4], "reading": [5, 6]],
                "rows": ["down": 0, "up": 1, "right": 2, "left": 2], "sitDrop": 3,
            ] as [String: Any],
            "appearance": appearance,
            "groupColors": OfficeAppearance.groupColors.map { [$0.r, $0.g, $0.b] },
            "art": artJSON(),
            "tiers": tiers,
            "furniture": furniture,
            "files": ["wall": "walls/wall_0.png", "floor": "floors/floor_%d.png"],
            "bubbleLifetime": OfficeBubbleText.lifetime,
            "strollSeconds": OfficeExecutive.idleStrollDuration,
            "maxCharacters": OfficeRoomTier.maxCharacters,
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) else { return nil }
        return Built(json: json, seats: seatsByTier)
    }

    static func accessoryName(_ a: OfficeAccessory) -> String {
        switch a {
        case .none: "none"
        case .crown: "crown"
        case .cap: "cap"
        case .star: "star"
        case .sprout: "sprout"
        }
    }

    static func directionName(_ d: OfficeCharacterSheet.Direction) -> String {
        switch d {
        case .down: "down"
        case .up: "up"
        case .left: "left"
        case .right: "right"
        }
    }

    static func seatKindName(_ k: OfficeSeat.Kind) -> String {
        switch k {
        case .executive: "executive"
        case .desk: "desk"
        case .lounge: "lounge"
        }
    }

    private static func tierJSON(_ tier: OfficeRoomTier, layout: OfficeLayout, grid: OfficeGrid, spots: OfficeSpots,
                                 catalog: [String: OfficeAsset], used: inout Set<String>) -> [String: Any] {
        let b = layout.visibleBounds
        // Karo başına [tür (0 boş, 1 duvar, 2 zemin), zemin görseli, duvar maskesi, renk indeksi].
        var palette: [[Double]] = []
        var tiles: [Int] = []
        for r in 0..<layout.rows { for c in 0..<layout.cols {
            var ci = -1
            if let col = layout.color(c, r) {
                let entry = [col.h, col.s, col.b, col.c]
                if let i = palette.firstIndex(of: entry) { ci = i } else { palette.append(entry); ci = palette.count - 1 }
            }
            switch layout.kind(c, r) {
            case .void: tiles += [0, 0, 0, -1]
            case .wall: tiles += [1, 0, layout.wallMask(c, r), ci]
            case .floor(let v): tiles += [2, max(0, v - 1), 0, ci]
            }
        } }

        var placements: [[String: Any]] = []
        for (index, f) in layout.furniture.enumerated() {
            guard let a = catalog[f.assetID] else { continue }
            used.insert(a.id)
            if let frames = OfficeBehavior.pcOnFrames(forOffAsset: a.id) { frames.forEach { used.insert($0) } }
            let baked = OfficeAssets.isBaked(a)
            // Öne-arkaya sıra (sahnedekiyle aynı): pişirilenler karakterlerin hep altında; diğerleri ayak izi alt kenarına göre.
            var z = Double((f.row + a.footprintH) * 16) + (a.onSurface ? 0.2 : 0) + (OfficeAssets.isFrontChair(a) ? 0.8 : 0)
            if baked { z = (a.onWall ? -2000 : -1000) + Double((f.row + a.footprintH) * 16) + (a.onSurface ? 1 : 0) }
            placements.append(["i": index, "asset": a.id, "col": f.col, "row": f.row, "mirrored": f.mirrored, "z": z])
        }

        func tile(_ t: OfficeTile) -> [Int] { [t.col, t.row] }
        let zoneGrid = layout.executiveZone.map { grid.restricted(to: $0) }
        var seats: [[String: Any]] = []
        for s in spots.seats {
            var item: [String: Any] = [
                "id": s.id, "col": s.tile.col, "row": s.tile.row, "facing": directionName(s.facing), "kind": seatKindName(s.kind),
                "enter": (grid.path(from: spots.entrance, to: s.tile) ?? []).map(tile),
            ]
            if let pc = s.pcIndex { item["pc"] = pc }
            if s.kind == .executive, let board = spots.board, let path = zoneGrid?.path(from: s.tile, to: board) { item["toBoard"] = path.map(tile) }
            seats.append(item)
        }

        var out: [String: Any] = [
            "capacity": tier.capacity, "cols": layout.cols, "rows": layout.rows,
            "bounds": ["minCol": b.minCol, "minRow": b.minRow, "maxCol": b.maxCol, "maxRow": b.maxRow],
            "tiles": tiles, "colors": palette, "furniture": placements, "seats": seats,
            "entrance": tile(spots.entrance), "door": tile(spots.door), "coffeeMachine": tier.hasCoffee,
        ]
        if let coffee = spots.coffee { out["coffee"] = ["tile": tile(coffee), "facing": directionName(spots.coffeeFacing)] }
        if let board = spots.board { out["board"] = tile(board) }
        if let boardIndex = spots.boardIndex { out["boardIndex"] = boardIndex }
        if let z = spots.zone { out["zone"] = ["minCol": z.minCol, "minRow": z.minRow, "maxCol": z.maxCol, "maxRow": z.maxRow] }
        out["zoneTiles"] = spots.zoneTiles.map(tile)
        return out
    }

    /// Kodla çizilen piksel-art tanımları (satırlar + palet); JS bunları canvas'a boyar. Kaynak: `OfficePixelArt`.
    private static func artJSON() -> [String: Any] {
        func art(_ rows: [String], _ palette: [Character: String]) -> [String: Any] {
            ["rows": rows, "palette": Dictionary(uniqueKeysWithValues: palette.map { (String($0.key), $0.value) })]
        }
        var door: [String] = []
        for y in 0..<32 {
            var row = ""
            for x in 0..<16 {
                if y == 0 || x == 0 || x == 15 { row.append("k") }
                else if y == 1 || x == 1 || x == 14 { row.append("d") }
                else if x == 12 && (y == 17 || y == 18) { row.append("y") }
                else if (y == 5 || y == 14 || y == 15 || y == 26) && x > 2 && x < 13 { row.append("l") }
                else { row.append("b") }
            }
            door.append(row)
        }
        let boardLines: [[(row: Int, length: Int, color: Character)]] = [
            [(1, 10, "b")], [(1, 18, "b"), (3, 8, "b")], [(1, 18, "b"), (3, 14, "b"), (5, 6, "r")],
        ]
        let boardFrames: [[String: Any]] = boardLines.map { frame in
            var rows = [[Character]](repeating: [Character](repeating: "w", count: 22), count: 9)
            for l in frame { for x in 1..<(1 + l.length) { rows[l.row][x] = l.color } }
            return art(rows.map { String($0) }, ["w": "#FFFFFF", "b": "#2F6FDE", "r": "#E0262B"])
        }
        return [
            "crown": art(["y...y...y", "yy.yyy.yy", "yyyyyyyyy", "yyyryyyyy", "ddddddddd"], ["y": "#FFD700", "d": "#B8860B", "r": "#E0262B"]),
            "cap": art(["..bbbbbb..", ".bblbbbbb.", "bbbbbbbbbb", "dddddddddd"], ["b": "#2F6FDE", "l": "#7FB0FF", "d": "#1B4DA8"]),
            "star": art(["...y...", "..yyy..", "yyyyyyy", ".yyyyy.", "..yyy..", ".yy.yy.", ".o...o."], ["y": "#FFC400", "o": "#FF8A00"]),
            "sprout": art([".gg.gg.", "ggg.ggg", ".ggdgg.", "...d...", "...d..."], ["g": "#4CD964", "d": "#2E8B3D"]),
            "alertBubble": art(["..kkkkkkk..", ".kwwwwwwwk.", "kwwwwowwwwk", "kwwwwowwwwk", "kwwwwowwwwk", "kwwwwowwwwk",
                                "kwwwwwwwwwk", "kwwwwowwwwk", ".kwwwwwwwk.", "..kkkwkkk..", "....kwk....", ".....k....."],
                               ["k": "#222222", "w": "#FFFFFF", "o": "#FF8A00"]),
            "door": art(door, ["k": "#3A2412", "d": "#6B4423", "b": "#8A5A32", "l": "#7A4D2A", "y": "#E0B040"]),
            "boardWrite": boardFrames,
            "boardWriteOrigin": [5, 12],
        ]
    }
}
