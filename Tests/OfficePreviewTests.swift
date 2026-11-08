import AppKit
import SpriteKit
import XCTest
@testable import Adalmon

/// Ofis sahnesini gerçek pencere olmadan `SKView.texture(from:)` ile PNG'ye çizer.
/// Yalnızca ADALMON_PREVIEW_DIR (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class OfficePreviewTests: XCTestCase {
    private func render(_ members: [OfficeMember], size: CGSize, name: String, dir: URL) throws {
        let assets = try XCTUnwrap(OfficeAssets.shared, "ofis varlıkları yüklenemedi")
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let scene = OfficeScene(assets: assets, size: size)
        view.presentScene(scene)
        scene.apply(members: members, animated: false)
        let tex = try XCTUnwrap(view.texture(from: scene), "texture(from:) nil")
        let cg = tex.cgImage()
        let rep = NSBitmapImageRep(cgImage: cg)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: dir.appending(path: "\(name).png"))
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
        try render(OfficeMember.members(from: OfficeDemo.showcase), size: size, name: "office-demo", dir: dir)
        // Küçük pencere (zoom 2) ve taşma: 16 üye.
        try render(OfficeMember.members(from: OfficeDemo.showcase), size: CGSize(width: 700, height: 460), name: "office-small", dir: dir)
        let now = Date()
        let statuses: [AgentStatus] = [.thinking, .tool("Edit"), .waitingPermission, .idle, .done]
        let models = ["claude-opus-4-8", "claude-sonnet-5-5", "claude-haiku-4-5", "claude-fable-1", "x"]
        let busy = (0..<9).map { i in
            AgentSession(id: "b\(i)", project: "proje-\(i)", model: models[i % 5], status: statuses[i % 5], startedAt: now.addingTimeInterval(Double(-i)), lastEventAt: now,
                         subagents: i % 3 == 0 ? [AgentSubagent(agentID: "s\(i)", agentType: "Explore", model: models[(i + 2) % 5], status: .thinking)] : [])
        }
        try render(OfficeMember.members(from: busy), size: size, name: "office-busy", dir: dir)
    }
}
