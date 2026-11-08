import AppKit
import SpriteKit
import XCTest
@testable import Adalmon

/// Ofis sahnesini gerçek pencere olmadan `SKView.texture(from:)` ile PNG'ye çizer.
/// Yalnızca ADALMON_PREVIEW_DIR (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class OfficePreviewTests: XCTestCase {
    private func render(_ members: [OfficeMember], size: CGSize, name: String, dir: URL, select: Int? = nil) throws {
        let assets = try XCTUnwrap(OfficeAssets.shared, "ofis varlıkları yüklenemedi")
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let scene = OfficeScene(assets: assets, size: size)
        view.presentScene(scene)
        scene.apply(members: members, animated: false)
        if let select, select < scene.roomIDs.count { scene.select(scene.roomIDs[select], animated: false) }
        let tex = try XCTUnwrap(view.texture(from: scene), "texture(from:) nil")
        let cg = tex.cgImage()
        let rep = NSBitmapImageRep(cgImage: cg)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: dir.appending(path: "\(name).png"))
        print("ONIZLEME \(name) \(cg.width)x\(cg.height) odalar=\(scene.roomCount) zoom=\(scene.zoom) dugum=\(scene.nodeCount) gorunur=\(scene.visibleRoomCount)")
        XCTAssertGreaterThan(cg.width, 100)
    }

    func testRenderOffice() throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let size = CGSize(width: 1000, height: 640)
        try render([], size: size, name: "office-empty", dir: dir)
        try render(OfficeMember.members(from: OfficeDemo.single()), size: size, name: "office-1-session", dir: dir)
        try render(OfficeMember.members(from: OfficeDemo.showcase), size: size, name: "office-3-sessions", dir: dir)
        try render(OfficeMember.members(from: OfficeDemo.showcase), size: size, name: "office-3-sessions-focus", dir: dir, select: 2)
        try render(OfficeMember.members(from: OfficeDemo.single()), size: CGSize(width: 1400, height: 900), name: "office-1-session-large-window", dir: dir)
        try render(OfficeMember.members(from: OfficeDemo.crowd()), size: size, name: "office-10x10", dir: dir)
        try render(OfficeMember.members(from: OfficeDemo.crowd()), size: size, name: "office-10x10-focus", dir: dir, select: 2)
        try render(OfficeMember.members(from: OfficeDemo.crowd()), size: CGSize(width: 1500, height: 900), name: "office-10x10-large-window", dir: dir)
        // Taşma: 1 oturum, 14 alt ajan → "+3".
        let now = Date()
        let models = ["claude-opus-4-8", "claude-sonnet-5-5", "claude-haiku-4-5", "claude-fable-1"]
        let overflow = AgentSession(id: "of", project: "taşma-testi", model: models[0], status: .thinking, startedAt: now, lastEventAt: now,
                                    subagents: (0..<14).map { AgentSubagent(agentID: "o\($0)", agentType: "worker-\($0)", model: models[$0 % 4], status: .tool("Bash")) })
        try render(OfficeMember.members(from: [overflow]), size: size, name: "office-overflow", dir: dir)
    }
}
