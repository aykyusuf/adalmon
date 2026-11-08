import AppKit
import SpriteKit
import XCTest
@testable import Adalmon

/// Ofis v4 (vektör tema) önizlemesi: piksel ↔ vektör yan yana PNG'ler + yakın çekimler + düğüm/bellek ölçümü.
/// Yalnızca ADALMON_PREVIEW_DIR (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class OfficeV4PreviewTests: XCTestCase {
    private let models = ["claude-opus-4-8", "claude-sonnet-5-5", "claude-haiku-4-5", "claude-fable-1"]

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

    private func write(_ cg: CGImage, _ name: String, dir: URL) throws {
        let rep = NSBitmapImageRep(cgImage: cg)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appending(path: "\(name).png"))
    }

    private func crop(_ cg: CGImage, _ r: CGRect) -> CGImage {
        let rect = CGRect(x: r.minX * CGFloat(cg.width), y: r.minY * CGFloat(cg.height), width: r.width * CGFloat(cg.width), height: r.height * CGFloat(cg.height))
        return cg.cropping(to: rect) ?? cg
    }

    /// Basit kontak sayfası: görüntüler `cols` sütunlu ızgarada, hücreye sığacak şekilde.
    private func sheet(_ images: [CGImage], cols: Int, cell: CGSize) -> CGImage? {
        let rows = (images.count + cols - 1) / cols
        let w = Int(cell.width) * cols, h = Int(cell.height) * rows
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        for (i, img) in images.enumerated() {
            let col = i % cols, row = rows - 1 - i / cols
            let s = min(cell.width / CGFloat(img.width), cell.height / CGFloat(img.height))
            let dw = CGFloat(img.width) * s, dh = CGFloat(img.height) * s
            ctx.draw(img, in: CGRect(x: CGFloat(col) * cell.width + (cell.width - dw) / 2, y: CGFloat(row) * cell.height + (cell.height - dh) / 2, width: dw, height: dh))
        }
        return ctx.makeImage()
    }

    func testRenderV4() throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else { throw XCTSkip("ADALMON_PREVIEW_DIR yok") }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let few = [session("a", subs: ["scanner", "implementer-hard", "reviewer"])]
        let eight = [session("b", subs: ["scanner", "deep-reader", "implementer", "implementer-hard", "reviewer", "ui-tester", "Explore", "Plan"])]
        let crowdTypes = ["scanner", "deep-reader", "implementer", "implementer-hard", "reviewer", "ui-tester", "ui-smoke", "Explore", "Plan", "general-purpose"]
        let crowd = (0..<10).map { i in session("c\(i)", subs: (0..<10).map { crowdTypes[($0 + i) % crowdTypes.count] }, status: i % 2 == 0 ? .thinking : .idle) }

        var compare: [CGImage] = []
        let big = CGSize(width: 1000, height: 640)
        for (name, ss, size) in [("1s3", few, big), ("1s8", eight, CGSize(width: 1000, height: 700))] {
            for night in [false, true] {
                for theme in [OfficeTheme.pixel, .vector] {
                    let (img, scene) = try render(ss, theme: theme, night: night, size: size)
                    let tag = "\(name)-\(theme.rawValue)-\(night ? "night" : "day")"
                    try write(img, tag, dir: dir)
                    compare.append(img)
                    print("V4 \(tag) \(img.width)x\(img.height) zoom=\(scene.zoom) dugum=\(scene.nodeCount)")
                }
            }
        }
        try write(try XCTUnwrap(sheet(compare, cols: 2, cell: CGSize(width: 1000, height: 700))), "sheet-compare", dir: dir)

        // 10x10: bellek + düğüm
        let before = residentMB()
        var crowdImgs: [CGImage] = []
        for theme in [OfficeTheme.pixel, .vector] {
            for night in [false, true] {
                let (img, scene) = try render(crowd, theme: theme, night: night, size: CGSize(width: 1500, height: 900))
                try write(img, "10x10-\(theme.rawValue)-\(night ? "night" : "day")", dir: dir)
                crowdImgs.append(img)
                print("V4 10x10 \(theme.rawValue) night=\(night) zoom=\(scene.zoom) dugum=\(scene.nodeCount) odalar=\(scene.roomCount) gorunur=\(scene.visibleRoomCount) rss=\(Int(residentMB()))MB")
            }
        }
        print("V4 vektor-pisirme-bayt=\((OfficeAssets.shared?.vectorBackgroundBytes ?? 0) / 1_048_576)MB rss-once=\(Int(before))MB rss-sonra=\(Int(residentMB()))MB")
        try write(try XCTUnwrap(sheet(crowdImgs, cols: 2, cell: CGSize(width: 1500, height: 900))), "sheet-10x10", dir: dir)

        // yakın çekimler: oda odağı (kesirli zoom 8x'e kadar) ve kırpmalar
        var close: [CGImage] = []
        for night in [false, true] {
            let (img, scene) = try render(eight, theme: .vector, night: night, size: CGSize(width: 1800, height: 1500), select: 0)
            try write(img, "close-room-\(night ? "night" : "day")", dir: dir)
            print("V4 close night=\(night) zoom=\(scene.zoom)")
            close.append(crop(img, CGRect(x: 0.0, y: 0.0, width: 1, height: 0.30)))      // duvar: pencere, tahta, kitaplık
            close.append(crop(img, CGRect(x: 0.0, y: 0.28, width: 1, height: 0.36)))     // masalar: iMac/MacBook
        }
        try write(try XCTUnwrap(sheet(close, cols: 2, cell: CGSize(width: 1800, height: 700))), "sheet-close", dir: dir)
        let (px, _) = try render(eight, theme: .pixel, night: false, size: CGSize(width: 1800, height: 1500), select: 0)
        try write(px, "close-room-pixel", dir: dir)
    }
}
