import AppKit
import SpriteKit
import SwiftUI
import XCTest
@testable import Adalmon

final class OfficeRackLogicTests: XCTestCase {
    func testLEDMapping() {
        func leds(_ n: Int, known: Bool = true) -> [OfficeRackLED] { OfficeRackState.make(total: n, known: known).leds }
        XCTAssertEqual(leds(0), [.off, .off, .off, .off])
        XCTAssertEqual(leds(1), [.green, .off, .off, .off])
        XCTAssertEqual(leds(2), [.green, .green, .off, .off])
        XCTAssertEqual(leds(4), [.green, .green, .green, .green])
        XCTAssertEqual(leds(5), [.green, .green, .green, .orange], "N>4: son LED turuncu")
        XCTAssertEqual(leds(40), [.green, .green, .green, .orange])
        XCTAssertEqual(leds(3, known: false), [.off, .off, .off, .off], "pid yok: gri")
        XCTAssertEqual(OfficeRackState.make(total: 3, known: true).litCount, 3)
    }

    func testTooltips() {
        XCTAssertEqual(OfficeRackState.make(total: 3, known: true).tooltip, "Arka plan işlemleri: 3")
        XCTAssertEqual(OfficeRackState.make(total: 0, known: true).tooltip, "Arka plan işlemleri: 0")
        XCTAssertEqual(OfficeRackState.make(total: 3, known: false).tooltip, "İşlem bilgisi yok (eski oturum)")
    }

    func testRowFormatting() {
        XCTAssertEqual(SessionShellFormat.age(seconds: 45), "45 sn")
        XCTAssertEqual(SessionShellFormat.age(seconds: 120), "2 dk")
        XCTAssertEqual(SessionShellFormat.age(seconds: 3900), "1 sa 5 dk")
        XCTAssertEqual(SessionShellFormat.cpu(3.24), "%3,2")
        XCTAssertEqual(SessionShellFormat.cpu(42), "%42")
        XCTAssertEqual(SessionShellFormat.memory(150 * 1_048_576), "150 MB")
        XCTAssertEqual(SessionShellFormat.memory(2048 * 1_048_576), "2,0 GB")
        XCTAssertEqual(SessionShellFormat.title(total: 7), "Arka plan işlemleri (7)")
        XCTAssertNil(SessionShellFormat.more(0))
        XCTAssertEqual(SessionShellFormat.more(3), "+3 daha")
        let row = SessionShellRowModel(SessionShell(pid: 5, name: "xcodebuild", ageSeconds: 120, cpuPercent: 3, rssBytes: 100 * 1_048_576, hasChildren: true))
        XCTAssertEqual([row.name, row.age, row.cpu, row.ram], ["xcodebuild", "2 dk", "%3,0", "100 MB"])
    }

    func testCardCarriesShellsForSessionsOnly() {
        let shells = SessionShells(items: [SessionShell(pid: 1, name: "node", ageSeconds: 60, cpuPercent: 1, rssBytes: 0, hasChildren: false)], total: 15)
        let s = OfficeMember(id: "s", parentID: nil, kind: .session, label: "x", badge: .opus, status: .idle, groupIndex: 0, shells: shells, shellsKnown: true)
        let sub = OfficeMember(id: "s#a", parentID: "s", kind: .subagent, label: "scanner", badge: .opus, status: .idle, groupIndex: 0)
        let card = OfficeDetailCard.make(member: s, members: [s, sub], spawnedAt: nil)
        XCTAssertEqual(card.shells.total, 15)
        XCTAssertEqual(card.shells.hidden, 14)
        XCTAssertTrue(card.shellsKnown)
        XCTAssertEqual(OfficeDetailCard.make(member: sub, members: [s, sub], spawnedAt: nil).shells, .empty)
    }

    func testMembersFromSessionsCarryShellsAndPidKnowledge() {
        let shells = SessionShells(items: [], total: 2)
        var a = AgentSession(id: "a", project: "p", model: nil, status: .idle, startedAt: .now, lastEventAt: .now, pid: 10)
        a.shells = shells
        let b = AgentSession(id: "b", project: "p", model: nil, status: .idle, startedAt: .now, lastEventAt: .now)
        let m = OfficeMember.members(from: [a, b])
        XCTAssertEqual(m.first { $0.id == "a" }?.shells.total, 2)
        XCTAssertEqual(m.first { $0.id == "a" }?.shellsKnown, true)
        XCTAssertEqual(m.first { $0.id == "b" }?.shellsKnown, false)
    }

    @MainActor func testTemplatesPlaceBlockingRackInEveryTier() throws {
        let assets = try XCTUnwrap(OfficeAssets.shared)
        XCTAssertNotNil(assets.catalog["SERVER_RACK"])
        for tier in OfficeRoomTier.allCases {
            let kit = assets.kit(tier)
            let rack = try XCTUnwrap(kit.layout.furniture.first { $0.assetID == "SERVER_RACK" }, "\(tier)")
            let a = try XCTUnwrap(kit.layout.furniture.isEmpty ? nil : assets.catalog["SERVER_RACK"])
            XCTAssertEqual([a.footprintW, a.footprintH], [1, 2])
            for dr in 0..<2 { XCTAssertFalse(kit.grid.isWalkable(OfficeTile(rack.col, rack.row + dr)), "raf engel (\(tier))") }
            // Rafsız düzenle karşılaştır: raf yalnızca kendi 2 karosunu yürünmez yapar, başka hiçbir karo erişilemez olmaz.
            var bare = kit.layout
            bare.furniture.removeAll { $0.assetID == "SERVER_RACK" }
            let bareGrid = OfficeGrid(layout: bare, assets: assets.catalog)
            let door = kit.spots.door
            let with = kit.grid.reachable(from: door), without = bareGrid.reachable(from: door)
            let rackTiles: Set<OfficeTile> = [OfficeTile(rack.col, rack.row), OfficeTile(rack.col, rack.row + 1)]
            XCTAssertEqual(without.subtracting(with), rackTiles.intersection(without), "yalnızca raf karoları kaybolur (\(tier))")
            XCTAssertEqual(kit.spots.seats.count, OfficeSpots.derive(layout: bare, assets: assets.catalog, grid: bareGrid)?.seats.count, "koltuk sayısı (\(tier))")
        }
    }
}

@MainActor
final class OfficeRackSceneTests: XCTestCase {
    func testRoomShowsRackStateAndHitsOpenSessionCard() throws {
        let assets = try XCTUnwrap(OfficeAssets.shared)
        let size = CGSize(width: 1000, height: 640)
        let scene = OfficeScene(assets: assets, size: size)
        var s = AgentSession(id: "a", project: "adalmon", model: "claude-opus-4-8", status: .idle, startedAt: .now, lastEventAt: .now, pid: 42)
        s.shells = SessionShells(items: [], total: 5)
        scene.apply(members: OfficeMember.members(from: [s]), animated: false)
        let room = try XCTUnwrap(scene.room("a"))
        XCTAssertEqual(room.rackState.leds, [.green, .green, .green, .orange])
        XCTAssertEqual(room.rackOwnerID, "a")
        s.shells = .empty
        scene.apply(members: OfficeMember.members(from: [s]), animated: false)
        XCTAssertEqual(room.rackState.litCount, 0)
        s.pid = nil
        scene.apply(members: OfficeMember.members(from: [s]), animated: false)
        XCTAssertEqual(room.rackState.tooltip, "İşlem bilgisi yok (eski oturum)")
        // Rafın merkezi rafa isabet sayılır, yanındaki boşluk sayılmaz.
        let f = try XCTUnwrap(room.rackFrame)
        XCTAssertTrue(room.rackContains(CGPoint(x: f.midX, y: f.midY)))
        XCTAssertFalse(room.rackContains(CGPoint(x: f.maxX + 20, y: f.midY)))
        scene.shutdown()
    }
}

/// Raf eşyası ve rafı olan oda/kart görsel önizlemesi (yalnızca ADALMON_PREVIEW_DIR verilince).
@MainActor
final class OfficeRackPreviewTests: XCTestCase {
    private func write(_ rep: NSBitmapImageRep, _ url: URL) throws { try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url) }

    func testRenderRackPreviews() throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else { throw XCTSkip("ADALMON_PREVIEW_DIR yok") }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let assets = try XCTUnwrap(OfficeAssets.shared)
        let rackAsset = try XCTUnwrap(assets.catalog["SERVER_RACK"])
        // 1) Eşya: vektör gündüz/gece + piksel, N = 0 / 2 / 5 / pid yok.
        let states: [(String, OfficeRackState)] = [("N0", .make(total: 0, known: true)), ("N2", .make(total: 2, known: true)),
                                                    ("N5", .make(total: 5, known: true)), ("nopid", .make(total: 3, known: false))]
        let cell = CGSize(width: 160, height: 300)
        let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(cell.width) * states.count, pixelsHigh: Int(cell.height) * 3, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
        for (row, mode) in ["vector-day", "vector-night", "pixel"].enumerated() {
            let y = CGFloat(2 - row) * cell.height
            (mode == "vector-night" ? NSColor(red: 0.09, green: 0.1, blue: 0.16, alpha: 1) : NSColor(red: 0.91, green: 0.89, blue: 0.84, alpha: 1)).setFill()
            CGRect(x: 0, y: y, width: cell.width * CGFloat(states.count), height: cell.height).fill()
            for (i, (_, st)) in states.enumerated() {
                let pixel = mode == "pixel"
                let body: CGImage?
                if pixel {
                    body = NSImage(contentsOf: assets.root.appending(path: "furniture/\(rackAsset.file)"))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                } else { body = OfficeVectorArt.furniture(rackAsset) }
                let ctx = NSGraphicsContext.current!.cgContext
                ctx.interpolationQuality = pixel ? .none : .high
                let rect = CGRect(x: CGFloat(i) * cell.width + 20, y: y + 22, width: 120, height: 240)
                if let body { ctx.draw(body, in: rect) }
                if let leds = OfficeVectorArt.rackLEDs(st, pixel: pixel) { ctx.draw(leds, in: rect) }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try write(sheet, dir.appending(path: "rack-items.png"))
        // 2) Odalar: N = 0 / 2 / 5, gündüz + gece.
        for (name, n) in [("N0", 0), ("N2", 2), ("N5", 5)] {
            for night in [false, true] {
                var s = AgentSession(id: "a", project: "adalmon", model: "claude-opus-4-8", status: .tool("Bash"), startedAt: Date().addingTimeInterval(-600),
                                     lastEventAt: .now, subagents: [AgentSubagent(agentID: "1", agentType: "scanner", model: "claude-haiku-4-5", status: .thinking)],
                                     pid: 7)
                s.shells = SessionShells(items: [], total: n)
                let size = CGSize(width: 1400, height: 900)
                let view = SKView(frame: CGRect(origin: .zero, size: size))
                let scene = OfficeScene(assets: assets, size: size)
                view.presentScene(scene)
                scene.setLightingMode(night ? .night : .day, animated: false)
                scene.apply(members: OfficeMember.members(from: [s]), animated: false)
                scene.select(scene.roomIDs[0], animated: false)
                let tex = try XCTUnwrap(view.texture(from: scene))
                try write(NSBitmapImageRep(cgImage: tex.cgImage()), dir.appending(path: "room-\(name)-\(night ? "night" : "day").png"))
                scene.shutdown()
            }
        }
        // 3) Kart.
        let items = (0..<4).map { SessionShell(pid: Int32($0), name: ["xcodebuild", "log", "node", "sleep"][$0], ageSeconds: [180, 3700, 95, 40][$0], cpuPercent: [42, 0.4, 3.2, 0][$0], rssBytes: UInt64([820, 64, 210, 2][$0]) * 1_048_576, hasChildren: $0 == 0) }
        let card = OfficeDetailCard(memberID: "a", isSession: true, title: "adalmon", roleName: "ana ajan", badge: .opus, status: "Bash", tool: nil, startedAt: Date().addingTimeInterval(-600),
                                    parentTitle: nil, subagentCount: 1, children: [.init(role: "scanner", status: "düşünüyor")],
                                    shells: SessionShells(items: items, total: 15), shellsKnown: true)
        let renderer = ImageRenderer(content: OfficeCardView(card: card, close: {}).padding(16).background(Color(white: 0.16)).environment(\.colorScheme, .dark))
        renderer.scale = 2
        if let img = renderer.cgImage { try write(NSBitmapImageRep(cgImage: img), dir.appending(path: "card.png")) }
    }
}
