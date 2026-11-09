import AppKit
import Observation
import SpriteKit
import SwiftUI
import XCTest
@testable import Adalmon

@MainActor @Observable
private final class MembersBox {
    var members: [OfficeMember]
    init(_ members: [OfficeMember]) { self.members = members }
}

private struct ArrivalHarness: View {
    let box: MembersBox
    var pano = false
    @State private var selected: String?
    var body: some View { OfficeSceneContainer(members: box.members, selectedRoom: $selected, panoActive: pano) }
}

/// Gerçek SwiftUI → SKView köprüsüyle: oturum açıkken yeni ajan gelince sahnede belirir, hareket eder (görünüm duraklı kalmaz) ve oturur.
@MainActor
final class OfficeLiveArrivalTests: XCTestCase {
    private func skView(in view: NSView) -> SKView? {
        if let s = view as? SKView { return s }
        for sub in view.subviews { if let s = skView(in: sub) { return s } }
        return nil
    }

    private func session() -> OfficeMember {
        OfficeMember(id: "s1", parentID: nil, kind: .session, label: "oturum", badge: .sonnet, status: .tool("Bash"), groupIndex: 0, activityAt: .now)
    }

    private func sub(_ n: Int) -> OfficeMember {
        OfficeMember(id: "s1#\(n)", parentID: "s1", kind: .subagent, label: "scanner", badge: .haiku, status: .tool("Bash"), groupIndex: 0, activityAt: .now)
    }

    func testNewSubagentArrivesAnimatesAndSitsInTheLiveBridge() async throws { try await arrival(pano: false, size: CGSize(width: 1000, height: 700)) }

    /// Tam ekran pano düzeni (büyük görünüm, temalı arka plan, ölçekli arayüz) altında da aynı garanti.
    func testNewSubagentArrivesInPanoFullScreenLayout() async throws { try await arrival(pano: true, size: CGSize(width: 2400, height: 1500)) }

    private func arrival(pano: Bool, size: CGSize) async throws {
        let box = MembersBox([session()])
        let host = NSHostingView(rootView: ArrivalHarness(box: box, pano: pano).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        try await Task.sleep(for: .seconds(1.5))
        let view = try XCTUnwrap(skView(in: host), "SKView bulunamadı")
        let scene = try XCTUnwrap(view.scene as? OfficeScene)
        XCTAssertEqual(scene.memberIDs, ["s1"])

        box.members = [session(), sub(1)]
        try await Task.sleep(for: .seconds(0.4))
        XCTAssertEqual(scene.memberIDs, ["s1", "s1#1"], "yeni ajan sahneye eklenmeli")
        XCTAssertFalse(view.isPaused, "yeni ajan yürürken görünüm duraklı kalmamalı")
        XCTAssertTrue(scene.isAnimating, "ajan giriş animasyonu çalışıyor olmalı")

        // İkinci ajan da gelsin (art arda).
        box.members = [session(), sub(1), sub(2)]
        try await Task.sleep(for: .seconds(0.4))
        XCTAssertEqual(scene.memberIDs, ["s1", "s1#1", "s1#2"])

        // Gerçek zamanda koltuklarına oturmaları.
        var settled = false
        for _ in 0..<80 {
            try await Task.sleep(for: .milliseconds(250))
            if let room = scene.room("s1"), room.actorCount == 3,
               room.actors.values.allSatisfy({ !$0.moving && !$0.away && !$0.leaving }) { settled = true; break }
        }
        XCTAssertTrue(settled, "ajanlar 20 sn içinde yürüyüp oturmalı")
        scene.shutdown()
    }

    // MARK: Uçtan uca: olay → AgentMonitorModel → OfficeWindowRoot → sahne

    private func event(_ name: String, session: String = "live-1", agent: String? = nil, type: String? = nil, tool: String? = nil) -> AgentEvent {
        AgentEvent(event: name, sessionID: session, agentID: agent, agentType: type, toolName: tool, project: "adalmon")
    }

    func testHookEventsReachTheOfficeWindowScene() async throws {
        let model = AppModel()
        let state = OfficeWindowState(settings: OfficeWindowSettings())
        let host = NSHostingView(rootView: OfficeWindowRoot(model: model, state: state).frame(width: 1200, height: 800))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close(); model.agents.monitor.reset() }
        try await Task.sleep(for: .seconds(1.5))
        let view = try XCTUnwrap(skView(in: host))
        let scene = try XCTUnwrap(view.scene as? OfficeScene)
        let monitor = model.agents.monitor

        monitor.ingest(event("SessionStart"))
        monitor.ingest(event("UserPromptSubmit"))
        try await Task.sleep(for: .seconds(0.6))
        XCTAssertEqual(scene.memberIDs, ["live-1"], "yeni oturum odaya gelmeli")

        monitor.ingest(event("SubagentStart", agent: "a1", type: "scanner"))
        try await Task.sleep(for: .seconds(0.6))
        XCTAssertEqual(scene.memberIDs, ["live-1", "live-1#a1"], "yeni alt ajan odaya gelmeli")
        XCTAssertFalse(view.isPaused, "yürüyen ajan varken görünüm duraklı olmamalı")

        monitor.ingest(event("SubagentStart", agent: "a2", type: "Explore"))
        monitor.ingest(event("PreToolUse", agent: "a2", type: "Explore", tool: "Bash"))
        try await Task.sleep(for: .seconds(0.6))
        XCTAssertEqual(scene.memberIDs, ["live-1", "live-1#a1", "live-1#a2"])

        monitor.ingest(event("SubagentStop", agent: "a1", type: "scanner"))
        try await Task.sleep(for: .seconds(0.6))
        XCTAssertFalse(scene.memberIDs.contains("live-1#a1"), "işi biten alt ajan odadan çıkar")

        // İkinci bir oturum (başka oda) de gelsin.
        monitor.ingest(event("SessionStart", session: "live-2"))
        monitor.ingest(event("UserPromptSubmit", session: "live-2"))
        try await Task.sleep(for: .seconds(0.8))
        XCTAssertTrue(scene.memberIDs.contains("live-2"), "ikinci oturum yeni oda olarak gelmeli")
        scene.shutdown()
    }
}

/// Tam ekran pano arayüzü önizlemesi (ADALMON_PREVIEW_DIR verilirse): şerit, ortalı saat, özet, sol kenarda uykuda çentiği.
@MainActor
final class OfficePanoOverlayPreviewTests: XCTestCase {
    func testRenderFullScreenOverlay() async throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else { throw XCTSkip("ADALMON_PREVIEW_DIR yok") }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel()
        var settings = OfficeWindowSettings()
        settings.panoMode = .always
        settings.showsClockSummary = true
        let state = OfficeWindowState(settings: settings)
        state.isFullScreen = true
        state.stripVisible = true
        let monitor = model.agents.monitor
        func ev(_ name: String, _ session: String, title: String? = nil) -> AgentEvent {
            AgentEvent(event: name, sessionID: session, project: "adalmon", sessionTitle: title)
        }
        for id in ["a", "b", "c"] { monitor.ingest(ev("SessionStart", id, title: "Oturum \(id.uppercased())")); monitor.ingest(ev("UserPromptSubmit", id)) }
        monitor.minimize("c")
        let size = CGSize(width: 1800, height: 1100)
        let host = NSHostingView(rootView: OfficeWindowRoot(model: model, state: state).frame(width: size.width, height: size.height).background(Color.black))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close(); monitor.reset() }
        try await Task.sleep(for: .seconds(2.5))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appending(path: "pano-overlay.png"))
    }
}
