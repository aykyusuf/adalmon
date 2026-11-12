import AppKit
import SpriteKit
import XCTest
@testable import Adalmon

/// Ofis kedisi önizlemesi (opt-in): poz sayfası + ofis içinde kedi PNG'leri. Yalnızca ADALMON_PREVIEW_DIR
/// (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class OfficeCatPreviewTests: XCTestCase {
    private func write(_ cg: CGImage, _ name: String, dir: URL) throws {
        let rep = NSBitmapImageRep(cgImage: cg)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appending(path: "\(name).png"))
    }

    private func previewDir() throws -> URL {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else { throw XCTSkip("ADALMON_PREVIEW_DIR yok") }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Tüm pozlar tek sayfada (açık/koyu zemin).
    func testPoseSheet() throws {
        let dir = try previewDir()
        let scale = 6
        var frames: [(String, CGImage)] = []
        for p in OfficeCatPose.allCases { for f in 0..<p.frameCount { if let img = OfficeCatArt.image(p, frame: f, scale: scale) { frames.append(("\(p.rawValue)\(f)", img)) } } }
        let cols = 6, rows = (frames.count + cols - 1) / cols
        let cw = OfficeCatArt.canvasW * scale, ch = OfficeCatArt.canvasH * scale
        for (name, bg) in [("light", CGColor(srgbRed: 0.82, green: 0.78, blue: 0.70, alpha: 1)), ("dark", CGColor(srgbRed: 0.16, green: 0.17, blue: 0.22, alpha: 1))] {
            let ctx = try XCTUnwrap(CGContext(data: nil, width: cw * cols, height: ch * rows, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: 0, width: cw * cols, height: ch * rows))
            for (i, (_, img)) in frames.enumerated() {
                let x = (i % cols) * cw, y = (rows - 1 - i / cols) * ch
                let drawn = name == "dark" ? OfficeVectorCharacter.nightGrade(img) : img
                ctx.draw(drawn, in: CGRect(x: x, y: y, width: cw, height: ch))
            }
            try write(try XCTUnwrap(ctx.makeImage()), "cat-poses-\(name)", dir: dir)
        }
    }

    private func members() -> [OfficeMember] {
        var out = [OfficeMember(id: "s", parentID: nil, kind: .session, label: "adalmon", badge: .opus, status: .tool("Edit"), groupIndex: 0)]
        let st: [AgentStatus] = [.tool("Bash"), .idle, .thinking, .tool("Read")]
        for i in 0..<4 { out.append(OfficeMember(id: "s#\(i)", parentID: "s", kind: .subagent, label: "implementer", badge: .sonnet, status: st[i], groupIndex: 0)) }
        return out
    }

    /// Ofis içinde kedi: yürüme, masada oturma, masada klavyeye uzanma, uyku, kalp tepkisi; açık/koyu.
    func testCatInOffice() throws {
        let dir = try previewDir()
        let assets = try XCTUnwrap(OfficeAssets.shared)
        let size = CGSize(width: 720, height: 560)
        for night in [false, true] {
            var shots: [CGImage] = []
            for scenario in 0..<5 {
                let view = SKView(frame: CGRect(origin: .zero, size: size))
                let scene = OfficeScene(assets: assets, size: size, theme: .vector)
                view.presentScene(scene)
                scene.setLightingMode(night ? .night : .day, animated: false)
                scene.apply(members: members(), animated: false)
                scene.select(scene.roomIDs[0], animated: false)
                scene.setCat(enabled: true, rng: .seeded(7))
                let cat = try XCTUnwrap(scene.cat)
                let now = Date()
                cat.clock = { now }
                let room = try XCTUnwrap(cat.room)
                let w = room.catWorld
                let perch = w.perches[min(1, w.perches.count - 1)]
                let ap = try XCTUnwrap(w.approach(to: perch, from: w.entrance))
                let lane = w.floor.filter { $0.row == 5 }
                let mid = lane.isEmpty ? w.entrance : lane[lane.count / 2]
                switch scenario {
                case 0: cat.startPlan(OfficeCatPlan(activity: .wander, steps: [.walk(mid)], end: .floor(mid)), now: now); cat.fastForwardFirstStepForPreview()
                case 1: cat.startPlan(OfficeCatPlan(activity: .climb, steps: [.walk(ap.tile), .up(perch.id), .pose(.sit, 30)], end: .perch(perch.id)), now: now); while cat.isAnimating { cat.fastForward() }
                case 2: cat.startPlan(OfficeCatPlan(activity: .climb, steps: [.walk(ap.tile), .up(perch.id), .pose(.lieKeys, 30)], end: .perch(perch.id)), now: now); while cat.isAnimating { cat.fastForward() }
                case 3: cat.startPlan(OfficeCatPlan(activity: .nap, steps: [.walk(mid), .pose(.sleep, 120)], end: .floor(mid)), now: now); while cat.isAnimating { cat.fastForward() }
                default: _ = cat.greet(now: now, zoom: scene.zoom)
                }
                let tex = try XCTUnwrap(view.texture(from: scene))
                shots.append(tex.cgImage())
                scene.shutdown()
            }
            let cw = Int(size.width), ch = Int(size.height) * 5 / 5
            _ = ch
            for (i, img) in shots.enumerated() { try write(img, "cat-office-\(night ? "dark" : "light")-\(i)", dir: dir) }
            _ = cw
        }
    }
}
