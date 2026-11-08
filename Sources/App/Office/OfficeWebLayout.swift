import CoreGraphics
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

    static let tierKeys: [OfficeRoomTier: String] = Dictionary(uniqueKeysWithValues: OfficeRoomTier.allCases.map { ($0, $0.key) })

    static func build(officeRoot root: URL) -> Built? {
        guard let data = try? Data(contentsOf: root.appending(path: "default-layout-1.json")),
              let base = try? OfficeLayout.parse(data) else { return nil }
        let catalog = OfficeCatalog.load(furnitureDirectory: root.appending(path: "furniture"))
        let floorColor = base.color(1, 11), wallColor = base.color(3, 10)

        var tiers: [String: Any] = [:]
        var seatsByTier: [OfficeRoomTier: [OfficeSeat]] = [:]
        var usedAssets = Set<String>()
        var vectorBackgrounds: [String: Any] = [:]
        for tier in OfficeRoomTier.allCases {
            let layout = OfficeRoomTemplates.layout(tier, floor: floorColor, wall: wallColor)
            let grid = OfficeGrid(layout: layout, assets: catalog)
            guard let spots = OfficeSpots.derive(layout: layout, assets: catalog, grid: grid) else { return nil }
            seatsByTier[tier] = spots.seats
            tiers[tierKeys[tier]!] = tierJSON(tier, layout: layout, grid: grid, spots: spots, catalog: catalog, used: &usedAssets)
            if let baked = OfficeVectorArt.bakeRoom(layout: layout, catalog: catalog, bounds: layout.visibleBounds), let png = OfficeArt.pngData(baked.image) {
                vectorBackgrounds[tier.key] = ["image": "data:image/png;base64," + png.base64EncodedString(), "w": baked.image.width, "h": baked.image.height,
                                               "windows": baked.windows.map { [$0.minX, $0.minY, $0.width, $0.height] }]
            }
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
                "tintHex": OfficeRoles.hex(a.tint),
                "label": badge.label, "character": a.characterIndex, "tint": [a.tint.r, a.tint.g, a.tint.b], "tintBlend": a.tintBlend,
                "accessory": accessoryName(a.accessory), "small": a.small, "badgeText": a.badgeText,
            ] as [String: Any]
        }

        let root: [String: Any] = [
            "v": 3, "tileSize": 16, "theme": "vector",
            "v3": v3JSON(vectorBackgrounds: vectorBackgrounds, catalog: catalog),
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

    /// Ofis v3 sözleşmesi: roller, bilgisayarlar, ışık, boşta/temizlikçi/taşıyıcı sabitleri ve Swift'te üretilen dokular (data URI).
    /// Tarayıcı bunları yeniden çizmek zorunda değildir (tek doğruluk kaynağı Swift).
    static func v3JSON(vectorBackgrounds: [String: Any] = [:], catalog: [String: OfficeAsset] = [:]) -> [String: Any] {
        let roles: [[String: Any]] = OfficeRoles.knownKeys.map { key in
            let r = OfficeRoles.style(forAgentType: key)
            return ["key": r.key, "tint": r.tintHex, "accessory": r.accessory.rawValue, "place": r.accessory.place.rawValue, "small": r.small, "hoodie": r.hoodie, "labelColor": OfficeRoles.hex(r.labelColor)]
        }
        var generated: [String: String] = [:]
        for name in OfficeArt.defs.keys.sorted() { if let u = OfficeArt.dataURI(name) { generated[name] = u } }
        for g in OfficeArt.glows { if let u = OfficeArt.dataURI(g.name) { generated[g.name] = u } }
        let computers: [[String: Any]] = OfficeArt.allComputers.map { c in
            ["kind": c.kind.rawValue, "color": c.color.rawValue, "name": c.artName,
             "off": OfficeArt.computerName(c, frame: nil), "on": (0..<3).map { OfficeArt.computerName(c, frame: $0) }]
        }
        return [
            "roles": roles,
            "roleFallback": ["accessory": "tag", "hsl": ["s": 0.55, "l": 0.55], "hash": "fnv1a64(key) % 360 (OfficeStroll.seed)"],
            "computers": computers,
            "computerPick": ["seed": "fnv1a64(roomID + \"|pc|\" + seatKey)", "imacShare": 0.55, "imacColors": OfficeComputer.imacColors.map(\.rawValue),
                             "macbookColors": OfficeComputer.macbookColors.map(\.rawValue), "executive": "imac_silver", "seatKey": "row*100+col", "rollFn": "splitmix64"],
            "lighting": [
                "modes": OfficeLightingMode.allCases.map(\.rawValue), "nightStartHour": OfficeLighting.nightStartMinutes / 60, "nightStartMinute": OfficeLighting.nightStartMinutes % 60,
                "nightEndHour": OfficeLighting.nightEndMinutes / 60, "nightEndMinute": OfficeLighting.nightEndMinutes % 60,
                "overlayColor": [0.14, 0.18, 0.40], "overlayAlpha": OfficeLighting.nightOverlayAlpha, "overlayBlend": "multiply", "crossfade": OfficeLighting.crossfade,
                "glows": OfficeArt.glows.map { ["name": $0.name, "w": $0.width, "h": $0.height, "rgb": [$0.r, $0.g, $0.b], "alpha": $0.alpha] as [String: Any] },
            ] as [String: Any],
            "idle": ["variants": OfficeIdleVariant.allCases.map(\.rawValue), "durationMin": OfficeIdle.duration.lowerBound, "durationMax": OfficeIdle.duration.upperBound,
                     "wanderChance": OfficeIdle.wanderChance, "wanderGapMin": OfficeIdle.wanderGap.lowerBound, "wanderGapMax": OfficeIdle.wanderGap.upperBound,
                     "wanderStayMin": OfficeIdle.wanderStay.lowerBound, "wanderStayMax": OfficeIdle.wanderStay.upperBound],
            "cleaner": ["intervalMin": OfficeCleaner.interval.lowerBound, "intervalMax": OfficeCleaner.interval.upperBound, "route": "S", "character": 1,
                        "tint": [0.15, 0.45, 0.98], "tintBlend": 0.6, "prop": "mop", "trailArt": "glow_trail", "trailFade": 3.2, "stepSeconds": OfficeRoomNode.stepDuration],
            "carrier": ["steps": OfficeCarrier.sequence(withCarrier: true).map(\.rawValue), "dropSeconds": OfficeCarrier.dropDuration, "growFade": OfficeCarrier.growFade,
                        "character": 1, "tint": [0.9, 0.55, 0.15], "tintBlend": 0.5, "prop": "box"],
            "generated": generated,
            "vector": vectorJSON(backgrounds: vectorBackgrounds, catalog: catalog),
        ]
    }

    /// Vektör tema (4x PNG data URI'leri). `generated` ile AYNI anahtarlar (bilgisayarlar, lamba) + `glows`, `furniture` (varlık kimliği → PNG),
    /// `door`, `boardWrite`, `windows` ve oda başına pişirilmiş `backgrounds`. Mantıksal boyut = PNG / `scale`. Bkz. docs/OFFICE-V4.md.
    static func vectorJSON(backgrounds: [String: Any], catalog: [String: OfficeAsset]) -> [String: Any] {
        func uri(_ img: CGImage?) -> String? { img.flatMap { OfficeArt.pngData($0) }.map { "data:image/png;base64," + $0.base64EncodedString() } }
        var generated: [String: String] = [:]
        for name in OfficeVectorArt.artNames { if let u = uri(OfficeVectorArt.art(name)) { generated[name] = u } }
        var furniture: [String: String] = [:]
        for (id, a) in catalog where OfficeVectorArt.furnitureIDs.contains(id) { if let u = uri(OfficeVectorArt.furniture(a)) { furniture[id] = u } }
        let lp = OfficeLightParams.vector
        return [
            "theme": "vector", "scale": OfficeTheme.vectorScale, "filter": "linear", "generated": generated, "furniture": furniture,
            "door": uri(OfficeVectorArt.door()) ?? "", "boardWrite": OfficeVectorArt.boardFrames().compactMap { uri($0) },
            "boardWriteOrigin": [OfficeVectorArt.boardWriteOrigin.x, OfficeVectorArt.boardWriteOrigin.y],
            "windowDay": uri(OfficeVectorArt.windowImage(night: false)) ?? "", "windowNight": uri(OfficeVectorArt.windowImage(night: true)) ?? "",
            "backgrounds": backgrounds,
            "characters": OfficeVectorCharacter.atlasJSON(),
            "lighting": ["multiplyColor": OfficeLightParams.duskFactor, "washColor": lp.overlayRGB, "washAlpha": lp.overlayAlpha, "bulbAlpha": lp.bulbAlpha,
                          "poolAlpha": lp.poolAlpha, "boardAlpha": lp.boardAlpha, "screenAlpha": lp.screenAlpha, "windowAlpha": lp.windowAlpha] as [String: Any],
        ]
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
            item["computerKey"] = OfficeRoomNode.seatKey(s)
            if s.kind == .executive, let board = spots.board, let path = zoneGrid?.path(from: s.tile, to: board) { item["toBoard"] = path.map(tile) }
            seats.append(item)
        }

        let n = tier.stations
        let blocks: [[String: Int]] = (0..<OfficeRoomTemplates.blocks(stations: n)).map {
            let o = OfficeRoomTemplates.blockOrigin($0)
            return ["i": $0, "col": o.col, "row": o.row]
        }
        // Masa lambaları: her masa bloğunun ortasında (karo koordinatı + masa üstü piksel sapması) ve yönetici masasında.
        var lamps: [[String: Any]] = blocks.map { ["col": ($0["col"] ?? 0) + 1, "row": $0["row"] ?? 0, "dx": 8, "dy": 14] }
        if let ex = layout.furniture.first(where: { $0.assetID == "SMALL_TABLE_FRONT" }) { lamps.append(["col": ex.col + 1, "row": ex.row, "dx": 0, "dy": 14]) }   // sahnede x = col·16 + 16
        let ct = OfficeRoomTemplates.coffeeTable(stations: n)
        var out: [String: Any] = [
            "key": tier.key, "stations": n, "blocks": blocks, "laneRows": OfficeRoomTemplates.laneRows(stations: n),
            "lamps": lamps, "coffeeTable": ["col": ct.col, "row": ct.row], "floorWidth": OfficeRoomTemplates.floorWidth(stations: n),
            "floorHeight": OfficeRoomTemplates.floorHeight(stations: n),
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
