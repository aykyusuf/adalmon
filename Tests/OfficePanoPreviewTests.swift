import AppKit
import SpriteKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Pano (kiosk) görünümü önizlemesi: 1/2/3/6 odalı, gündüz+gece, 3840x2160 ve 2560x1440 PNG'ler (arka plan, vinyet, köşe katmanı dahil).
/// Yalnızca ADALMON_PREVIEW_DIR (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class OfficePanoPreviewTests: XCTestCase {
    private let models = ["claude-opus-4-8", "claude-sonnet-5-5", "claude-haiku-4-5", "claude-fable-1"]
    private let projects = ["adalmon", "terra-app", "site", "api-core", "docs", "infra"]

    private func session(_ i: Int, subs n: Int, now: Date = Date()) -> AgentSession {
        let types = ["scanner", "implementer", "reviewer", "ui-tester", "Explore", "Plan", "deep-reader"]
        let st: [AgentStatus] = [.tool("Bash"), .thinking, .idle, .tool("Read"), .tool("Edit"), .done]
        let subs = (0..<n).map { k in
            AgentSubagent(agentID: "s\(i)-\(k)", agentType: types[k % types.count], model: models[(k + 1) % models.count], status: st[(k + i) % st.count],
                          activity: "Bash", target: "build.sh", activityAt: now)
        }
        var s = AgentSession(id: "sess-\(i)", project: projects[i % projects.count], model: models[i % models.count],
                             status: i % 3 == 0 ? .thinking : (i % 3 == 1 ? .tool("Edit") : .idle),
                             startedAt: now.addingTimeInterval(-600), lastEventAt: now, subagents: subs, activity: "Edit", target: "main.swift", activityAt: now)
        s.title = projects[i % projects.count]
        return s
    }

    private func render(_ sessions: [AgentSession], pixels: CGSize, night: Bool) throws -> CGImage {
        let assets = try XCTUnwrap(OfficeAssets.shared)
        let points = CGSize(width: pixels.width / 2, height: pixels.height / 2)
        let view = SKView(frame: CGRect(origin: .zero, size: points))
        let scene = OfficeScene(assets: assets, size: points, theme: .vector)
        scene.setBackdropStyle(.themed)
        scene.panoMode = true
        view.presentScene(scene)
        scene.setLightingMode(night ? .night : .day, animated: false)
        let members = OfficeMember.members(from: sessions)
        scene.apply(members: members, animated: false)
        let tex = try XCTUnwrap(view.texture(from: scene))
        let base = tex.cgImage()
        scene.shutdown()
        // Köşe katmanı (SwiftUI) sahnenin üstüne bindirilir.
        let when = Date(timeIntervalSinceReferenceDate: 800_000_000 + 12 * 3600)
        let corners = OfficePanoCorners(members: members, now: when, night: night).frame(width: points.width, height: points.height)
        let renderer = ImageRenderer(content: corners)
        renderer.scale = 2
        guard let overlay = renderer.cgImage,
              let ctx = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return base }
        let rect = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        ctx.draw(base, in: rect)
        ctx.draw(overlay, in: rect)
        return ctx.makeImage() ?? base
    }

    private func write(_ cg: CGImage, _ name: String, dir: URL) throws {
        let rep = NSBitmapImageRep(cgImage: cg)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appending(path: "\(name).png"))
    }

    private func sheet(_ images: [CGImage], cols: Int, cell: CGSize) -> CGImage? {
        let rows = (images.count + cols - 1) / cols
        let w = Int(cell.width) * cols, h = Int(cell.height) * rows
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        for (i, img) in images.enumerated() {
            let col = i % cols, row = rows - 1 - i / cols
            ctx.draw(img, in: CGRect(x: CGFloat(col) * cell.width + 3, y: CGFloat(row) * cell.height + 3, width: cell.width - 6, height: cell.height - 6))
        }
        return ctx.makeImage()
    }

    func testRenderPano() throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else { throw XCTSkip("ADALMON_PREVIEW_DIR yok") }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let subs = [3, 1, 5, 2, 0, 4]
        var contact: [CGImage] = []
        for (res, px) in [("4k", CGSize(width: 3840, height: 2160)), ("1440", CGSize(width: 2560, height: 1440))] {
            for rooms in [1, 2, 3, 6] {
                let sessions = (0..<rooms).map { session($0, subs: subs[$0]) }
                for night in [false, true] {
                    let img = try render(sessions, pixels: px, night: night)
                    try write(img, "pano-\(res)-\(rooms)r-\(night ? "night" : "day")", dir: dir)
                    if res == "4k" { contact.append(img) }
                }
            }
        }
        try write(try XCTUnwrap(sheet(contact, cols: 2, cell: CGSize(width: 1280, height: 720))), "sheet-4k", dir: dir)
        // Ultra geniş (21:9) ve 32:9: eşit aralık.
        for (name, px) in [("21x9", CGSize(width: 3440, height: 1440)), ("32x9", CGSize(width: 5120, height: 1440))] {
            let img = try render((0..<2).map { session($0, subs: subs[$0]) }, pixels: px, night: false)
            try write(img, "pano-\(name)-2r-day", dir: dir)
        }
    }
}
