import AppKit
import SpriteKit
import XCTest
@testable import Adalmon

/// Etiket/balon çakışma önizlemesi (gündüz + gece). Yalnızca ADALMON_PREVIEW_DIR (TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class OfficeLabelPreviewTests: XCTestCase {
    private func session(subs: Int, now: Date = Date()) -> AgentSession {
        let types = ["crew-chief:scanner", "crew-chief:scanner", "crew-chief:implementer", "crew-chief:implementer-hard", "Explore", "crew-chief:ui-tester",
                     "crew-chief:scanner", "crew-chief:deep-reader", "crew-chief:reviewer", "Plan", "crew-chief:scanner"]
        let statuses: [AgentStatus] = [.thinking, .thinking, .tool("Bash"), .thinking, .tool("Read"), .waitingPermission, .thinking, .tool("Grep"), .thinking, .idle, .tool("Edit")]
        let list = (0..<subs).map { i in
            AgentSubagent(agentID: "s\(i)", agentType: types[i % types.count], model: "claude-sonnet-5-5", status: statuses[i % statuses.count],
                          activity: "Bash", target: "build.sh", activityAt: now)
        }
        return AgentSession(id: "main", project: "adalmon", model: "claude-opus-4-8", status: .tool("Edit"), startedAt: now.addingTimeInterval(-600), lastEventAt: now,
                            subagents: list, activity: "Edit", target: "main.swift", activityAt: now)
    }

    func testRenderLabels() throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else { throw XCTSkip("ADALMON_PREVIEW_DIR yok") }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let assets = try XCTUnwrap(OfficeAssets.shared)
        for subs in [6, 11] {
            for night in [false, true] {
                let size = CGSize(width: 1600, height: 1000)
                let view = SKView(frame: CGRect(origin: .zero, size: size))
                let scene = OfficeScene(assets: assets, size: size, theme: .vector)
                view.presentScene(scene)
                scene.setLightingMode(night ? .night : .day, animated: false)
                scene.apply(members: OfficeMember.members(from: [session(subs: subs)]), animated: false)
                if let id = scene.roomIDs.first { scene.select(id, animated: false) }
                let tex = try XCTUnwrap(view.texture(from: scene))
                let rep = NSBitmapImageRep(cgImage: tex.cgImage())
                try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appending(path: "labels-\(subs)subs-\(night ? "night" : "day").png"))
                scene.shutdown()
            }
        }
    }
}
