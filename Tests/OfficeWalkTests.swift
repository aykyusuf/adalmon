import SpriteKit
import XCTest
@testable import Adalmon

/// Yürüyüş/oturma/yönetici davranışı: gerçek SKAction'larla (pencereye bağlı SKView, run loop döndürülerek, sahne hızlandırılmış)
/// her üyenin sonunda koltuğunda oturduğunu, yöneticinin tahta/volta/masa durum makinesini ve volta rotasını doğrular.
@MainActor
final class OfficeWalkTests: XCTestCase {
    private func assets() throws -> OfficeAssets { try XCTUnwrap(OfficeAssets.shared) }

    /// Pencereye bağlı sahne (SKAction'lar yalnızca pencereli SKView'de çalışır); `speed` ile hızlandırılır.
    private func host(_ size: CGSize = CGSize(width: 1000, height: 640), speed: CGFloat = 8) throws -> (OfficeScene, NSWindow) {
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let scene = OfficeScene(assets: try assets(), size: size)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        view.presentScene(scene)
        scene.speed = speed
        return (scene, window)
    }

    /// Koşul gerçekleşene (ya da süre dolana) kadar run loop'u döndürür; koşul sağlandı mı döner.
    @discardableResult
    private func pump(_ seconds: TimeInterval, until cond: () -> Bool = { false }) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if cond() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        return cond()
    }

    private func sessions(subs: Int, lead: AgentStatus = .idle, sub: AgentStatus = .tool("Bash")) -> [AgentSession] {
        let now = Date()
        let list = (0..<subs).map { AgentSubagent(agentID: "a\($0)", agentType: "crew-chief", model: $0 % 2 == 0 ? "claude-sonnet-5-5" : "claude-haiku-4-5",
                                                  status: sub, activity: "Bash", activityAt: now) }
        return [AgentSession(id: "L", project: "p", model: "claude-sonnet-5-5", status: lead, startedAt: now, lastEventAt: now, subagents: list)]
    }

    private func settled(_ room: OfficeRoomNode?, count: Int) -> Bool {
        guard let room, room.actorCount == count else { return false }
        return room.actors.values.allSatisfy { !$0.moving && !$0.away && !$0.leaving }
    }

    /// Her üye koltuğunda, doğru konumda ve oturma pozunda (ayakta/yürüme karesinde takılı kalmamış).
    private func assertAllSeated(_ room: OfficeRoomNode, expectUpright exec: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        var seen: Set<Int> = []
        for a in room.actors.values {
            let who = a.member.id
            XCTAssertFalse(a.moving, "\(who) yürüyüşte takılı", file: file, line: line)
            XCTAssertFalse(a.away, "\(who) dışarıda", file: file, line: line)
            XCTAssertNil(a.heading, "\(who) yürüyüş hedefi açık", file: file, line: line)
            XCTAssertTrue(seen.insert(a.seat.id).inserted, "\(who): koltuk çift atanmış", file: file, line: line)
            if a.isExecutive && exec { continue }
            XCTAssertEqual(a.tile, a.seat.tile, "\(who) koltuğunda değil", file: file, line: line)
            XCTAssertEqual(a.root.position, room.point(a.seat.tile), "\(who) koltuk konumunda değil", file: file, line: line)
            XCTAssertEqual(a.body.position.y, -OfficeRoomNode.sitDrop, "\(who) oturma pozunda değil (ayakta)", file: file, line: line)
            XCTAssertEqual(a.direction, a.seat.facing, "\(who) koltuk yönüne dönmemiş", file: file, line: line)
        }
    }

    // MARK: Herkes oturur

    func testEveryMemberEndsSeatedAfterWalkingIn() throws {
        for subs in [0, 1, 2, 3, 4, 7, 8, 11, 12] {
            let (scene, window) = try host()
            _ = window
            let members = OfficeMember.members(from: sessions(subs: subs))
            scene.apply(members: members, animated: true)
            let shown = min(members.count, OfficeRoomTier.maxCharacters)
            let ok = pump(25) { settled(scene.room("L"), count: shown) }
            let room = try XCTUnwrap(scene.room("L"))
            XCTAssertTrue(ok, "\(subs) alt ajan: herkes yürüyüşü bitirmedi")
            XCTAssertEqual(room.tier, OfficeRoomTier.tier(forCount: members.count))
            XCTAssertEqual(room.overflow, max(0, members.count - OfficeRoomTier.maxCharacters), "yalnızca koltuk yoksa +N")
            assertAllSeated(room)
            XCTAssertFalse(room.actors.values.contains { $0.seat.kind == .executive && $0.member.kind != .session })
            XCTAssertEqual(room.actors["L"]?.seat.kind, .executive)
        }
    }

    func testTierGrowthWhileAgentsArrivePutsEveryoneBackInTheirSeats() throws {
        let (scene, window) = try host()
        _ = window
        for subs in 0...11 {
            let members = OfficeMember.members(from: sessions(subs: subs))
            scene.apply(members: members, animated: true)
            let room = try XCTUnwrap(scene.room("L"))
            XCTAssertEqual(room.tier, OfficeRoomTier.tier(forCount: members.count), "\(members.count) üye")
            // Kademe geçişi (4, 6, 8, 10 üye): oturanlar yerinde kalır (kaybolmaz); yeni ajan taşıyıcıdan sonra yürüyüp oturur.
            if [4, 6, 8, 10].contains(members.count) {
                XCTAssertGreaterThanOrEqual(room.actorCount, members.count - 1, "\(members.count) üye: kademe geçişinde oturanlar kaybolmaz")
            }
            XCTAssertTrue(pump(25) { settled(scene.room("L"), count: members.count) }, "\(members.count) üye yürüyüşü bitirmedi")
            assertAllSeated(try XCTUnwrap(scene.room("L")))
        }
    }

    /// Ekran görüntüsündeki durum: kapının yanındaki salon koltuğundaki alt ajan "ayakta" görünüyordu. Mantıkta takılma yok: koltuğunda,
    /// oturma çökmesiyle (sitDrop) ve okuma pozunda (PC yok); görünüm sorunu yan koltuğun arka plana pişip bacakları açıkta bırakmasıydı.
    // MARK: Yönetici durum makinesi

    func testExecutiveModeStateMachine() {
        let now = Date()
        let until = now.addingTimeInterval(OfficeExecutive.idleStrollDuration)
        XCTAssertEqual(OfficeExecutive.mode(status: .thinking, strollUntil: nil, now: now), .board)
        XCTAssertEqual(OfficeExecutive.mode(status: .tool("Bash"), strollUntil: until, now: now), .board, "çalışırken her zaman tahta")
        XCTAssertEqual(OfficeExecutive.mode(status: .waitingPermission, strollUntil: nil, now: now), .stroll)
        XCTAssertEqual(OfficeExecutive.mode(status: .idle, strollUntil: until, now: now), .stroll, "boşta ilk 60 sn volta")
        XCTAssertEqual(OfficeExecutive.mode(status: .done, strollUntil: until, now: until.addingTimeInterval(-1)), .stroll)
        XCTAssertEqual(OfficeExecutive.mode(status: .idle, strollUntil: until, now: until), .seated, "60 sn sonra masaya oturur ve durur")
        XCTAssertEqual(OfficeExecutive.mode(status: .idle, strollUntil: nil, now: now), .seated)
        XCTAssertEqual(OfficeExecutive.mode(status: .ended, strollUntil: until, now: now), .seated)
        // Volta bitiş anı: yalnızca çalışırken boşa geçişte (animasyonluysa) kurulur.
        XCTAssertEqual(OfficeExecutive.strollDeadline(previous: nil, old: .thinking, new: .idle, animated: true, now: now), until)
        XCTAssertEqual(OfficeExecutive.strollDeadline(previous: nil, old: .waitingPermission, new: .done, animated: true, now: now), until)
        XCTAssertNil(OfficeExecutive.strollDeadline(previous: until, old: .thinking, new: .idle, animated: false, now: now))
        XCTAssertNil(OfficeExecutive.strollDeadline(previous: until, old: .idle, new: .tool("x"), animated: true, now: now))
        XCTAssertEqual(OfficeExecutive.strollDeadline(previous: until, old: .idle, new: .done, animated: true, now: now.addingTimeInterval(30)), until, "boşta kalırken süre uzamaz")
    }

    func testStrollRouteStaysInsideZoneAndAvoidsObstacles() throws {
        let a = try assets()
        for tier in OfficeRoomTier.allCases {
            let kit = a.kit(tier)
            let zone = try XCTUnwrap(kit.spots.zone, "\(tier) yönetici bölgesi")
            let tiles = kit.spots.zoneTiles
            XCTAssertGreaterThanOrEqual(tiles.count, 12, "\(tier): voltaya yetecek bölge")
            XCTAssertTrue(tiles.allSatisfy { zone.contains($0) && kit.grid.isWalkable($0) }, "\(tier): bölge karoları yürünür")
            XCTAssertTrue(tiles.allSatisfy { t in !kit.spots.seats.contains { $0.tile == t } }, "\(tier): koltuk karosu volta karosu değil")
            XCTAssertTrue(zone.contains(try XCTUnwrap(kit.spots.board)), "\(tier): tahta önü bölgede")
            XCTAssertTrue(zone.contains(try XCTUnwrap(kit.spots.executiveSeat).tile), "\(tier): yönetici masası bölgede")
            XCTAssertTrue(kit.spots.deskSeats.allSatisfy { !zone.contains($0.tile) }, "\(tier): alt ajan masaları bölge dışında")
            XCTAssertTrue(kit.spots.loungeSeats.allSatisfy { !zone.contains($0.tile) }, "\(tier): salon koltukları bölge dışında")
            let zoneGrid = kit.grid.restricted(to: zone)
            let seed = OfficeStroll.seed(for: "L")
            var maxLength = 0
            for from in tiles {
                for step in 0..<12 {
                    let goal = try XCTUnwrap(OfficeStroll.target(from: from, zone: tiles, seed: seed, step: step), "\(tier) \(from): hedef")
                    XCTAssertTrue(tiles.contains(goal))
                    let route = try XCTUnwrap(zoneGrid.path(from: from, to: goal), "\(tier) \(from)→\(goal): bölge içinde yol yok")
                    XCTAssertTrue(route.allSatisfy { zone.contains($0) && kit.grid.isWalkable($0) }, "\(tier): rota bölgeden çıkmaz, engele girmez")
                    maxLength = max(maxLength, abs(goal.col - from.col))
                }
            }
            XCTAssertTrue(OfficeStroll.lengths.contains(maxLength), "\(tier): 4-6 karelik yürüyüş var (en uzun \(maxLength))")
            // Tahtadan başlayan volta 3-6 karelik yatay yürüyüş verir (küçük odada tahtanın bir yanı 3 karo).
            let board = try XCTUnwrap(kit.spots.board)
            let goal = try XCTUnwrap(OfficeStroll.target(from: board, zone: tiles, seed: seed, step: 0))
            XCTAssertTrue((3...6).contains(abs(goal.col - board.col)), "\(tier): \(board)→\(goal)")
        }
        // Deterministik ve süreler aralıkta.
        let seed = OfficeStroll.seed(for: "x")
        XCTAssertEqual(OfficeStroll.roll(seed: seed, 3), OfficeStroll.roll(seed: seed, 3))
        for n in 0..<50 {
            XCTAssertTrue((3.0...5.0).contains(OfficeStroll.writeInterval(seed: seed, n)))
            XCTAssertTrue((1.5...4.0).contains(OfficeStroll.pause(seed: seed, step: n)))
            XCTAssertTrue((1.0...1.8).contains(OfficeStroll.lookAwayDuration(seed: seed, n)))
        }
    }

    func testExecutiveWritesAtBoardAndLooksAtSubagentsThenTurnsBack() throws {
        let (scene, window) = try host()
        _ = window
        scene.apply(members: OfficeMember.members(from: sessions(subs: 2, lead: .tool("Edit"))), animated: false)
        let room = try XCTUnwrap(scene.room("L"))
        let exec = try XCTUnwrap(room.actors["L"])
        XCTAssertTrue(exec.atBoard)
        XCTAssertEqual(exec.direction, .up)
        XCTAssertTrue(room.isBoardWriting)
        var seen: Set<OfficeCharacterSheet.Direction> = []
        pump(8) { seen.insert(exec.direction); return seen.count == 2 }
        XCTAssertEqual(seen, [.up, .down], "tahtaya yazar, arada alt ajanlara bakar")
        XCTAssertTrue(pump(8) { exec.direction == .up }, "sonra tahtaya döner")
        XCTAssertTrue(exec.atBoard)
        XCTAssertEqual(exec.tile, room.kit.spots.board)
        XCTAssertTrue(room.isBoardWriting)
    }

    func testExecutiveStrollsInsideZoneWhenWaitingThenSitsAfterIdleWindow() throws {
        let (scene, window) = try host()
        _ = window
        let now = Date()
        scene.apply(members: OfficeMember.members(from: sessions(subs: 1, lead: .thinking)), animated: false, now: now)
        let room = try XCTUnwrap(scene.room("L"))
        let exec = try XCTUnwrap(room.actors["L"])
        let zone = try XCTUnwrap(room.kit.spots.zone)
        let zoneTiles = Set(room.kit.spots.zoneTiles)
        XCTAssertTrue(exec.atBoard)
        // İzin beklerken: tahtadan ayrılıp bölgede volta atar.
        scene.apply(members: OfficeMember.members(from: sessions(subs: 1, lead: .waitingPermission)), animated: true, now: now)
        var tiles: Set<OfficeTile> = []
        pump(10) {
            XCTAssertTrue(zone.contains(exec.heading ?? exec.tile), "volta bölgeden çıkmadı")
            tiles.insert(exec.tile)
            return tiles.count >= 6
        }
        XCTAssertGreaterThanOrEqual(tiles.count, 6, "gezindi")
        XCTAssertTrue(tiles.isSubset(of: zoneTiles), "yalnızca bölge karolarında")
        XCTAssertTrue(exec.strolling)
        XCTAssertFalse(exec.atBoard)
        XCTAssertTrue(scene.isAnimating, "volta animasyonlu sayılır")
        // Boşa geçti (animasyonlu): 60 sn volta penceresi; test için pencere ~1 sn kalmış gibi (now - 59).
        scene.apply(members: OfficeMember.members(from: sessions(subs: 1, lead: .idle, sub: .idle)), animated: true, now: Date().addingTimeInterval(-59))
        XCTAssertTrue(exec.strolling, "boşta ilk süre volta")
        XCTAssertTrue(pump(20) { settled(room, count: 2) && !exec.strolling }, "süre dolunca masasına yürür ve oturur")
        XCTAssertEqual(exec.tile, exec.seat.tile)
        XCTAssertEqual(exec.body.position.y, -OfficeRoomNode.sitDrop)
        XCTAssertNil(exec.body.action(forKey: "bubbleExpiry"))
        XCTAssertFalse(scene.isAnimating || room.isAnimating, "oturduktan sonra tüm sahne durağan (CPU)")
        // Tekrar çalışınca tahtaya gider.
        scene.apply(members: OfficeMember.members(from: sessions(subs: 1, lead: .tool("Bash"))), animated: true)
        XCTAssertTrue(pump(20) { exec.atBoard && !exec.moving })
        XCTAssertEqual(exec.tile, room.kit.spots.board)
    }

    func testIdleExecutiveIsSeatedStaticWhenNotAnimated() throws {
        let (scene, window) = try host()
        _ = window
        scene.apply(members: OfficeMember.members(from: sessions(subs: 0, lead: .thinking)), animated: false)
        scene.apply(members: OfficeMember.members(from: sessions(subs: 0, lead: .idle)), animated: false)
        let exec = try XCTUnwrap(scene.room("L")?.actors["L"])
        XCTAssertFalse(exec.strolling)
        XCTAssertEqual(exec.tile, exec.seat.tile)
        XCTAssertFalse(scene.isAnimating)
    }

    // MARK: Balonlar

    func testNeighbouringBubblesNeverOverlap() throws {
        let now = Date()
        for subs in [2, 3, 7] {
            let scene = OfficeScene(assets: try assets(), size: CGSize(width: 1000, height: 640))
            let list = (0..<subs).map { AgentSubagent(agentID: "a\($0)", agentType: "crew-chief", model: "claude-sonnet-5-5", status: .tool("Bash"), activity: "Bash", activityAt: now) }
            let s = [AgentSession(id: "L", project: "p", model: "claude-sonnet-5-5", status: .tool("Bash"), startedAt: now, lastEventAt: now, subagents: list, activity: "Bash", activityAt: now)]
            scene.apply(members: OfficeMember.members(from: s), animated: false, now: now)
            XCTAssertGreaterThanOrEqual(scene.zoom, 2)
            let room = try XCTUnwrap(scene.room("L"))
            let z = CGFloat(scene.zoom)
            let rects: [(String, CGRect)] = room.actors.values.compactMap { a in
                guard let tb = a.textBubble, !tb.node.isHidden else { return nil }
                let tail = OfficePixelArt.speechBubbleTailX / z, w = tb.width / z
                let x = a.root.position.x + (tb.flipped ? tail - w : -tail)
                return (a.member.id, CGRect(x: x, y: a.root.position.y + tb.node.position.y, width: w, height: OfficeTextBubble.height / z))
            }
            XCTAssertEqual(rects.count, subs + 1, "her çalışan karakterin balonu var (yönetici dahil)")
            for (i, a) in rects.enumerated() { for b in rects[(i + 1)...] {
                XCTAssertFalse(a.1.intersects(b.1), "balonlar çakışıyor: \(a.0) \(b.0)")
            } }
        }
    }
}
