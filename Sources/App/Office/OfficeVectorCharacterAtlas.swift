import CoreGraphics
import Foundation

// `/v1/layout` `v3.vector.characters`: vektör karakter atlası (tarayıcı çizer). Tek renk atlası (6 look × 3 yön × 18 kare, nötr gömlek,
// aksesuarsız) + gömlek maskesi (beyaz = gömlek/kol/kapüşon; tarayıcı `multiply` ile `shirt` rengi uygular) + aksesuar atlası
// (model/rol/yardımcı: 3 yön, ayakta kare 1 ile aynı hücre konumunda çizilir). Sol yön = sağın yatay yansıması.

extension OfficeVectorCharacter {
    static let atlasDirections: [OfficeCharacterSheet.Direction] = [.down, .up, .right]
    static let atlasNeutralShirt: UInt32 = 0xF2F2F4
    static let cellW = canvasW * OfficeTheme.vectorScale   // 96
    static let cellH = canvasH * OfficeTheme.vectorScale   // 128

    static let modelAccessories = ["crown", "cap", "star", "sprout"]
    static var roleAccessories: [String] { OfficeRoleAccessory.allCases.filter { $0 != .none }.map(\.rawValue) }
    /// Aksesuar atlası satırları: (ad, tür).
    static var accessoryItems: [(name: String, kind: String)] {
        modelAccessories.map { ($0, "model") } + roleAccessories.map { ($0, "role") } + [("hardhat", "prop"), ("apron", "prop")]
    }

    private static func spec(item: (name: String, kind: String)) -> Spec {
        var s = Spec(look: 0, shirt: 0x5B8DEF)
        switch item.kind {
        case "model": s.model = item.name
        case "role": s.role = item.name
        default: s.prop = item.name == "hardhat" ? .carrier : .cleaner
        }
        return s
    }

    private static func compose(rows: Int, cols: Int, _ draw: (CGContext, Int) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: cols * cellW, height: rows * cellH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        draw(ctx, rows)
        return ctx.makeImage()
    }

    /// (renk, maske) atlasları: hücre (x = kare·96, y = (look·3 + yönSatırı)·128), y yukarıdan.
    static func characterAtlas() -> (color: CGImage, mask: CGImage)? {
        let rows = looks.count * atlasDirections.count
        func build(_ mode: Mode) -> CGImage? {
            compose(rows: rows, cols: frameCount) { ctx, rows in
                for look in 0..<looks.count {
                    let s = Spec(look: look, shirt: atlasNeutralShirt)
                    for (di, d) in atlasDirections.enumerated() {
                        for f in 0..<frameCount {
                            guard let img = image(spec: s, direction: d, frame: f, mode: mode) else { continue }
                            let row = look * atlasDirections.count + di
                            ctx.draw(img, in: CGRect(x: f * cellW, y: (rows - 1 - row) * cellH, width: cellW, height: cellH))
                        }
                    }
                }
            }
        }
        guard let c = build(.color), let m = build(.mask), let g = grayscale(m) else { return nil }
        return (c, g)
    }

    /// Maske düzlemi: 8 bit gri (beyaz = gömlek, siyah = diğer/saydam); alfa düzlemi renk atlasındadır (boyut tasarrufu).
    private static func grayscale(_ img: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: img.width, height: img.height))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return ctx.makeImage()
    }

    static func accessoryAtlas() -> CGImage? {
        let items = accessoryItems
        return compose(rows: items.count, cols: atlasDirections.count) { ctx, rows in
            for (i, item) in items.enumerated() {
                let s = spec(item: item)
                for (di, d) in atlasDirections.enumerated() {
                    guard let img = image(spec: s, direction: d, frame: 1, mode: .accessories) else { continue }
                    ctx.draw(img, in: CGRect(x: di * cellW, y: (rows - 1 - i) * cellH, width: cellW, height: cellH))
                }
            }
        }
    }

    static func uri(_ img: CGImage) -> String { "data:image/png;base64," + (OfficeArt.pngData(img)?.base64EncodedString() ?? "") }

    /// `v3.vector.characters` JSON'u. Alan adları için docs/OFFICE-V4.md "Karakter atlası".
    @MainActor static func atlasJSON() -> [String: Any] {
        let frameNames = ["walk0", "stand", "walk2", "type0", "type1", "read0", "read1", "board0", "board1", "raise0", "raise1", "yawn", "sleep",
                          "coffee0", "coffee1", "carry0", "carry1", "carry2"]
        var out: [String: Any] = [
            "scale": OfficeTheme.vectorScale, "frameWidth": canvasW, "frameHeight": canvasH, "figureWidth": 16, "padX": Int(padX),
            "cell": [cellW, cellH], "frameCount": frameCount, "frameNames": frameNames, "walkCycle": OfficeCharacterSheet.walkCycle,
            "directions": atlasDirections.map { OfficeWebLayout.directionName($0) }, "left": "mirror of right (flip x about the cell center)",
            "sitDrop": 3, "bob": (0..<frameCount).map { Double(bob(frame: $0)) },
            "frames": ["stand": 1, "walk": [0, 1, 2], "typing": [3, 4], "reading": [5, 6], "boardWrite": [7, 8], "raiseHand": [9, 10], "yawn": 11, "sleep": 12,
                       "coffee": [13, 14], "carry": [15, 16, 17]],
            "looks": looks.enumerated().map { i, l in
                ["index": i, "skin": String(format: "#%06X", l.skin), "hair": String(format: "#%06X", l.hair), "hairStyle": l.style.rawValue,
                 "pants": String(format: "#%06X", l.pants), "shoe": String(format: "#%06X", l.shoe)] as [String: Any]
            },
            "shirtTint": "color = atlas.rgb * lerp(white, shirt, mask.gray); mask is an 8-bit gray PNG, white on shirt/sleeves/hood; alpha comes from the color atlas",
            "neutralShirt": String(format: "#%06X", atlasNeutralShirt),
            "bindings": ["head": [12, 11], "face": [12, 11], "chest": [12, 20], "hand": [18, 22], "unit": "logical, cell origin top-left, y down, before bob"],
        ]
        if let atlas = characterAtlas() {
            var index: [[String: Int]] = []
            for look in 0..<looks.count { for (di, _) in atlasDirections.enumerated() { for f in 0..<frameCount {
                index.append(["look": look, "direction": di, "frame": f, "x": f * cellW, "y": (look * atlasDirections.count + di) * cellH, "w": cellW, "h": cellH])
            } } }
            out["atlas"] = ["image": uri(atlas.color), "mask": uri(atlas.mask), "width": atlas.color.width, "height": atlas.color.height,
                            "layout": "x = frame * w, y = (look * 3 + directionRow) * h", "index": index] as [String: Any]
        }
        if let acc = accessoryAtlas() {
            let items = accessoryItems
            var index: [[String: Any]] = []
            for (i, item) in items.enumerated() { for di in 0..<atlasDirections.count {
                index.append(["name": item.name, "kind": item.kind, "direction": di, "x": di * cellW, "y": i * cellH, "w": cellW, "h": cellH])
            } }
            out["accessories"] = ["image": uri(acc), "width": acc.width, "height": acc.height, "index": index,
                                  "note": "overlay cells align with the stand frame (1); shift by bob[frame]; hand items stay at the right hip"] as [String: Any]
        }
        let models: [[String: Any]] = AgentModelBadge.allCases.map { b in
            let a = OfficeAppearance.appearance(for: b)
            return ["badge": b.rawValue, "look": a.characterIndex, "shirt": String(format: "#%06X", hex(a.tint)), "accessory": accessoryName(a.accessory), "small": a.small]
        }
        out["models"] = models
        out["roles"] = OfficeRoles.knownKeys.map { key -> [String: Any] in
            let r = OfficeRoles.style(forAgentType: key)
            return ["key": r.key, "shirt": String(format: "#%06X", hex(r.tint)), "accessory": r.accessory.rawValue, "place": r.accessory.place.rawValue,
                    "hoodie": r.hoodie, "vest": r.accessory == .vest, "small": r.small]
        }
        out["props"] = [["key": "cleaner", "shirt": "#2673FA", "look": 1, "accessory": "apron"], ["key": "carrier", "shirt": "#E68C26", "look": 1, "accessory": "hardhat"]]
        return out
    }
}
