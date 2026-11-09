import SpriteKit
import XCTest
@testable import Adalmon

/// Küçültme animasyonu (sola süzülme) ve oda üzerine gelme bildirimi.
@MainActor
final class OfficeTuckTests: XCTestCase {
    private func host(_ size: CGSize = CGSize(width: 1000, height: 640)) throws -> (OfficeScene, NSWindow) {
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let scene = OfficeScene(assets: try XCTUnwrap(OfficeAssets.shared), size: size, theme: .vector)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        view.presentScene(scene)
        scene.speed = 8
        return (scene, window)
    }

    @discardableResult
    private func pump(_ seconds: TimeInterval, until cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if cond() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        return cond()
    }

    private func members(_ ids: [String]) -> [OfficeMember] {
        ids.map { OfficeMember(id: $0, parentID: nil, kind: .session, label: $0, badge: .sonnet, status: .idle, groupIndex: 0) }
    }

    func testTuckCompletesThenRoomRemovalIsImmediate() throws {
        let (scene, window) = try host()
        defer { scene.shutdown(); window.close() }
        scene.apply(members: members(["a", "b"]), animated: false)
        XCTAssertEqual(scene.roomCount, 2)
        var boosted = 0.0
        scene.onCameraAnimation = { boosted = max(boosted, $0) }
        var done = false
        scene.tuck("a") { done = true }
        XCTAssertGreaterThan(boosted, 0.3, "animasyon sırasında kare hızı yükseltilir")
        XCTAssertTrue(pump(3) { done }, "animasyon biter ve completion çağrılır")
        // Üst katman küçültmeyi uygular: oda kararma beklemeden hemen kalkar.
        scene.apply(members: members(["b"]), animated: true)
        XCTAssertEqual(scene.roomCount, 1)
        XCTAssertEqual(scene.roomIDs, ["b"])
    }

    func testTuckWithoutRoomCompletesImmediately() throws {
        let (scene, window) = try host()
        defer { scene.shutdown(); window.close() }
        var done = false
        scene.tuck("yok") { done = true }
        XCTAssertTrue(done)
    }

    func testTuckedRoomReopensWhenMinimizeIsNotApplied() throws {
        let (scene, window) = try host()
        defer { scene.shutdown(); window.close() }
        scene.apply(members: members(["a", "b"]), animated: false)
        var done = false
        scene.tuck("a") { done = true }
        XCTAssertTrue(pump(3) { done })
        // Küçültme uygulanmadı (oturum çalışmaya başladı): bir saniyeden sonra gelen güncelleme odayı geri açar.
        scene.apply(members: members(["a", "b"]), animated: false, now: Date().addingTimeInterval(2))
        XCTAssertEqual(scene.roomCount, 2)
        XCTAssertEqual(scene.roomIDs.count, 2)
    }

    func testRoomHoverReportsAndClears() throws {
        let (scene, window) = try host()
        defer { scene.shutdown(); window.close() }
        scene.apply(members: members(["a"]), animated: false)
        var events: [OfficeRoomHover?] = []
        scene.onRoomHover = { events.append($0) }
        scene.hover(at: CGPoint(x: 500, y: 320))
        XCTAssertEqual(events.last??.id, "a")
        let rect = try XCTUnwrap(events.last??.rect)
        XCTAssertGreaterThan(rect.width, 50)
        scene.hover(at: nil)
        XCTAssertNil(events.last ?? nil)
        XCTAssertEqual(events.count, 2, "aynı oda üstünde tekrar bildirilmez")
    }
}

/// Küçültme uygulanmazsa (ör. oturum izin bekliyor) oda görünmez/küçük kalmamalı: sessiz sahnede de kendiliğinden geri açılır.
@MainActor
final class OfficeTuckRecoveryTests: XCTestCase {
    func testTuckedRoomReopensByItselfWhenMinimizeIsNotApplied() async throws {
        let size = CGSize(width: 1000, height: 640)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let scene = OfficeScene(assets: try XCTUnwrap(OfficeAssets.shared), size: size, theme: .vector)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        view.presentScene(scene)
        defer { scene.shutdown(); window.close() }
        let m = OfficeMember(id: "a", parentID: nil, kind: .session, label: "a", badge: .sonnet, status: .tool("Bash"), groupIndex: 0)
        scene.apply(members: [m], animated: false)
        var done = false
        scene.tuck("a") { done = true }                 // küçültme uygulanmayacak: sahneye yeni üye listesi GELMEZ
        for _ in 0..<40 where !done { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(done)
        XCTAssertLessThan(try XCTUnwrap(scene.room("a")).root.alpha, 0.1, "animasyon sonunda oda görünmez")
        // Üst katman küçültmeyi uygulamadı → sahne kendiliğinden geri açar.
        var reopened = false
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(100))
            let r = try XCTUnwrap(scene.room("a")).root
            if r.alpha > 0.95, abs(r.xScale - 1) < 0.01 { reopened = true; break }
        }
        XCTAssertTrue(reopened, "uygulanmayan küçültmede oda tekrar görünür olmalı")
    }
}
