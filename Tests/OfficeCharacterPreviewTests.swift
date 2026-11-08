import AppKit
import SpriteKit
import XCTest
@testable import Adalmon

/// Vektör karakter önizlemesi (kontak sayfası, rol kadrosu, sahneler). Yalnızca ADALMON_PREVIEW_DIR (TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class OfficeCharacterPreviewTests: XCTestCase {
    private let models = ["claude-opus-4-8", "claude-sonnet-5-5", "claude-haiku-4-5", "claude-fable-1"]

    private func previewDir() throws -> URL {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else { throw XCTSkip("ADALMON_PREVIEW_DIR yok") }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ cg: CGImage, _ name: String, dir: URL) throws {
        let rep = NSBitmapImageRep(cgImage: cg)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appending(path: "\(name).png"))
    }

    private func canvas(_ w: Int, _ h: Int, bg: UInt32 = 0xC9AE86, _ draw: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(ctx.vc(bg)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        draw(ctx)
        return ctx.makeImage()
    }

    private func caption(_ ctx: CGContext, _ s: String, x: CGFloat, y: CGFloat, size: CGFloat = 13) {
        let g = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = g
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: NSColor(white: 0.1, alpha: 1)]).draw(at: CGPoint(x: x, y: y))
        NSGraphicsContext.restoreGraphicsState()
    }

    private func appearance(look: Int) -> OfficeAppearance {
        let badges: [AgentModelBadge] = [.sonnet, .sonnet, .opus, .unknown, .haiku, .fable]
        var a = OfficeAppearance.appearance(for: badges[look])
        if look == 1 { a = OfficeAppearance(characterIndex: 1, tint: OfficeRGB(r: 0.15, g: 0.45, b: 0.98), tintBlend: 0.6, accessory: .none, small: false, badgeText: ""); a.prop = .cleaner }
        return a
    }

    func testContactSheet() throws {
        let dir = try previewDir()
        let cols = [0, 1, 2, 3, 4, 5, 6, 7, 9, 11, 12, 13, 14, 16]
        let dirs: [OfficeCharacterSheet.Direction] = [.down, .up, .right]
        for (n, looks) in [[0, 1, 2], [3, 4, 5]].enumerated() {
            let cw = 96, ch = 128
            let img = canvas(cw * cols.count, ch * looks.count * dirs.count) { c in
                let totalRows = looks.count * dirs.count
                for (li, look) in looks.enumerated() {
                    let spec = OfficeVectorCharacter.spec(for: appearance(look: look))
                    for (di, d) in dirs.enumerated() {
                        for (ci, f) in cols.enumerated() {
                            guard let cg = OfficeVectorCharacter.image(spec: spec, direction: d, frame: f) else { XCTFail("kare yok \(look) \(d) \(f)"); continue }
                            let row = li * dirs.count + di
                            c.draw(cg, in: CGRect(x: ci * cw, y: (totalRows - 1 - row) * ch, width: cw, height: ch))
                        }
                    }
                }
            }
            try write(try XCTUnwrap(img), "contact-\(n == 0 ? "a" : "b")", dir: dir)
        }
    }

    func testRoster() throws {
        let dir = try previewDir()
        let keys = OfficeRoles.knownKeys
        let badges: [AgentModelBadge] = [.sonnet, .opus, .haiku, .fable, .unknown]
        let cols = 5, rows = (keys.count + cols - 1) / cols
        let bw = 300, bh = 230
        let img = canvas(bw * cols, bh * rows) { c in
            for (i, key) in keys.enumerated() {
                let m = OfficeMember(id: key, parentID: "p", kind: .subagent, label: key, badge: badges[i % badges.count], status: .tool("Edit"), groupIndex: 0)
                let spec = OfficeVectorCharacter.spec(for: OfficeAppearance.appearance(for: m))
                let col = i % cols, row = rows - 1 - i / cols
                let x0 = col * bw, y0 = row * bh
                for (k, (d, f)) in [(OfficeCharacterSheet.Direction.down, 1), (.up, 3)].enumerated() {
                    if let cg = OfficeVectorCharacter.image(spec: spec, direction: d, frame: f) { c.draw(cg, in: CGRect(x: x0 + 20 + k * 130, y: y0 + 30, width: 144, height: 192)) }
                }
                caption(c, "\(key) [\(spec.role)\(spec.hoodie ? "+hood" : "")]", x: CGFloat(x0 + 8), y: CGFloat(y0 + 8), size: 12)
            }
        }
        try write(try XCTUnwrap(img), "roster", dir: dir)
    }

    private func session(_ id: String, subs types: [String], status: AgentStatus = .tool("Edit"), now: Date = Date()) -> AgentSession {
        let subStatus: [AgentStatus] = [.tool("Bash"), .thinking, .idle, .tool("Read"), .waitingPermission, .done, .tool("Grep"), .idle, .tool("Edit")]
        let subs = types.enumerated().map { i, t in
            AgentSubagent(agentID: "\(id)-\(i)", agentType: t, model: models[(i + 1) % models.count], status: subStatus[i % subStatus.count],
                          activity: "Bash", target: "build.sh", activityAt: now)
        }
        return AgentSession(id: id, project: "adalmon", model: models[0], status: status, startedAt: now.addingTimeInterval(-600), lastEventAt: now,
                            subagents: subs, activity: "Edit", target: "main.swift", activityAt: now)
    }

    private func residentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
        return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }

    private func render(_ sessions: [AgentSession], theme: OfficeTheme, night: Bool, size: CGSize, select: Int? = nil) throws -> (CGImage, OfficeScene) {
        let assets = try XCTUnwrap(OfficeAssets.shared)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let scene = OfficeScene(assets: assets, size: size, theme: theme)
        view.presentScene(scene)
        scene.setLightingMode(night ? .night : .day, animated: false)
        scene.apply(members: OfficeMember.members(from: sessions), animated: false)
        if let select, select < scene.roomIDs.count { scene.select(scene.roomIDs[select], animated: false) }
        let tex = try XCTUnwrap(view.texture(from: scene))
        scene.shutdown()
        return (tex.cgImage(), scene)
    }

    private func crop(_ cg: CGImage, _ r: CGRect) -> CGImage {
        cg.cropping(to: CGRect(x: r.minX * CGFloat(cg.width), y: r.minY * CGFloat(cg.height), width: r.width * CGFloat(cg.width), height: r.height * CGFloat(cg.height))) ?? cg
    }

    func testScenes() throws {
        let dir = try previewDir()
        let few = [session("a", subs: ["scanner", "implementer-hard", "reviewer"])]
        let eight = [session("b", subs: ["scanner", "deep-reader", "implementer", "implementer-hard", "reviewer", "ui-tester", "Explore", "Plan"])]
        let crowdTypes = ["scanner", "deep-reader", "implementer", "implementer-hard", "reviewer", "ui-tester", "ui-smoke", "Explore", "Plan", "general-purpose"]
        let crowd = (0..<10).map { i in session("c\(i)", subs: (0..<10).map { crowdTypes[($0 + i) % crowdTypes.count] }, status: i % 2 == 0 ? .thinking : .idle) }
        let assets = try XCTUnwrap(OfficeAssets.shared)
        for (name, ss, size) in [("s4", few, CGSize(width: 1000, height: 640)), ("s9", eight, CGSize(width: 1000, height: 700))] {
            for night in [false, true] {
                let (img, scene) = try render(ss, theme: .vector, night: night, size: size)
                try write(img, "\(name)-\(night ? "night" : "day")", dir: dir)
                print("CHAR \(name) night=\(night) zoom=\(scene.zoom) dugum=\(scene.nodeCount)")
            }
        }
        let before = residentMB()
        for night in [false, true] {
            let (img, scene) = try render(crowd, theme: .vector, night: night, size: CGSize(width: 1500, height: 900))
            try write(img, "10x10-\(night ? "night" : "day")", dir: dir)
            print("CHAR 10x10 night=\(night) zoom=\(scene.zoom) dugum=\(scene.nodeCount) rss=\(Int(residentMB()))MB")
        }
        print("CHAR karakter-kare=\(assets.vectorCharacterFrameCount) bayt=\(assets.vectorCharacterBytes / 1_048_576)MB rss-once=\(Int(before)) rss-sonra=\(Int(residentMB()))")
        var close: [CGImage] = []
        for night in [false, true] {
            let (img, scene) = try render(eight, theme: .vector, night: night, size: CGSize(width: 1800, height: 1500), select: 0)
            try write(img, "close-room-\(night ? "night" : "day")", dir: dir)
            print("CHAR close night=\(night) zoom=\(scene.zoom)")
            close.append(crop(img, CGRect(x: 0.2, y: 0.12, width: 0.6, height: 0.28)))
            close.append(crop(img, CGRect(x: 0.2, y: 0.40, width: 0.6, height: 0.28)))
        }
        let (px, _) = try render(eight, theme: .pixel, night: false, size: CGSize(width: 1800, height: 1500), select: 0)
        try write(px, "close-room-pixel", dir: dir)
        let (vec, _) = try render(eight, theme: .vector, night: false, size: CGSize(width: 1800, height: 1500), select: 0)
        let a = crop(px, CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.3)), b = crop(vec, CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.3))
        let w = a.width, h = a.height
        let ba = canvas(w, h * 2) { c in c.draw(a, in: CGRect(x: 0, y: h, width: w, height: h)); c.draw(b, in: CGRect(x: 0, y: 0, width: w, height: h)) }
        try write(try XCTUnwrap(ba), "before-after", dir: dir)
        let cl = canvas(close[0].width * 2, close[0].height * 2) { c in
            for (i, img) in close.enumerated() { c.draw(img, in: CGRect(x: (i % 2) * close[0].width, y: (1 - i / 2) * close[0].height, width: close[0].width, height: close[0].height)) }
        }
        try write(try XCTUnwrap(cl), "close-crops", dir: dir)
    }
}
