import SpriteKit
import XCTest
@testable import Adalmon

/// Ofis kedisi: saf beyin (enjekte RNG/saat), masa erişilebilirliği, kapalıyken oluşturulmaz, uyurken eylem/güncelleme yok, tıklama, yerleşim.
@MainActor
final class OfficeCatTests: XCTestCase {
    private func assets() throws -> OfficeAssets { try XCTUnwrap(OfficeAssets.shared) }

    private func members(_ status: AgentStatus = .idle, subs: Int = 3) -> [OfficeMember] {
        var out = [OfficeMember(id: "s", parentID: nil, kind: .session, label: "oturum", badge: .opus, status: status, groupIndex: 0)]
        for i in 0..<subs { out.append(OfficeMember(id: "s#\(i)", parentID: "s", kind: .subagent, label: "implementer", badge: .sonnet, status: status, groupIndex: 0)) }
        return out
    }

    private func world(_ tier: OfficeRoomTier) throws -> OfficeCatWorld {
        let a = try assets(), kit = a.kit(tier)
        return OfficeCatWorld.make(grid: kit.grid, entrance: kit.spots.entrance, furniture: kit.layout.furniture, catalog: a.catalog)
    }

    // MARK: Dünya / erişilebilirlik

    func testPerchesOnlyReachable() throws {
        for tier in OfficeRoomTier.allCases {
            let w = try world(tier)
            let reach = w.grid.reachable(from: w.entrance)
            XCTAssertFalse(w.perches.isEmpty, "\(tier): en az bir masa")
            for p in w.perches {
                XCTAssertFalse(p.approaches.isEmpty)
                XCTAssertTrue(p.approaches.allSatisfy { reach.contains($0) && w.grid.isWalkable($0) }, "\(tier) masa \(p.id): yaklaşma karoları ulaşılabilir")
                XCTAssertNotNil(w.approach(to: p, from: w.entrance))
            }
            XCTAssertTrue(w.floor.allSatisfy { reach.contains($0) })
        }
    }

    func testUnreachableDeskIsNotAPerch() throws {
        // Masayı tamamen çevreleyen duvarlı sentetik ızgara: giriş izole → masa erişilemez.
        let cols = 9, rows = 5
        var walk = [Bool](repeating: false, count: cols * rows)
        for c in 0..<3 { walk[2 * cols + c] = true }          // giriş koridoru (soldan)
        for c in 5..<9 { walk[2 * cols + c] = true }          // masa çevresi (ayrı ada)
        let grid = OfficeGrid(cols: cols, rows: rows, walkable: walk)
        let a = try assets()
        let desk = [OfficeFurniturePlacement(type: "DESK_FRONT", col: 6, row: 1)]
        let w = OfficeCatWorld.make(grid: grid, entrance: OfficeTile(0, 2), furniture: desk, catalog: a.catalog)
        XCTAssertTrue(w.perches.isEmpty)
        var open = walk
        open[2 * cols + 3] = true; open[2 * cols + 4] = true     // köprü
        let w2 = OfficeCatWorld.make(grid: OfficeGrid(cols: cols, rows: rows, walkable: open), entrance: OfficeTile(0, 2), furniture: desk, catalog: a.catalog)
        XCTAssertEqual(w2.perches.count, 1)
    }

    // MARK: Beyin

    func testWeightedPickDeterministic() {
        let items: [(String, Double)] = [("a", 1), ("b", 3), ("c", 0), ("d", 1)]
        XCTAssertEqual(OfficeCatBrain.weightedPick(items, roll: 0.0), "a")
        XCTAssertEqual(OfficeCatBrain.weightedPick(items, roll: 0.19), "a")
        XCTAssertEqual(OfficeCatBrain.weightedPick(items, roll: 0.21), "b")
        XCTAssertEqual(OfficeCatBrain.weightedPick(items, roll: 0.79), "b")
        XCTAssertEqual(OfficeCatBrain.weightedPick(items, roll: 0.81), "d")
        XCTAssertNil(OfficeCatBrain.weightedPick([("x", 0)], roll: 0.5))
    }

    func testPlansAreValidAndConsistent() throws {
        for tier in [OfficeRoomTier.s2, .s6, .s16] {
            let w = try world(tier)
            for seed in 0..<400 as Range<UInt64> {
                let rng = OfficeCatRandom.seeded(seed)
                var spot: OfficeCatSpot = seed % 3 == 0 ? .perch(w.perches[Int(seed) % w.perches.count].id) : .floor(w.floor[Int(seed) % w.floor.count])
                let ctx = OfficeCatContext(world: w, spot: spot, workingSeats: seed % 2 == 0 ? [w.floor[0]] : [], cleaning: seed % 7 == 0, isNight: seed % 5 == 0,
                                           otherRooms: seed % 4 == 0 ? ["r2"] : [], awakeFor: Double(seed) * 3, sinceZoomies: seed % 2 == 0 ? .infinity : 10)
                let plan = OfficeCatBrain.plan(ctx, rng: rng)
                XCTAssertFalse(plan.steps.isEmpty)
                // Yer tutarlılığı: zeminde yürür, masadayken yalnızca iner; bitiş = plan.end.
                let end = try XCTUnwrap(OfficeCatBrain.endSpot(of: plan.steps, from: spot, world: w), "\(plan.activity) seed \(seed)")
                if plan.activity != .travel { XCTAssertEqual(end, plan.end, "\(plan.activity)") }
                for s in plan.steps {
                    switch s.kind {
                    case .walk(let t, _): XCTAssertTrue(w.floor.contains(t), "yürüme hedefi ulaşılabilir zemin")
                    case .jumpUp(let id): XCTAssertNotNil(w.perch(id))
                    case .jumpDown(let t): XCTAssertTrue(w.grid.isWalkable(t))
                    default: break
                    }
                }
                if ctx.cleaning { XCTAssertEqual(plan.activity, .flee) }
                if case .perch = spot { XCTAssertNotEqual(plan.activity, .zoomies); XCTAssertNotEqual(plan.activity, .wander) }
                spot = end
            }
        }
    }

    func testOnlyReachablePerchesAreClimbed() throws {
        let w = try world(.s4)
        for seed in 0..<300 as Range<UInt64> {
            let ctx = OfficeCatContext(world: w, spot: .floor(w.entrance))
            guard let plan = OfficeCatBrain.build(.climb, ctx, rng: .seeded(seed)) else { continue }
            for s in plan.steps { if case .jumpUp(let id) = s.kind { XCTAssertNotNil(w.perch(id)) } }
            if case .walk(let t, _)? = plan.steps.first?.kind { XCTAssertTrue(w.perches.contains { $0.approaches.contains(t) }) }
        }
    }

    func testZoomiesGatedAndFleeFromVacuum() throws {
        let w = try world(.s6)
        var c = OfficeCatContext(world: w, spot: .floor(w.entrance), isNight: false, sinceZoomies: 10)
        XCTAssertEqual(OfficeCatBrain.weights(c).first { $0.0 == .zoomies }?.1, 0, "4 dk dolmadan zoomies yok")
        c.sinceZoomies = OfficeCatBrain.zoomiesGap
        XCTAssertGreaterThan(OfficeCatBrain.weights(c).first { $0.0 == .zoomies }?.1 ?? 0, 0)
        c.isNight = true
        XCTAssertEqual(OfficeCatBrain.weights(c).first { $0.0 == .zoomies }?.1, 0, "geceleri koşmaz")
        c.isNight = false; c.cleaning = true
        XCTAssertEqual(OfficeCatBrain.weights(c).map(\.0), [.flee])
        let plan = OfficeCatBrain.plan(c, rng: .seeded(1))
        XCTAssertEqual(plan.activity, .flee)
        XCTAssertTrue(plan.steps.contains { if case .pose(.alert, _, _) = $0.kind { true } else { false } })
    }

    func testVisitAgentNeedsWorkingSeat() throws {
        let w = try world(.s4)
        var c = OfficeCatContext(world: w, spot: .floor(w.entrance))
        XCTAssertEqual(OfficeCatBrain.weights(c).first { $0.0 == .visitAgent }?.1, 0)
        c.workingSeats = [w.floor[w.floor.count / 2]]
        XCTAssertGreaterThan(OfficeCatBrain.weights(c).first { $0.0 == .visitAgent }?.1 ?? 0, 0)
        let plan = try XCTUnwrap(OfficeCatBrain.build(.visitAgent, c, rng: .seeded(3)))
        if case .walk(let t, _) = plan.steps[0].kind { XCTAssertLessThanOrEqual(t.manhattan(to: c.workingSeats[0]), 2) }
    }

    func testNapIsLongSleepThenWakeSequence() throws {
        let w = try world(.s4)
        let plan = try XCTUnwrap(OfficeCatBrain.build(.nap, OfficeCatContext(world: w, spot: .floor(w.entrance)), rng: .seeded(2)))
        let poses = plan.steps.compactMap { s -> OfficeCatPose? in if case .pose(let p, _, _) = s.kind { p } else { nil } }
        XCTAssertEqual(Array(poses.prefix(5)), [.yawn, .sleep, .stretch, .yawn, .sit])
        if case .pose(.sleep, let d, let animated) = plan.steps[1].kind { XCTAssertGreaterThanOrEqual(d, 90); XCTAssertFalse(animated, "uyku sabit poz (eylem yok)") } else { XCTFail() }
    }

    /// Simüle 2 saat: kedinin "animasyonlu" (eylem çalıştıran) süre payı. Sabit pozlar/uyku sayılmaz.
    func testAnimatedTimeShareIsLow() throws {
        let w = try world(.s6)
        let rng = OfficeCatRandom.seeded(42)
        var spot: OfficeCatSpot = .floor(w.entrance)
        var animated = 0.0, total = 0.0
        var sinceZoom = 1000.0, sleepTime = 0.0
        while total < 7200 {
            let ctx = OfficeCatContext(world: w, spot: spot, awakeFor: 100, sinceZoomies: sinceZoom)
            let plan = OfficeCatBrain.plan(ctx, rng: rng)
            if plan.activity == .zoomies { sinceZoom = 0 }
            for s in plan.steps {
                switch s.kind {
                case .pose(let p, let d, let anim):
                    // Sabit poz: zamanlayıcı vuruşuna (12 sn) yuvarlanır.
                    let span = anim ? d : max(d, 12)
                    total += span; if anim { animated += d }; if p == .sleep { sleepTime += span }
                case .walk(let t, let fast):
                    if case .floor(let here) = spot, let r = w.grid.path(from: here, to: t) { let d = Double(r.count) * (fast ? 0.14 : 0.32); animated += d; total += d }
                    spot = .floor(t)
                case .jumpUp(let id): animated += 0.75; total += 0.75; spot = .perch(id)
                case .jumpDown(let t): animated += 0.55; total += 0.55; spot = .floor(t)
                case .travel: animated += 1; total += 1
                }
            }
            sinceZoom += 1
            spot = OfficeCatBrain.endSpot(of: plan.steps, from: spot, world: w) ?? spot
        }
        let share = animated / total
        print("OFFICE-CAT-SIM animatedShare=\(String(format: "%.3f", share)) sleepShare=\(String(format: "%.3f", sleepTime / total)) over \(Int(total)) s")
        XCTAssertLessThan(share, 0.25, "eylem çalıştıran süre payı düşük olmalı")
    }

    // MARK: Sahne: kapalı / açık

    func testDisabledByDefaultAndNothingCreated() throws {
        let scene = OfficeScene(assets: try assets(), size: CGSize(width: 1000, height: 640), theme: .vector)
        scene.apply(members: members(), animated: false)
        XCTAssertNil(scene.cat, "varsayılan: kedi yok")
        let before = scene.nodeCount
        scene.setCat(enabled: false)
        XCTAssertNil(scene.cat)
        XCTAssertEqual(scene.nodeCount, before)
        XCTAssertFalse(scene.wanderTick(now: .now.addingTimeInterval(100), roll: 0.99) && scene.cat != nil)
        scene.setCat(enabled: true, rng: .seeded(1))
        XCTAssertNotNil(scene.cat)
        XCTAssertGreaterThan(scene.nodeCount, before)
        scene.setCat(enabled: false)
        XCTAssertNil(scene.cat)
        XCTAssertEqual(scene.nodeCount, before, "kapatınca düğüm kalmaz")
    }

    func testPrefDefaultsOn() {
        let d = UserDefaults(suiteName: "officeCatTests-\(UUID().uuidString)")!
        XCTAssertTrue(OfficeCat.storedEnabled(d))
        OfficeCat.store(false, defaults: d)
        XCTAssertFalse(OfficeCat.storedEnabled(d))
        XCTAssertFalse(Preferences(defaults: d).officeCatEnabled)
    }

    func testSleepingCatRequestsNoUpdates() throws {
        let scene = OfficeScene(assets: try assets(), size: CGSize(width: 1000, height: 640), theme: .vector)
        scene.apply(members: members(.idle, subs: 1), animated: false)
        scene.setCat(enabled: true, rng: .seeded(5))
        let cat = try XCTUnwrap(scene.cat)
        let now = Date()
        cat.clock = { now }
        let w = try XCTUnwrap(cat.room).catWorld
        let plan = OfficeCatPlan(activity: .nap, steps: [.pose(.sleep, 120), .pose(.sit, 5)], end: cat.spot)
        _ = w
        cat.startPlan(plan, now: now)
        XCTAssertEqual(cat.pose, .sleep)
        XCTAssertFalse(cat.isAnimating)
        XCTAssertFalse(cat.hasActions, "uyurken hiçbir SKAction yok")
        XCTAssertFalse(cat.tick(now: now.addingTimeInterval(30)), "uyku bitmeden vuruş iş yapmaz")
        XCTAssertEqual(cat.pose, .sleep)
        XCTAssertFalse(cat.hasActions)
        XCTAssertFalse(scene.isAnimating, "uyuyan kedi sahneyi animasyonlu saymaz (idle ajanlarla görünüm duraklayabilir)")
        XCTAssertTrue(cat.tick(now: now.addingTimeInterval(121)), "uyku bitince sonraki adım")
        XCTAssertEqual(cat.pose, .sit)
    }

    func testTickWalksAndTravelsFinishViaFastForward() throws {
        let scene = OfficeScene(assets: try assets(), size: CGSize(width: 1000, height: 640), theme: .vector)
        scene.apply(members: members(.idle, subs: 3), animated: false)
        scene.setCat(enabled: true, rng: .seeded(9))
        let cat = try XCTUnwrap(scene.cat)
        var now = Date()
        cat.clock = { now }
        let room = try XCTUnwrap(cat.room)
        let w = room.catWorld
        let perch = try XCTUnwrap(w.perches.first)
        let ap = try XCTUnwrap(w.approach(to: perch, from: w.entrance))
        cat.startPlan(OfficeCatPlan(activity: .climb, steps: [.walk(ap.tile), .up(perch.id), .pose(.loaf, 30)], end: .perch(perch.id)), now: now)
        XCTAssertTrue(cat.isAnimating)
        XCTAssertTrue(scene.isAnimating)
        var guardN = 0
        while cat.isAnimating, guardN < 10 { cat.fastForward(); guardN += 1 }
        XCTAssertEqual(cat.spot, .perch(perch.id))
        XCTAssertEqual(cat.pose, .loaf)
        let pp = room.perchPoint(perch)
        XCTAssertEqual(cat.root.position.x, pp.point.x, accuracy: 0.01)
        XCTAssertEqual(cat.root.position.y, pp.point.y, accuracy: 0.01)
        XCTAssertGreaterThan(cat.root.zPosition, room.tileZ(ap.tile), "masada: masanın önünde")
        now.addTimeInterval(31)
        XCTAssertTrue(cat.tick(now: now))
    }

    func testClickGreets() throws {
        let scene = OfficeScene(assets: try assets(), size: CGSize(width: 1000, height: 640), theme: .vector)
        scene.apply(members: members(.idle, subs: 1), animated: false)
        scene.setCat(enabled: true, rng: .seeded(11))
        let cat = try XCTUnwrap(scene.cat)
        let now = Date()
        XCTAssertTrue(cat.hit(local: CGPoint(x: cat.root.position.x, y: cat.root.position.y + 6)))
        XCTAssertFalse(cat.hit(local: CGPoint(x: cat.root.position.x + 60, y: cat.root.position.y)))
        XCTAssertTrue(cat.greet(now: now, zoom: 1))
        XCTAssertEqual(cat.pose, .happy)
        XCTAssertEqual(cat.holdUntil, now.addingTimeInterval(OfficeCatBrain.greetHold))
        XCTAssertTrue(cat.isAnimating, "kalp/miyav tepkisi sürerken")
    }

    func testCatRelocatesWhenRoomReplaced() throws {
        let scene = OfficeScene(assets: try assets(), size: CGSize(width: 1000, height: 640), theme: .vector)
        scene.apply(members: members(.idle, subs: 1), animated: false)
        scene.setCat(enabled: true, rng: .seeded(4))
        let cat = try XCTUnwrap(scene.cat)
        let first = cat.room
        scene.apply(members: members(.idle, subs: 8), animated: false)     // kademe büyür → oda yeniden kurulur
        XCTAssertNotNil(cat.room)
        XCTAssertTrue(cat.room === scene.room(try XCTUnwrap(cat.roomID)))
        XCTAssertFalse(cat.room === first)
        scene.setTheme(.pixel)
        XCTAssertNotNil(scene.cat, "tema değişince kedi yeniden kurulur")
        XCTAssertTrue(scene.cat?.room === scene.room(try XCTUnwrap(scene.cat?.roomID)))
    }
}
