import AppKit
import SpriteKit
import XCTest
@testable import Adalmon

/// Ofis v3 görsel önizleme (gündüz + gece). Yalnızca ADALMON_PREVIEW_DIR (TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class OfficeV3PreviewTests: XCTestCase {
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

    private func png(_ scene: OfficeScene, _ view: SKView, name: String, dir: URL) throws {
        let tex = try XCTUnwrap(view.texture(from: scene))
        let rep = NSBitmapImageRep(cgImage: tex.cgImage())
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appending(path: "\(name).png"))
        print("ONIZLEME \(name) \(tex.cgImage().width)x\(tex.cgImage().height) odalar=\(scene.roomCount) zoom=\(scene.zoom) dugum=\(scene.nodeCount)")
    }

    private func still(_ sessions: [AgentSession], night: Bool, size: CGSize, name: String, dir: URL, select: Int? = nil) throws {
        let assets = try XCTUnwrap(OfficeAssets.shared)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let scene = OfficeScene(assets: assets, size: size)
        view.presentScene(scene)
        scene.setLightingMode(night ? .night : .day, animated: false)
        scene.apply(members: OfficeMember.members(from: sessions), animated: false)
        if let select, select < scene.roomIDs.count { scene.select(scene.roomIDs[select], animated: false) }
        try png(scene, view, name: name + (night ? "-night" : "-day"), dir: dir)
        scene.shutdown()
    }

    func testRenderV3() throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else { throw XCTSkip("ADALMON_PREVIEW_DIR yok") }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let few = [session("a", subs: ["scanner", "implementer-hard", "reviewer"])]
        let eight = [session("b", subs: ["scanner", "deep-reader", "implementer", "implementer-hard", "reviewer", "ui-tester", "Explore", "Plan"])]
        let crowdTypes = ["scanner", "deep-reader", "implementer", "implementer-hard", "reviewer", "ui-tester", "ui-smoke", "Explore", "Plan", "general-purpose"]
        let crowd = (0..<10).map { i in session("c\(i)", subs: (0..<10).map { crowdTypes[($0 + i) % crowdTypes.count] }, status: i % 2 == 0 ? .thinking : .idle) }
        for night in [false, true] {
            try still(few, night: night, size: CGSize(width: 1000, height: 640), name: "1session-3subs", dir: dir)
            try still(few, night: night, size: CGSize(width: 1600, height: 1000), name: "1session-3subs-close", dir: dir, select: 0)
            try still(eight, night: night, size: CGSize(width: 1000, height: 700), name: "1session-8subs", dir: dir)
            try still(eight, night: night, size: CGSize(width: 1800, height: 1200), name: "computers-closeup", dir: dir, select: 0)
            try still(crowd, night: night, size: CGSize(width: 1500, height: 900), name: "10x10", dir: dir)
        }
        // Temizlikçi + taşıyıcı bir karede: A odasında temizlikçi yürür, B odası büyür (taşıyıcı masa getirir).
        let assets = try XCTUnwrap(OfficeAssets.shared)
        let size = CGSize(width: 1200, height: 700)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        window.contentView = view
        let scene = OfficeScene(assets: assets, size: size)
        view.presentScene(scene)
        view.preferredFramesPerSecond = 12
        scene.setLightingMode(.day, animated: false)
        let a = session("A", subs: ["scanner", "reviewer", "implementer"], status: .idle)
        let b4 = session("B", subs: ["Explore", "Plan", "deep-reader", "ui-tester"], status: .tool("Edit"))
        scene.apply(members: OfficeMember.members(from: [b4, a]), animated: false)
        let b5 = session("B", subs: ["Explore", "Plan", "deep-reader", "ui-tester", "implementer-hard"], status: .tool("Edit"))
        scene.apply(members: OfficeMember.members(from: [b5, a]), animated: true)
        XCTAssertTrue(scene.room("A")?.startCleaner(now: Date()) ?? false)
        let until = Date().addingTimeInterval(3.2)
        while Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        try png(scene, view, name: "cleaner-and-carrier", dir: dir)
        scene.shutdown()
        withExtendedLifetime(window) {}
    }
}
