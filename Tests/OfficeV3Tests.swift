import SpriteKit
import XCTest
@testable import Adalmon

/// Ofis v3: parametrik oda üreticisi, roller, gece/gündüz, bilgisayar türü, boşta/temizlikçi/taşıyıcı mantığı, detay kartı, JSON sözleşmesi.
@MainActor
final class OfficeV3Tests: XCTestCase {
    private func assets() throws -> OfficeAssets { try XCTUnwrap(OfficeAssets.shared, "ofis varlıkları yüklenemedi") }

    private func members(session: String = "s", subs: Int, status: AgentStatus = .tool("Bash")) -> [OfficeMember] {
        var out = [OfficeMember(id: session, parentID: nil, kind: .session, label: "oturum", badge: .opus, status: status, groupIndex: 0)]
        for i in 0..<subs {
            out.append(OfficeMember(id: "\(session)#\(i)", parentID: session, kind: .subagent, label: "implementer", badge: .sonnet, status: status, groupIndex: 0))
        }
        return out
    }

    // MARK: Parametrik oda üreticisi

    func testTierThresholdsAndStations() {
        XCTAssertEqual(OfficeRoomTier.allCases.map(\.stations), [2, 4, 6, 8, 12, 16])
        XCTAssertEqual(OfficeRoomTier.allCases.map(\.capacity), [3, 5, 7, 9, 13, 17])
        XCTAssertEqual(OfficeRoomTier.maxCharacters, 17)
        let expect: [(Int, OfficeRoomTier)] = [(0, .s2), (1, .s2), (3, .s2), (4, .s4), (5, .s4), (6, .s6), (7, .s6), (8, .s8), (9, .s8), (10, .s12), (13, .s12), (14, .s16), (17, .s16), (110, .s16)]
        for (n, t) in expect { XCTAssertEqual(OfficeRoomTier.tier(forCount: n), t, "\(n) üye") }
    }

    func testEveryStationCountEveryoneSitsAtDeskWithComputer() throws {
        let kits = try assets().kits
        for tier in OfficeRoomTier.allCases {
            let kit = try XCTUnwrap(kits[tier])
            XCTAssertEqual(kit.spots.deskSeats.count, tier.stations, "\(tier) masa koltuğu")
            XCTAssertEqual(kit.spots.executiveSeat?.id, 0)
            XCTAssertTrue(kit.spots.loungeSeats.isEmpty, "salon koltuğu yok (yalnızca dekor)")
            XCTAssertNotNil(kit.spots.coffee, "\(tier): her odada kahve makinesi")
            XCTAssertTrue(kit.spots.seats.allSatisfy { $0.pcIndex != nil }, "\(tier): her koltuğun karşısında bilgisayar")
            let reach = kit.grid.reachable(from: kit.spots.entrance)
            for s in kit.spots.seats {
                XCTAssertNotNil(kit.grid.path(from: kit.spots.entrance, to: s.tile), "\(tier) koltuk \(s.id) ulaşılabilir")
                XCTAssertFalse(reach.contains(s.tile), "koltuk karosu yürünür değil")
            }
            XCTAssertNotNil(kit.spots.board)
            XCTAssertGreaterThanOrEqual(kit.spots.zoneTiles.count, 2)
        }
    }

    func testPlannerSeatsEveryoneFor1To16AndOverflowsAbove() throws {
        let kits = try assets().kits
        for subs in 0...20 {
            var planner = OfficeRoomPlanner(seats: kits.mapValues { $0.spots.seats })
            let plan = planner.update(members: members(subs: subs))
            let room = try XCTUnwrap(plan.rooms.first)
            let shown = min(subs + 1, OfficeRoomTier.maxCharacters)
            XCTAssertEqual(room.placements.values.filter { if case .seat = $0 { true } else { false } }.count, shown, "\(subs) alt ajan")
            XCTAssertEqual(room.overflowCount, max(0, subs + 1 - OfficeRoomTier.maxCharacters))
            XCTAssertEqual(room.tier, OfficeRoomTier.tier(forCount: subs + 1))
            if subs <= 15 {
                let seatIDs = room.placements.values.compactMap { if case .seat(let s) = $0 { s } else { nil } }
                XCTAssertEqual(Set(seatIDs).count, seatIDs.count, "çift koltuk yok")
            }
        }
    }

    func testGrowthKeepsSeatedAgentsInPlaceAndShrinkHasHysteresis() throws {
        let kits = try assets().kits
        var planner = OfficeRoomPlanner(seats: kits.mapValues { $0.spots.seats })
        func tile(_ plan: OfficeRoomsPlan, _ id: String) -> OfficeTile? {
            guard case .seat(let s)? = plan.rooms.first?.placements[id], let tier = plan.rooms.first?.tier else { return nil }
            return kits[tier]?.spots.seats.first { $0.id == s }?.tile
        }
        let p5 = planner.update(members: members(subs: 4))
        XCTAssertEqual(p5.rooms[0].tier, .s4)
        let before = (0..<4).map { tile(p5, "s#\($0)") }
        let p6 = planner.update(members: members(subs: 5))   // 6 üye → s6 (büyüme)
        XCTAssertEqual(p6.rooms[0].tier, .s6)
        XCTAssertTrue(p6.rooms[0].reseated)
        XCTAssertEqual(p6.rooms[0].previousTier, .s4)
        XCTAssertEqual((0..<4).map { tile(p6, "s#\($0)") }, before, "oturanlar karo olarak yerinde kalır")
        XCTAssertFalse(p6.rooms[0].placements.values.contains(.overflow))
        let fresh = OfficeCarrier.newDeskSeats(old: kits[.s4]!.spots.seats, new: kits[.s6]!.spots.seats)
        XCTAssertEqual(fresh.count, 2, "s4 → s6: yalnızca yeni masa bloğu (2 istasyon)")
        // Küçülme histerezisi: 5 üye (s4 kapasitesi 5) iken s6'dan inmez; 4 üyeye inince iner.
        XCTAssertEqual(planner.update(members: members(subs: 4)).rooms[0].tier, .s6)
        XCTAssertEqual(planner.update(members: members(subs: 3)).rooms[0].tier, .s4)
    }

    func testShrinkOnlyBelowLowerTierCapacity() throws {
        let kits = try assets().kits
        var planner = OfficeRoomPlanner(seats: kits.mapValues { $0.spots.seats })
        _ = planner.update(members: members(subs: 7))   // 8 üye → s8
        XCTAssertEqual(planner.update(members: members(subs: 6)).rooms[0].tier, .s8, "7 üye: s6 kapasitesi 7, alt sınır 6 → kalır")
        XCTAssertEqual(planner.update(members: members(subs: 5)).rooms[0].tier, .s6, "6 üye → s6'ya iner (boş masalar kalkar)")
    }

    func testTemplateGeometry() {
        XCTAssertEqual(OfficeRoomTemplates.floorWidth(stations: 2), 8)
        XCTAssertEqual(OfficeRoomTemplates.floorWidth(stations: 16), 11)
        XCTAssertEqual(OfficeRoomTemplates.floorHeight(stations: 6), 10)
        XCTAssertEqual(OfficeRoomTemplates.floorHeight(stations: 16), 18)
        XCTAssertEqual(OfficeRoomTemplates.laneRows(stations: 2), [5, 11])
        for tier in OfficeRoomTier.allCases {
            let l = OfficeRoomTemplates.layout(tier, floor: nil, wall: nil)
            XCTAssertEqual(l.furniture.filter { $0.assetID == "DESK_FRONT" }.count, tier.stations / 2)
            XCTAssertEqual(l.furniture.filter { $0.assetID == "COFFEE" }.count, 1)
        }
    }

    // MARK: Roller

    func testRoleMappingKnownPrefixedAndUnknown() {
        XCTAssertEqual(OfficeRoles.style(forAgentType: "scanner").accessory, .binoculars)
        XCTAssertTrue(OfficeRoles.style(forAgentType: "scanner").small)
        XCTAssertEqual(OfficeRoles.style(forAgentType: "implementer-hard").accessory, .headphones)
        XCTAssertTrue(OfficeRoles.style(forAgentType: "implementer").hoodie)
        XCTAssertEqual(OfficeRoles.style(forAgentType: "Explore").key, "explore")
        XCTAssertEqual(OfficeRoles.style(forAgentType: "Explore").name, "Explore", "ad aynen kalır")
        XCTAssertEqual(OfficeRoles.style(forAgentType: "crew-chief:reviewer").key, "reviewer")
        XCTAssertEqual(OfficeRoles.style(forAgentType: "crew-chief:reviewer").name, "crew-chief:reviewer")
        XCTAssertEqual(OfficeRoles.style(forAgentType: "feature-dev:code-architect").accessory, .ruler)
        XCTAssertEqual(OfficeRoles.style(forAgentType: "feature-dev:code-reviewer").accessory, .glasses)
        XCTAssertEqual(OfficeRoles.style(forAgentType: "claude-code-guide").accessory, .book)
        XCTAssertEqual(OfficeRoles.style(forAgentType: "ui-smoke").small, true)
        XCTAssertEqual(OfficeRoles.knownKeys.count, 15)
        let u1 = OfficeRoles.style(forAgentType: "zeta-worker"), u2 = OfficeRoles.style(forAgentType: "zeta-worker"), u3 = OfficeRoles.style(forAgentType: "alpha-worker")
        XCTAssertFalse(u1.known)
        XCTAssertEqual(u1, u2, "hash tonu deterministik")
        XCTAssertNotEqual(u1.tintHex, u3.tintHex)
        XCTAssertEqual(u1.accessory, .tag)
        XCTAssertEqual(OfficeRoles.rgb(hex: "#FF0000"), OfficeRGB(r: 1, g: 0, b: 0))
        XCTAssertEqual(OfficeRoles.style(forAgentType: "reviewer").tintHex, "#E04848")
    }

    func testRoleDominatesSubagentLookButMainAgentKeepsModelAccessory() {
        let lead = OfficeMember(id: "a", parentID: nil, kind: .session, label: "x", badge: .opus, status: .idle, groupIndex: 0)
        XCTAssertEqual(OfficeAppearance.appearance(for: lead).accessory, .crown)
        XCTAssertNil(OfficeAppearance.appearance(for: lead).role)
        let sub = OfficeMember(id: "a#1", parentID: "a", kind: .subagent, label: "reviewer", badge: .haiku, status: .idle, groupIndex: 0)
        let look = OfficeAppearance.appearance(for: sub)
        XCTAssertEqual(look.accessory, .none)
        XCTAssertEqual(look.role?.key, "reviewer")
        XCTAssertEqual(look.tint, OfficeRoles.style(forAgentType: "reviewer").tint)
        XCTAssertEqual(look.modelDot, OfficeAppearance.appearance(for: .haiku).tint, "model rengi nokta olarak kalır")
        XCTAssertFalse(look.small, "reviewer küçük değil (haiku küçüklüğü rolle değişir)")
    }

    // MARK: Gece / gündüz

    func testNightRuleBoundariesOverrideAndTimeZone() {
        let utc = TimeZone(identifier: "UTC")!, ist = TimeZone(identifier: "Europe/Istanbul")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
        func d(_ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: h, minute: m))! }
        XCTAssertFalse(OfficeLighting.isNight(mode: .auto, date: d(12, 0), timeZone: utc))
        XCTAssertFalse(OfficeLighting.isNight(mode: .auto, date: d(19, 29), timeZone: utc))
        XCTAssertTrue(OfficeLighting.isNight(mode: .auto, date: d(19, 30), timeZone: utc))
        XCTAssertTrue(OfficeLighting.isNight(mode: .auto, date: d(23, 59), timeZone: utc))
        XCTAssertTrue(OfficeLighting.isNight(mode: .auto, date: d(0, 0), timeZone: utc))
        XCTAssertTrue(OfficeLighting.isNight(mode: .auto, date: d(6, 29), timeZone: utc))
        XCTAssertFalse(OfficeLighting.isNight(mode: .auto, date: d(6, 30), timeZone: utc))
        // Aynı an, farklı saat dilimi: 17:00 UTC = 20:00 İstanbul (UTC+3) → gece sadece İstanbul'da.
        XCTAssertFalse(OfficeLighting.isNight(mode: .auto, date: d(17, 0), timeZone: utc))
        XCTAssertTrue(OfficeLighting.isNight(mode: .auto, date: d(17, 0), timeZone: ist))
        XCTAssertFalse(OfficeLighting.isNight(mode: .day, date: d(23, 0), timeZone: utc))
        XCTAssertTrue(OfficeLighting.isNight(mode: .night, date: d(12, 0), timeZone: utc))
        let next = OfficeLighting.nextBoundary(after: d(12, 0), timeZone: utc)
        XCTAssertEqual(next, d(19, 30))
        XCTAssertEqual(OfficeLighting.nextBoundary(after: d(20, 0), timeZone: utc), cal.date(byAdding: .day, value: 1, to: d(6, 30)))
    }

    func testLightingModeStorage() {
        let defaults = UserDefaults(suiteName: "office-v3-tests-\(UUID().uuidString)")!
        XCTAssertEqual(OfficeLighting.storedMode(defaults), .auto)
        OfficeLighting.store(.night, defaults: defaults)
        XCTAssertEqual(OfficeLighting.storedMode(defaults), .night)
        defaults.set("bozuk", forKey: OfficeLighting.defaultsKey)
        XCTAssertEqual(OfficeLighting.storedMode(defaults), .auto)
        XCTAssertEqual(OfficeLighting.defaultsKey, "officeLightingMode")
    }

    func testSceneNightBuildsLightsOnlyWhenVisible() throws {
        let scene = OfficeScene(assets: try assets(), size: CGSize(width: 1000, height: 640))
        scene.setLightingMode(.night, animated: false)
        scene.apply(members: members(subs: 3), animated: false)
        XCTAssertTrue(scene.isNight)
        let room = try XCTUnwrap(scene.room("s"))
        XCTAssertTrue(room.nightWanted)
        let nodes = scene.nodeCount
        scene.setLightingMode(.day, animated: false)
        XCTAssertFalse(scene.isNight)
        XCTAssertEqual(scene.nodeCount, nodes, "ışık düğümleri korunur, yalnızca gizlenir")
        scene.shutdown()
    }

    // MARK: Bilgisayar türü

    func testComputerPickDeterministicAndMixed() {
        XCTAssertEqual(OfficeComputer.pick(roomID: "abc", seatID: 808), OfficeComputer.pick(roomID: "abc", seatID: 808))
        var kinds = Set<OfficeComputer.Kind>(), imacColors = Set<OfficeComputer.Color>()
        for room in 0..<5 { for seat in 0..<16 {
            let c = OfficeComputer.pick(roomID: "room\(room)", seatID: 800 + seat)
            kinds.insert(c.kind)
            if c.kind == .imac { imacColors.insert(c.color); XCTAssertTrue(OfficeComputer.imacColors.contains(c.color)) } else { XCTAssertTrue(OfficeComputer.macbookColors.contains(c.color)) }
        } }
        XCTAssertEqual(kinds, [.imac, .macbook], "karma dağılım iki türü de içerir")
        XCTAssertGreaterThanOrEqual(imacColors.count, 3, "iMac renk çeşitliliği")
        XCTAssertEqual(OfficeComputer.executive.kind, .imac)
    }

    func testComputerArtExistsForAllVariantsAndIsSizedLikeOldPC() throws {
        for c in OfficeArt.allComputers {
            for f in [nil, 0, 1, 2] as [Int?] {
                let img = try XCTUnwrap(OfficeArt.image(OfficeArt.computerName(c, frame: f)), "\(c.artName) \(String(describing: f))")
                XCTAssertEqual(img.width, 16); XCTAssertEqual(img.height, 32)
            }
        }
        XCTAssertNotNil(OfficeArt.dataURI("glow_bulb"))
        XCTAssertTrue(try XCTUnwrap(OfficeArt.dataURI("cup")).hasPrefix("data:image/png;base64,"))
        // Her masa bilgisayarı sahnede doğru dokuyla kurulur.
        let scene = OfficeScene(assets: try assets(), size: CGSize(width: 1000, height: 640))
        scene.apply(members: members(subs: 5), animated: false)
        let room = try XCTUnwrap(scene.room("s"))
        let pcs = room.kit.spots.seats.compactMap { $0.pcIndex }
        XCTAssertFalse(pcs.isEmpty)
        for pc in pcs { XCTAssertNotNil(room.computer(forPC: pc)) }
        XCTAssertEqual(room.computer(forPC: try XCTUnwrap(room.kit.spots.executiveSeat?.pcIndex)), OfficeComputer.executive)
    }

    // MARK: Boşta / temizlikçi / taşıyıcı

    func testIdleVariantDeterministicAndCoversAll() {
        XCTAssertEqual(OfficeIdle.variant(seed: "a", n: 3), OfficeIdle.variant(seed: "a", n: 3))
        let seen = Set((0..<80).map { OfficeIdle.variant(seed: "agent-\($0 % 7)", n: $0) })
        XCTAssertEqual(seen, Set(OfficeIdleVariant.allCases))
        for n in 0..<30 { XCTAssertTrue(OfficeIdle.duration.contains(OfficeIdle.length(seed: "x", n: n))); XCTAssertTrue(OfficeIdle.wanderStay.contains(OfficeIdle.stay(seed: "x", n: n))) }
        XCTAssertEqual(OfficeIdle.wanderChance, 0.3)
        XCTAssertEqual(OfficeIdle.wanderGap, 20...60)
        XCTAssertEqual(OfficeIdle.maxWanderers(memberCount: 3), 1)
        XCTAssertEqual(OfficeIdle.maxWanderers(memberCount: 12), 2)
    }

    func testCleanerSchedulerRules() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        for n in 0..<40 { XCTAssertTrue(OfficeCleaner.interval.contains(OfficeCleaner.delay(seed: "r", n: n))) }
        XCTAssertEqual(OfficeCleaner.interval, 90...180)
        XCTAssertEqual(OfficeCleaner.delay(seed: "r", n: 2), OfficeCleaner.delay(seed: "r", n: 2))
        let due = now.addingTimeInterval(-1)
        XCTAssertTrue(OfficeCleaner.shouldStart(now: now, dueAt: due, roomVisible: true, scenePaused: false, busy: false))
        XCTAssertFalse(OfficeCleaner.shouldStart(now: now, dueAt: due, roomVisible: false, scenePaused: false, busy: false), "oda görünmezken başlamaz")
        XCTAssertFalse(OfficeCleaner.shouldStart(now: now, dueAt: due, roomVisible: true, scenePaused: true, busy: false), "sahne duraklatılmışken başlamaz")
        XCTAssertFalse(OfficeCleaner.shouldStart(now: now, dueAt: due, roomVisible: true, scenePaused: false, busy: true), "odada bir kerede bir")
        XCTAssertFalse(OfficeCleaner.shouldStart(now: now, dueAt: now.addingTimeInterval(5), roomVisible: true, scenePaused: false, busy: false))
        XCTAssertFalse(OfficeCleaner.shouldStart(now: now, dueAt: nil, roomVisible: true, scenePaused: false, busy: false))
    }

    func testCleanerRouteWalksOnlyFreeTilesAndNeverSeats() throws {
        let kits = try assets().kits
        for tier in OfficeRoomTier.allCases {
            let kit = try XCTUnwrap(kits[tier])
            let route = OfficeCleaner.route(grid: kit.grid, entrance: kit.spots.entrance, laneRows: OfficeRoomTemplates.laneRows(stations: tier.stations))
            XCTAssertGreaterThan(route.count, 10, "\(tier)")
            XCTAssertEqual(route.first, kit.spots.entrance)
            XCTAssertEqual(route.last, kit.spots.entrance)
            let seatTiles = Set(kit.spots.seats.map(\.tile))
            XCTAssertTrue(route.allSatisfy { kit.grid.isWalkable($0) && !seatTiles.contains($0) }, "\(tier): rota koltuklara girmez")
            XCTAssertTrue(zip(route, route.dropFirst()).allSatisfy { $0.manhattan(to: $1) == 1 }, "adım adım")
            XCTAssertGreaterThan(Set(route.map(\.row)).count, 1)
        }
    }

    func testRoomCleanerStartsOnlyWhenVisibleAndOnce() throws {
        let scene = OfficeScene(assets: try assets(), size: CGSize(width: 1000, height: 640))
        scene.apply(members: members(subs: 3), animated: false)
        let room = try XCTUnwrap(scene.room("s"))
        let now = Date()
        XCTAssertFalse(room.cleanerTick(now: now), "ilk çağrı yalnızca zamanlar")
        let due = try XCTUnwrap(room.cleanerDueAt)
        XCTAssertTrue(OfficeCleaner.interval.contains(due.timeIntervalSince(now)) || due.timeIntervalSince(now) <= 180.5)
        room.isVisible = false
        XCTAssertFalse(room.cleanerTick(now: due.addingTimeInterval(1)), "görünmezken başlamaz")
        room.isVisible = true
        XCTAssertTrue(room.cleanerTick(now: due.addingTimeInterval(1)))
        XCTAssertTrue(room.isAnimating)
        XCTAssertFalse(room.cleanerTick(now: due.addingTimeInterval(2)), "bir kerede bir")
    }

    func testCarrierSequence() {
        XCTAssertEqual(OfficeCarrier.sequence(withCarrier: true), [.enter, .walkToDesk, .dropDesk, .showComputer, .walkBack, .leave, .seatAgent])
        XCTAssertEqual(OfficeCarrier.sequence(withCarrier: true).last, .seatAgent, "ajan en son oturur")
        XCTAssertEqual(OfficeCarrier.sequence(withCarrier: false), [.seatAgent])
        XCTAssertEqual(OfficeCarrier.dropDuration, 0.4)
    }

    func testGrowthInSceneKeepsActorsAndDefersNewcomerUntilCarrierDone() throws {
        let scene = OfficeScene(assets: try assets(), size: CGSize(width: 1000, height: 640))
        scene.apply(members: members(subs: 4), animated: false)
        XCTAssertEqual(scene.room("s")?.tier, .s4)
        scene.apply(members: members(subs: 5), animated: true)   // 6 üye → s6
        let room = try XCTUnwrap(scene.room("s"))
        XCTAssertEqual(room.tier, .s6)
        XCTAssertEqual(room.actorCount, 5, "oturanlar kaybolmadı; yeni ajan taşıyıcı bitene dek bekler")
        XCTAssertTrue(room.isAnimating, "taşıyıcı yürüyor")
        XCTAssertEqual(room.overflow, 0)
    }

    func testIdleVariantRunsFiniteAndStopsOnWork() throws {
        let scene = OfficeScene(assets: try assets(), size: CGSize(width: 1000, height: 640))
        scene.apply(members: members(subs: 2, status: .idle), animated: false)
        let room = try XCTUnwrap(scene.room("s"))
        let cand = try XCTUnwrap(room.idleCandidates().first)
        XCTAssertNotNil(room.startIdleVariant(id: cand.member.id))
        XCTAssertEqual(room.variantCount, 1)
        XCTAssertTrue(room.isAnimating)
        var m = members(subs: 2, status: .idle)
        m[cand.member.id == "s#0" ? 1 : 2].status = .tool("Edit")
        scene.apply(members: m, animated: false)
        XCTAssertEqual(room.variantCount, 0, "çalışmaya başlayınca varyant durur")
    }

    // MARK: Detay kartı

    func testDetailCardModel() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var ms = members(subs: 2)
        ms[0].startedAt = t0
        ms[1].activity = "Edit"; ms[1].target = "a.swift"
        ms[1].label = "crew-chief:reviewer"
        let lead = OfficeDetailCard.make(member: ms[0], members: ms, spawnedAt: nil)
        XCTAssertTrue(lead.isSession)
        XCTAssertEqual(lead.subagentCount, 2)
        XCTAssertEqual(lead.children.map(\.role), ["crew-chief:reviewer", "implementer"])
        XCTAssertEqual(lead.rows(now: t0.addingTimeInterval(125)).first { $0.title == "Süre" }?.value, "2:05")
        let sub = OfficeDetailCard.make(member: ms[1], members: ms, spawnedAt: t0)
        XCTAssertEqual(sub.parentTitle, "oturum")
        XCTAssertEqual(sub.roleName, "crew-chief:reviewer")
        XCTAssertEqual(sub.tool, "Edit · a.swift")
        XCTAssertTrue(sub.children.isEmpty)
        XCTAssertTrue(sub.tooltip.contains("Sonnet") && sub.tooltip.contains("crew-chief:reviewer"))
        XCTAssertEqual(OfficeDetailCard.duration(3725), "1:02:05")
    }

    func testSceneHitAndCardSelection() throws {
        let scene = OfficeScene(assets: try assets(), size: CGSize(width: 1000, height: 640))
        scene.apply(members: members(subs: 2), animated: false)
        var cards: [OfficeDetailCard?] = []
        scene.onCardChange = { cards.append($0) }
        let room = try XCTUnwrap(scene.room("s"))
        let a = try XCTUnwrap(room.actors["s#0"])
        // Karakterin sahnedeki görünüm noktası.
        let cell = try XCTUnwrap(scene.arrangement.cell(id: "s"))
        let contentY = cell.y + cell.height - (a.root.position.y + 10)
        let contentX = cell.x + a.root.position.x
        let z = CGFloat(scene.zoom)
        let viewPoint = CGPoint(x: (contentX - scene.cameraCenter.x) * z + scene.size.width / 2, y: (scene.cameraCenter.y - contentY) * z + scene.size.height / 2)
        let hit = try XCTUnwrap(scene.hit(atView: viewPoint))
        XCTAssertEqual(hit.memberID, "s#0")
        scene.pointerDown(at: viewPoint); scene.pointerUp(at: viewPoint)
        XCTAssertEqual(scene.selectedMemberID, "s#0")
        XCTAssertEqual(cards.last??.memberID, "s#0")
        XCTAssertNil(scene.selectedRoomID, "tek tık kartı açar, odaya yakınlaştırmaz")
        scene.escape()
        XCTAssertNil(scene.selectedMemberID)
        XCTAssertNil(cards.last ?? nil)
        scene.pointerDown(at: viewPoint, clickCount: 2); scene.pointerUp(at: viewPoint)
        XCTAssertEqual(scene.selectedRoomID, "s", "çift tık odaya yakınlaştırır")
    }

    // MARK: JSON sözleşmesi

    private var officeRoot: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "Resources/Office") }

    func testLayoutContractFields() throws {
        let built = try XCTUnwrap(OfficeWebLayout.build(officeRoot: officeRoot))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: built.json) as? [String: Any])
        XCTAssertEqual(root["v"] as? Int, 3)
        let tiers = try XCTUnwrap(root["tiers"] as? [String: [String: Any]])
        XCTAssertEqual(Set(tiers.keys), ["s2", "s4", "s6", "s8", "s12", "s16"])
        for (key, t) in tiers {
            let n = try XCTUnwrap(t["stations"] as? Int)
            XCTAssertEqual(key, "s\(n)")
            XCTAssertEqual((t["seats"] as? [[String: Any]])?.count, n + 1)
            XCTAssertEqual((t["blocks"] as? [[String: Int]])?.count, n / 2)
            XCTAssertNotNil(t["laneRows"]); XCTAssertNotNil(t["lamps"]); XCTAssertNotNil(t["coffeeTable"]); XCTAssertNotNil(t["coffee"])
            XCTAssertTrue((t["seats"] as? [[String: Any]] ?? []).allSatisfy { $0["computerKey"] != nil })
        }
        let v3 = try XCTUnwrap(root["v3"] as? [String: Any])
        XCTAssertEqual((v3["roles"] as? [[String: Any]])?.count, 15)
        XCTAssertEqual((v3["computers"] as? [[String: Any]])?.count, 6)
        let generated = try XCTUnwrap(v3["generated"] as? [String: String])
        for name in ["imac_blue_off", "imac_pink_on2", "macbook_gray_on3", "role_glasses", "lamp", "glow_pool", "glow_bulb", "mop", "box", "cup", "zzz"] {
            XCTAssertTrue(generated[name]?.hasPrefix("data:image/png;base64,") == true, name)
        }
        let lighting = try XCTUnwrap(v3["lighting"] as? [String: Any])
        XCTAssertEqual(lighting["nightStartHour"] as? Int, 19); XCTAssertEqual(lighting["nightStartMinute"] as? Int, 30)
        XCTAssertEqual(lighting["nightEndHour"] as? Int, 6); XCTAssertEqual(lighting["nightEndMinute"] as? Int, 30)
        let cleaner = try XCTUnwrap(v3["cleaner"] as? [String: Any])
        XCTAssertEqual(cleaner["intervalMin"] as? Double, 90); XCTAssertEqual(cleaner["intervalMax"] as? Double, 180)
        XCTAssertEqual((v3["carrier"] as? [String: Any])?["dropSeconds"] as? Double, 0.4)
    }

    func testStateContractFields() throws {
        let built = try XCTUnwrap(OfficeWebLayout.build(officeRoot: officeRoot))
        let builder = AgentWebSnapshotBuilder(seats: built.seats)
        let now = Date()
        let session = AgentSession(id: "sess", project: "p", model: "claude-opus-4-8", status: .tool("Edit"), startedAt: now, lastEventAt: now,
                                   subagents: [AgentSubagent(agentID: "1", agentType: "crew-chief:implementer-hard", model: "claude-haiku-4-5", status: .idle),
                                               AgentSubagent(agentID: "2", agentType: "mystery", model: nil, status: .tool("Bash"), activity: "Bash")])
        let data = builder.snapshot(sessions: [session], now: now)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["v"] as? Int, 3)
        let lighting = try XCTUnwrap(root["lighting"] as? [String: Any])
        XCTAssertNotNil(lighting["mode"]); XCTAssertNotNil(lighting["resolvedNight"]); XCTAssertEqual(lighting["nightStartHour"] as? Int, 19)
        let room = try XCTUnwrap((root["rooms"] as? [[String: Any]])?.first)
        XCTAssertEqual(room["tier"] as? String, "s2")
        XCTAssertEqual(room["stations"] as? Int, 2)
        XCTAssertNotNil((room["cleaner"] as? [String: Any])?["laneRows"])
        let members = try XCTUnwrap(room["members"] as? [[String: Any]])
        let lead = try XCTUnwrap(members.first { $0["kind"] as? String == "session" })
        XCTAssertEqual((lead["role"] as? [String: Any])?["key"] as? String, "lead")
        XCTAssertEqual(((lead["appearance"] as? [String: Any])?["computer"] as? [String: Any])?["kind"] as? String, "imac")
        let hard = try XCTUnwrap(members.first { ($0["label"] as? String) == "crew-chief:implementer-hard" })
        let role = try XCTUnwrap(hard["role"] as? [String: Any])
        XCTAssertEqual(role["key"] as? String, "implementer-hard")
        XCTAssertEqual(role["tint"] as? String, "#8E4FE0")
        XCTAssertEqual(role["accessory"] as? String, "headphones")
        let seatInfo = try XCTUnwrap(hard["seatInfo"] as? [String: Any])
        XCTAssertEqual(hard["seat"] as? Int, seatInfo["id"] as? Int, "eski `seat` alanı korunur")
        let computer = try XCTUnwrap(((hard["appearance"] as? [String: Any])?["computer"]) as? [String: Any])
        XCTAssertTrue(["imac", "macbook"].contains(computer["kind"] as? String ?? ""))
        let idle = try XCTUnwrap(hard["idleVariant"] as? [String: Any])
        XCTAssertEqual((idle["sequence"] as? [[String: Any]])?.count, 8)
        let mystery = try XCTUnwrap(members.first { ($0["label"] as? String) == "mystery" })
        XCTAssertEqual((mystery["role"] as? [String: Any])?["accessory"] as? String, "tag")
        // Aynı oda + koltuk → aynı bilgisayar (yeniden kurulunca değişmez).
        let again = try XCTUnwrap(JSONSerialization.jsonObject(with: AgentWebSnapshotBuilder(seats: built.seats).snapshot(sessions: [session], now: now)) as? [String: Any])
        let m2 = try XCTUnwrap(((again["rooms"] as? [[String: Any]])?.first?["members"] as? [[String: Any]])?.first { ($0["label"] as? String) == "crew-chief:implementer-hard" })
        XCTAssertEqual(((m2["appearance"] as? [String: Any])?["computer"] as? [String: Any])?["name"] as? String, computer["name"] as? String)
    }

    func testLightingJSONResolution() {
        let utc = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = utc
        let noon = cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        XCTAssertEqual(AgentWebSnapshotBuilder.lightingJSON(now: noon, mode: .auto, timeZone: utc)["resolvedNight"] as? Bool, false)
        XCTAssertEqual(AgentWebSnapshotBuilder.lightingJSON(now: noon, mode: .night, timeZone: utc)["resolvedNight"] as? Bool, true)
        XCTAssertEqual(AgentWebSnapshotBuilder.lightingJSON(now: noon, mode: .day, timeZone: utc)["mode"] as? String, "day")
    }

    // MARK: Görünümün yerinde yenilenmesi (model/rol sonradan öğrenilir)

    func testAppearanceRefreshesInPlaceWhenModelAndRoleAreLearnedLater() throws {
        for theme in [OfficeTheme.pixel, .vector] {
            let scene = OfficeScene(assets: try assets(), size: CGSize(width: 1000, height: 640), theme: theme)
            func team(_ badge: AgentModelBadge, subLabel: String) -> [OfficeMember] {
                [OfficeMember(id: "s", parentID: nil, kind: .session, label: "oturum", badge: badge, status: .tool("Bash"), groupIndex: 0),
                 OfficeMember(id: "s#0", parentID: "s", kind: .subagent, label: subLabel, badge: badge, status: .tool("Bash"), groupIndex: 0)]
            }
            scene.apply(members: team(.unknown, subLabel: "agent"), animated: false)
            let room = try XCTUnwrap(scene.room("s"))
            room.setLabels(true)
            let lead = try XCTUnwrap(room.actors["s"]), sub = try XCTUnwrap(room.actors["s#0"])
            let before = lead.appearance, subBefore = sub.appearance
            let spec = OfficeVectorCharacter.spec(for: before)
            XCTAssertEqual(before.badgeText, "?")
            XCTAssertTrue(lead.labelBuilt && sub.labelBuilt)
            let pos = lead.root.position, tile = lead.tile, behavior = lead.behavior
            let bodyBefore = lead.body, dotBefore = sub.labelDot?.color

            scene.apply(members: team(.sonnet, subLabel: "reviewer"), animated: false)
            XCTAssertTrue(room.actors["s"] === lead, "düğüm yeniden kurulmadı")
            XCTAssertTrue(lead.body === bodyBefore)
            XCTAssertEqual(lead.appearance.badgeText, "SONNET", "rozetle aynı anda")
            XCTAssertNotEqual(lead.appearance, before)
            XCTAssertNotEqual(OfficeVectorCharacter.spec(for: lead.appearance).key, spec.key, "look/aksesuar anahtarı değişti")
            XCTAssertEqual(lead.appearance.accessory, .cap)
            XCTAssertEqual(lead.root.position, pos)
            XCTAssertEqual(lead.tile, tile)
            XCTAssertEqual(lead.behavior, behavior)
            if theme == .pixel {
                XCTAssertEqual(Double(lead.body.colorBlendFactor), lead.appearance.tintBlend, accuracy: 0.001)
                XCTAssertNotNil(lead.accessory, "sonnet başlığı sonradan eklendi")
            }
            // Alt ajan: rol (agentType) sonradan gelince ton/aksesuar/etiket yenilenir; model rengi nokta olarak kalır.
            XCTAssertNotEqual(sub.appearance, subBefore)
            XCTAssertEqual(sub.appearance.role?.name, OfficeRoles.style(forAgentType: "reviewer").name)
            XCTAssertNotEqual(sub.appearance.role?.name, subBefore.role?.name)
            XCTAssertTrue(sub.labelBuilt, "etiket yeni rolle yeniden kuruldu")
            if theme == .vector {
                XCTAssertNotEqual(sub.labelDot?.color, dotBefore)
                XCTAssertEqual(sub.labelTitle, OfficeRoomNode.truncated(OfficeRoles.style(forAgentType: "reviewer").name, 22))
            }
        }
    }
}
