import SpriteKit
import XCTest
@testable import Adalmon

/// Robot süpürge (vektör temada temizlikçinin yerine): görsel, hız ve oda davranışı.
@MainActor
final class OfficeRobotTests: XCTestCase {
    private func host(theme: OfficeTheme, _ size: CGSize = CGSize(width: 1000, height: 640)) throws -> (OfficeScene, NSWindow) {
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let scene = OfficeScene(assets: try XCTUnwrap(OfficeAssets.shared), size: size, theme: theme)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        view.presentScene(scene)
        return (scene, window)
    }

    private func members() -> [OfficeMember] {
        [OfficeMember(id: "a", parentID: nil, kind: .session, label: "a", badge: .sonnet, status: .idle, groupIndex: 0)]
    }

    func testRobotArtExistsAndIsExported() {
        XCTAssertTrue(OfficeVectorUI.overlayNames.contains("robot"))
        XCTAssertTrue(OfficeVectorUI.overlayNames.contains("robot_brush"))
        XCTAssertNotNil(OfficeVectorUI.overlay("robot"))
        XCTAssertNotNil(OfficeVectorUI.overlay("robot_brush"))
        XCTAssertEqual(OfficeVectorArt.artSize("robot"), CGSize(width: 15, height: 9))
        XCTAssertTrue(OfficeVectorArt.artNames.contains("robot"), "web'e de gider")
    }

    func testRobotGlidesWithoutSweepPausesAndFasterThanTheOldCleaner() {
        XCTAssertEqual(OfficeCleaner.robotStepDuration, 0.34)
        XCTAssertLessThan(OfficeCleaner.robotStepDuration, OfficeCleaner.stepDuration)
    }

    func testVectorThemeCleansWithRobot() throws {
        let (scene, window) = try host(theme: .vector)
        defer { scene.shutdown(); window.close() }
        scene.apply(members: members(), animated: false)
        let room = try XCTUnwrap(scene.room("a"))
        XCTAssertTrue(room.startCleaner(now: .now))
        XCTAssertTrue(room.cleanerIsRobot)
    }

    func testPixelThemeKeepsTheOldCleaner() throws {
        let (scene, window) = try host(theme: .pixel)
        defer { scene.shutdown(); window.close() }
        scene.apply(members: members(), animated: false)
        let room = try XCTUnwrap(scene.room("a"))
        XCTAssertTrue(room.startCleaner(now: .now))
        XCTAssertFalse(room.cleanerIsRobot)
    }

    func testWebContractDescribesTheRobot() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Resources/Office")
        let layout = try XCTUnwrap(OfficeWebLayout.build(officeRoot: root))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: layout.json) as? [String: Any])
        let v3 = try XCTUnwrap(obj["v3"] as? [String: Any])
        let cleaner = try XCTUnwrap(v3["cleaner"] as? [String: Any])
        let robot = try XCTUnwrap(cleaner["robot"] as? [String: Any])
        XCTAssertEqual(robot["body"] as? String, "robot")
        XCTAssertEqual(robot["brush"] as? String, "robot_brush")
        let gen = try XCTUnwrap((v3["vector"] as? [String: Any])?["generated"] as? [String: Any])
        XCTAssertNotNil(gen["robot"]); XCTAssertNotNil(gen["robot_brush"])
    }

    /// Önizleme (ADALMON_PREVIEW_DIR verilirse): vektör temada robot süpürge odada, gündüz ve gece.
    func testRenderRobotPreview() throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else { throw XCTSkip("ADALMON_PREVIEW_DIR yok") }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for night in [false, true] {
            let size = CGSize(width: 1000, height: 700)
            let view = SKView(frame: CGRect(origin: .zero, size: size))
            let scene = OfficeScene(assets: try XCTUnwrap(OfficeAssets.shared), size: size, theme: .vector)
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.presentScene(scene)
            scene.setLightingMode(night ? .night : .day, animated: false)
            scene.apply(members: members(), animated: false)
            scene.select("a", animated: false)
            XCTAssertTrue(scene.room("a")?.startCleaner(now: Date()) ?? false)
            let until = Date().addingTimeInterval(2.2)
            while Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
            let tex = try XCTUnwrap(view.texture(from: scene))
            let rep = NSBitmapImageRep(cgImage: tex.cgImage())
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appending(path: "robot-\(night ? "night" : "day").png"))
            scene.shutdown()
            withExtendedLifetime(window) {}
        }
    }
}
