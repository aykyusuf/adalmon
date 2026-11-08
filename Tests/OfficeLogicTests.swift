import XCTest
@testable import Adalmon

/// Ajan ofisi saf mantığı: düzen ayrıştırma, manifest, sprite dilimleme, BFS, masa atama, durum → davranış, model → görünüm.
@MainActor
final class OfficeLogicTests: XCTestCase {
    private func root() throws -> URL { try XCTUnwrap(OfficeAssets.bundleRoot(), "Office klasörü pakette yok") }

    private func realLayout() throws -> (OfficeLayout, [String: OfficeAsset], OfficeGrid, OfficeSpots) {
        let root = try root()
        let layout = try OfficeLayout.parse(Data(contentsOf: root.appending(path: "default-layout-1.json")))
        let catalog = OfficeCatalog.load(furnitureDirectory: root.appending(path: "furniture"))
        let grid = OfficeGrid(layout: layout, assets: catalog)
        return (layout, catalog, grid, try XCTUnwrap(OfficeSpots.derive(layout: layout, assets: catalog, grid: grid)))
    }

    // MARK: Düzen JSON

    func testLayoutParsesSyntheticJSON() throws {
        let json = #"{"version":1,"cols":3,"rows":2,"tiles":[255,0,1,1,1,9],"tileColors":[null,{"h":10,"s":20,"b":-5,"c":3},null,null,null,null],"furniture":[{"uid":"x","type":"SOFA_SIDE:left","col":1,"row":1}]}"#
        let l = try OfficeLayout.parse(Data(json.utf8))
        XCTAssertEqual([l.cols, l.rows, l.tiles.count], [3, 2, 6])
        XCTAssertEqual(l.kind(0, 0), .void)
        XCTAssertEqual(l.kind(1, 0), .wall)
        XCTAssertEqual(l.kind(2, 1), .floor(9))
        XCTAssertEqual(l.kind(5, 5), .void, "sınır dışı boşluk")
        XCTAssertNil(l.color(0, 0))
        XCTAssertEqual(l.color(1, 0), OfficeTileColor(h: 10, s: 20, b: -5, c: 3))
        XCTAssertEqual(l.furniture.first?.assetID, "SOFA_SIDE")
        XCTAssertEqual(l.furniture.first?.mirrored, true)
    }

    func testLayoutRejectsWrongTileCount() {
        let json = #"{"cols":3,"rows":3,"tiles":[1,1,1]}"#
        XCTAssertThrowsError(try OfficeLayout.parse(Data(json.utf8))) { error in
            XCTAssertEqual(error as? OfficeLayout.LayoutError, .badTileCount(expected: 9, got: 3))
        }
    }

    func testDefaultLayoutParses() throws {
        let (layout, catalog, _, _) = try realLayout()
        XCTAssertEqual([layout.cols, layout.rows], [21, 22])
        XCTAssertEqual(layout.tiles.count, 21 * 22)
        XCTAssertEqual(layout.furniture.count, 36)
        for f in layout.furniture { XCTAssertNotNil(catalog[f.assetID], "katalogda yok: \(f.assetID)") }
        let b = layout.visibleBounds
        XCTAssertEqual([b.minCol, b.minRow, b.maxCol, b.maxRow], [0, 9, 19, 20])
    }

    func testWallMask() throws {
        let (layout, _, _, _) = try realLayout()
        XCTAssertEqual(layout.wallMask(5, 10), 2 | 8, "üst duvarın ortası: doğu+batı")
        XCTAssertEqual(layout.wallMask(0, 10), 2 | 4, "sol-üst köşe: doğu+güney")
    }

    // MARK: Manifest

    func testManifestFlattensGroupsAndInheritsAttributes() throws {
        let pc = #"{"id":"PC","category":"electronics","type":"group","groupType":"rotation","canPlaceOnSurfaces":true,"backgroundTiles":1,"members":[{"type":"group","groupType":"state","orientation":"front","members":[{"type":"group","groupType":"animation","state":"on","members":[{"type":"asset","id":"PC_FRONT_ON_1","file":"PC_FRONT_ON_1.png","width":16,"height":32,"footprintW":1,"footprintH":2,"frame":0}]},{"type":"asset","id":"PC_FRONT_OFF","file":"PC_FRONT_OFF.png","width":16,"height":32,"footprintW":1,"footprintH":2,"state":"off"}]},{"type":"asset","id":"PC_SIDE","file":"PC_SIDE.png","width":16,"height":32,"footprintW":1,"footprintH":2,"orientation":"side","mirrorSide":true}]}"#
        let assets = try OfficeCatalog.parse(manifest: Data(pc.utf8), folder: "PC")
        XCTAssertEqual(assets.map(\.id), ["PC_FRONT_ON_1", "PC_FRONT_OFF", "PC_SIDE"])
        let on = assets[0]
        XCTAssertEqual([on.category, on.state, on.orientation], ["electronics", "on", "front"])
        XCTAssertTrue(on.onSurface)
        XCTAssertEqual(on.backgroundTiles, 1)
        XCTAssertEqual(on.file, "PC/PC_FRONT_ON_1.png")
        XCTAssertEqual(on.frame, 0)
        XCTAssertTrue(assets[2].mirrorSide)
        XCTAssertEqual(assets[1].state, "off")
    }

    func testRealCatalogHasAllAssetsWithFootprintMatchingSize() throws {
        let catalog = OfficeCatalog.load(furnitureDirectory: try root().appending(path: "furniture"))
        XCTAssertGreaterThanOrEqual(catalog.count, 38)
        for a in catalog.values {
            XCTAssertEqual(a.width, a.footprintW * 16, a.id)
            XCTAssertEqual(a.height, a.footprintH * 16, a.id)
            XCTAssertTrue(FileManager.default.fileExists(atPath: try root().appending(path: "furniture/\(a.file)").path), a.file)
        }
        XCTAssertEqual(catalog["DESK_FRONT"]?.footprintW, 3)
        XCTAssertEqual(catalog["CUSHIONED_BENCH"]?.category, "chairs")
    }

    // MARK: Sprite sayfası

    func testCharacterSheetSlicing() {
        XCTAssertEqual(OfficeCharacterSheet.sheetWidth, 112)
        XCTAssertEqual(OfficeCharacterSheet.sheetHeight, 96)
        XCTAssertEqual(OfficeCharacterSheet.pixelRect(direction: .down, frame: 0), CGRect(x: 0, y: 0, width: 16, height: 32))
        XCTAssertEqual(OfficeCharacterSheet.pixelRect(direction: .up, frame: 3), CGRect(x: 48, y: 32, width: 16, height: 32))
        XCTAssertEqual(OfficeCharacterSheet.pixelRect(direction: .right, frame: 6), CGRect(x: 96, y: 64, width: 16, height: 32))
        XCTAssertEqual(OfficeCharacterSheet.pixelRect(direction: .left, frame: 2), OfficeCharacterSheet.pixelRect(direction: .right, frame: 2), "sol = sağın yansıması")
        XCTAssertTrue(OfficeCharacterSheet.mirrorsHorizontally(.left))
        for d in OfficeCharacterSheet.Direction.allCases { for f in 0..<OfficeCharacterSheet.columns {
            let r = OfficeCharacterSheet.pixelRect(direction: d, frame: f)
            XCTAssertTrue(CGRect(x: 0, y: 0, width: 112, height: 96).contains(r))
        } }
        XCTAssertEqual((0..<4).map { OfficeCharacterSheet.frameIndex(.walk($0)) }, [0, 1, 2, 1])
        XCTAssertEqual([OfficeCharacterSheet.frameIndex(.typing(0)), OfficeCharacterSheet.frameIndex(.typing(1))], [3, 4])
        XCTAssertEqual([OfficeCharacterSheet.frameIndex(.reading(0)), OfficeCharacterSheet.frameIndex(.reading(1))], [5, 6])
    }

    func testCharacterTexturesSliceTo21FramesOf16x32() throws {
        let assets = try XCTUnwrap(OfficeAssets.shared)
        for index in 0..<6 {
            let frames = assets.characterFrames(index)
            XCTAssertEqual(frames.count, 21)
            for t in frames { XCTAssertEqual(t.size(), CGSize(width: 16, height: 32)) }
        }
    }

    func testColorize() {
        let c = OfficeTileColor(h: 0, s: 0, b: 0, c: 0).colorize(gray: 0.5)
        XCTAssertEqual(c.r, 0.5, accuracy: 0.001)
        XCTAssertEqual(c.g, 0.5, accuracy: 0.001)
        let red = OfficeRGB.fromHSL(h: 0, s: 1, l: 0.5)
        XCTAssertEqual([red.r, red.g, red.b], [1, 0, 0])
        XCTAssertEqual(OfficeTileColor(h: 0, s: 0, b: -100, c: 0).colorize(gray: 0.5).r, 0, accuracy: 0.001)
    }

    // MARK: BFS

    private func grid(_ rows: [String]) -> OfficeGrid {
        OfficeGrid(cols: rows[0].count, rows: rows.count, walkable: rows.flatMap { $0.map { $0 != "#" } })
    }

    func testBFSFindsShortestPathAroundObstacles() throws {
        let g = grid(["....", ".##.", "...."])
        let p = try XCTUnwrap(g.path(from: OfficeTile(0, 0), to: OfficeTile(3, 2)))
        XCTAssertEqual(p.count, 5)
        XCTAssertEqual(p.last, OfficeTile(3, 2))
        XCTAssertFalse(p.contains(OfficeTile(1, 1)))
        for (a, b) in zip([OfficeTile(0, 0)] + p, p) { XCTAssertEqual(a.manhattan(to: b), 1) }
    }

    func testBFSUnreachableAndTrivial() {
        let g = grid(["..#.", "..#.", "..#."])
        XCTAssertNil(g.path(from: OfficeTile(0, 0), to: OfficeTile(3, 0)))
        XCTAssertEqual(g.path(from: OfficeTile(0, 0), to: OfficeTile(0, 0)), [])
        XCTAssertNil(g.path(from: OfficeTile(0, 0), to: OfficeTile(9, 9)), "sınır dışı")
    }

    func testBFSAllowsBlockedGoalAndStart() {
        let g = grid([".#.", "..."])
        XCTAssertEqual(g.path(from: OfficeTile(0, 0), to: OfficeTile(1, 0))?.last, OfficeTile(1, 0), "koltuk engel olsa da hedef olur")
        XCTAssertNotNil(g.path(from: OfficeTile(1, 0), to: OfficeTile(2, 0)))
    }

    func testRealOfficeGridAndSpots() throws {
        let (layout, _, grid, spots) = try realLayout()
        XCTAssertEqual(spots.entrance, OfficeTile(18, 19))
        XCTAssertEqual(spots.door, OfficeTile(19, 19))
        XCTAssertFalse(grid.isWalkable(OfficeTile(5, 10)), "duvar")
        XCTAssertFalse(grid.isWalkable(OfficeTile(5, 18)), "masa")
        XCTAssertTrue(grid.isWalkable(OfficeTile(10, 15)), "oda arası kapı aralığı")
        XCTAssertEqual(spots.deskSeats.count, 6)
        XCTAssertEqual(spots.loungeSeats.count, 8)
        XCTAssertNotNil(spots.coffee)
        for seat in spots.seats {
            XCTAssertNotNil(grid.path(from: spots.entrance, to: seat.tile), "koltuğa yol yok: \(seat)")
        }
        XCTAssertNotNil(grid.path(from: spots.entrance, to: try XCTUnwrap(spots.coffee)))
        // Her masa koltuğunun bir bilgisayarı var; yön masaya doğru.
        for s in spots.deskSeats { XCTAssertNotNil(s.pcIndex, "PC yok: \(s)") }
        let bench = try XCTUnwrap(spots.deskSeats.first { $0.tile == OfficeTile(3, 14) })
        XCTAssertEqual(bench.facing, .up)
        XCTAssertEqual(layout.furniture[try XCTUnwrap(bench.pcIndex)].assetID, "PC_FRONT_OFF")
        let side = try XCTUnwrap(spots.deskSeats.first { $0.tile == OfficeTile(3, 17) })
        XCTAssertEqual(side.facing, .right)
        XCTAssertEqual(try XCTUnwrap(spots.deskSeats.first { $0.tile == OfficeTile(7, 17) }).facing, .left)
    }

    // MARK: Üyeler + masa atama

    private func seats(desk: Int, lounge: Int) -> [OfficeSeat] {
        (0..<desk).map { OfficeSeat(id: $0, tile: OfficeTile($0, 0), facing: .down, kind: .desk, pcIndex: nil) }
            + (0..<lounge).map { OfficeSeat(id: desk + $0, tile: OfficeTile($0, 5), facing: .down, kind: .lounge, pcIndex: nil) }
    }

    private func member(_ id: String, parent: String? = nil, status: AgentStatus = .thinking) -> OfficeMember {
        OfficeMember(id: id, parentID: parent, kind: parent == nil ? .session : .subagent, label: id, badge: .opus, status: status, groupIndex: 0)
    }

    func testAssignmentDistributesDesksInOrderAndKeepsThem() {
        var a = OfficeAssigner(seats: seats(desk: 3, lounge: 0))
        let p1 = a.update(members: [member("s1"), member("s2")])
        XCTAssertEqual(p1.placements, ["s1": .seat(0), "s2": .seat(1)])
        let p2 = a.update(members: [member("s1"), member("s2"), member("s3")])
        XCTAssertEqual(p2.placements["s1"], .seat(0))
        XCTAssertEqual(p2.placements["s3"], .seat(2))
        XCTAssertTrue(p2.departed.isEmpty)
    }

    func testAssignmentFreesSeatOfDepartedAndReuses() {
        var a = OfficeAssigner(seats: seats(desk: 2, lounge: 0))
        _ = a.update(members: [member("s1"), member("s2")])
        let p = a.update(members: [member("s2"), member("s3")])
        XCTAssertEqual(p.departed, ["s1"])
        XCTAssertEqual(p.placements["s2"], .seat(1), "kalan üye yerini korur")
        XCTAssertEqual(p.placements["s3"], .seat(0), "boşalan masa yeniden kullanılır")
    }

    func testSubagentSitsNearestToParent() {
        var a = OfficeAssigner(seats: seats(desk: 5, lounge: 0))
        // s1 (seat 0) ve s2 (seat 1) otursun, sonra s2'nin alt ajanı: en yakın boş = seat 2.
        _ = a.update(members: [member("s1"), member("s2")])
        let p = a.update(members: [member("s1"), member("s2"), member("s2#a", parent: "s2")])
        XCTAssertEqual(p.placements["s2#a"], .seat(2))
        let q = a.update(members: [member("s1"), member("s2"), member("s2#a", parent: "s2"), member("s1#b", parent: "s1")])
        XCTAssertEqual(q.placements["s1#b"], .seat(3), "seat 0'a en yakın boş: sütun 3 (1 ve 2 dolu)")
    }

    func testMembersFromSessions() {
        let now = Date()
        let sub = AgentSubagent(agentID: "a1", agentType: "Explore", model: "claude-haiku-4-5", status: .tool("Grep"))
        let doneSub = AgentSubagent(agentID: "a2", agentType: "Plan", model: nil, status: .done)
        let s1 = AgentSession(id: "s1", project: "adalmon", model: "claude-opus-4-8", status: .thinking, startedAt: now, lastEventAt: now, subagents: [sub, doneSub])
        let s2 = AgentSession(id: "s2", project: "eski", model: "claude-sonnet-5-5", status: .ended, startedAt: now.addingTimeInterval(-9), lastEventAt: now)
        let s3 = AgentSession(id: "s3", project: "web", model: nil, status: .idle, startedAt: now.addingTimeInterval(-5), lastEventAt: now,
                              subagents: [AgentSubagent(agentID: "x", agentType: "Plan", model: nil, status: .thinking)])
        let m = OfficeMember.members(from: [s1, s3, s2])
        XCTAssertEqual(m.map(\.id), ["s3", "s3#x", "s1", "s1#a1"], "eskiden yeniye; kapalı oturum ve biten alt ajan yok")
        XCTAssertEqual(m.first { $0.id == "s1#a1" }?.badge, .haiku)
        XCTAssertEqual(m.first { $0.id == "s1#a1" }?.parentID, "s1")
        XCTAssertEqual(m.first { $0.id == "s3#x" }?.badge, .unknown, "model yoksa üst oturumunki (burada da bilinmiyor)")
        XCTAssertEqual(m.first { $0.id == "s1" }?.groupIndex, m.first { $0.id == "s1#a1" }?.groupIndex, "alt ajan üstle aynı şerit")
        XCTAssertEqual(OfficeMember.stableGroup(for: "abc", fallback: 0), OfficeMember.stableGroup(for: "abc", fallback: 3))
    }

    // MARK: Durum → davranış

    func testStatusToBehavior() {
        let typing = OfficeBehavior.behavior(for: .tool("Edit"), atDesk: true)
        XCTAssertEqual([typing.pose == .typing, typing.pcOn, typing.bubble == nil], [true, true, true])
        let thinking = OfficeBehavior.behavior(for: .thinking, atDesk: true)
        XCTAssertEqual(thinking.bubble, .thinking)
        XCTAssertEqual(thinking.pose, .typing)
        let perm = OfficeBehavior.behavior(for: .waitingPermission, atDesk: true)
        XCTAssertEqual(perm.bubble, .alert)
        XCTAssertEqual(perm.pose, .reading)
        let idle = OfficeBehavior.behavior(for: .idle, atDesk: true)
        XCTAssertEqual([idle.pose == .sitting, idle.pcOn, idle.mayWander], [true, false, true])
        XCTAssertTrue(OfficeBehavior.behavior(for: .done, atDesk: true).mayWander)
        XCTAssertFalse(OfficeBehavior.behavior(for: .thinking, atDesk: true).mayWander)
        // Salonda PC yok: yazmak yerine okur.
        let lounge = OfficeBehavior.behavior(for: .tool("Read"), atDesk: false)
        XCTAssertEqual(lounge.pose, .reading)
        XCTAssertFalse(lounge.pcOn)
    }

    func testCelebrationOnlyWhenWorkFinishes() {
        XCTAssertTrue(OfficeBehavior.celebrates(from: .thinking, to: .done))
        XCTAssertTrue(OfficeBehavior.celebrates(from: .tool("Bash"), to: .done))
        XCTAssertFalse(OfficeBehavior.celebrates(from: .idle, to: .done))
        XCTAssertFalse(OfficeBehavior.celebrates(from: .done, to: .done))
        XCTAssertFalse(OfficeBehavior.celebrates(from: nil, to: .done))
        XCTAssertFalse(OfficeBehavior.celebrates(from: .thinking, to: .idle))
    }

    func testPCFrames() {
        XCTAssertEqual(OfficeBehavior.pcOnFrames(forOffAsset: "PC_FRONT_OFF"), ["PC_FRONT_ON_1", "PC_FRONT_ON_2", "PC_FRONT_ON_3"])
        XCTAssertNil(OfficeBehavior.pcOnFrames(forOffAsset: "PC_SIDE"))
    }

    func testWanderDecision() {
        let now = Date()
        let old = OfficeWander.Candidate(id: "a", idleSince: now.addingTimeInterval(-60))
        let fresh = OfficeWander.Candidate(id: "b", idleSince: now.addingTimeInterval(-5))
        XCTAssertEqual(OfficeWander.pick([fresh, old], now: now, lastWander: nil, someoneWalking: false, roll: 0.1), "a")
        XCTAssertNil(OfficeWander.pick([fresh], now: now, lastWander: nil, someoneWalking: false, roll: 0.1), "yeterince boşta değil")
        XCTAssertNil(OfficeWander.pick([old], now: now, lastWander: nil, someoneWalking: true, roll: 0.1))
        XCTAssertNil(OfficeWander.pick([old], now: now, lastWander: now.addingTimeInterval(-3), someoneWalking: false, roll: 0.1))
        XCTAssertNil(OfficeWander.pick([old], now: now, lastWander: nil, someoneWalking: false, roll: 0.9), "olasılık kapısı")
    }

    // MARK: Model → görünüm

    func testModelToAppearanceDistinct() {
        let all = AgentModelBadge.allCases.map(OfficeAppearance.appearance(for:))
        XCTAssertEqual(Set(all.map(\.characterIndex)).count, 5, "her model ayrı karakter dokusu")
        XCTAssertTrue(all.allSatisfy { (0..<6).contains($0.characterIndex) })
        XCTAssertEqual(Set(all.map(\.accessory)).count, 5)
        XCTAssertEqual(OfficeAppearance.appearance(for: .opus).accessory, .crown)
        XCTAssertEqual(OfficeAppearance.appearance(for: .sonnet).accessory, .cap)
        XCTAssertEqual(OfficeAppearance.appearance(for: .fable).accessory, .star)
        XCTAssertEqual(OfficeAppearance.appearance(for: .unknown).accessory, OfficeAccessory.none)
        XCTAssertEqual(AgentModelBadge.allCases.filter { OfficeAppearance.appearance(for: $0).small }, [.haiku])
        // Panel rozetiyle aynı renk ailesi: Sonnet mavi, Haiku yeşil, Opus mor, Fable turuncu.
        let sonnet = OfficeAppearance.appearance(for: .sonnet).tint, haiku = OfficeAppearance.appearance(for: .haiku).tint
        XCTAssertGreaterThan(sonnet.b, sonnet.r + 0.5)
        XCTAssertGreaterThan(haiku.g, haiku.r + 0.4)
        XCTAssertGreaterThan(OfficeAppearance.appearance(for: .fable).tint.r, OfficeAppearance.appearance(for: .fable).tint.b + 0.5)
        let opus = OfficeAppearance.appearance(for: .opus).tint
        XCTAssertTrue(opus.r > opus.g && opus.b > opus.g)
    }

    func testIntegerScaling() {
        XCTAssertEqual(OfficeAppearance.spriteScale(small: true, zoom: 3), 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(OfficeAppearance.spriteScale(small: true, zoom: 4), 0.75, accuracy: 1e-9)
        XCTAssertEqual(OfficeAppearance.spriteScale(small: true, zoom: 1), 1)
        XCTAssertEqual(OfficeAppearance.spriteScale(small: false, zoom: 4), 1)
        XCTAssertEqual(OfficeAppearance.integerZoom(viewWidth: 1010, viewHeight: 700, contentWidth: 336, contentHeight: 208), 3)
        XCTAssertEqual(OfficeAppearance.integerZoom(viewWidth: 100, viewHeight: 100, contentWidth: 336, contentHeight: 208), 1)
        XCTAssertEqual(OfficeAppearance.integerZoom(viewWidth: 5000, viewHeight: 5000, contentWidth: 336, contentHeight: 208), 8)
    }

    func testDemoCoversAllModelsAndSubagents() {
        let steps = OfficeDemo.steps()
        XCTAssertGreaterThanOrEqual(steps.count, 5)
        let showcase = OfficeMember.members(from: OfficeDemo.showcase)
        XCTAssertEqual(Set(showcase.map(\.badge)), [.opus, .sonnet, .haiku, .fable])
        XCTAssertEqual(showcase.filter { $0.kind == .subagent }.count, 3)
        XCTAssertEqual(showcase.count, 6)
        XCTAssertTrue(showcase.contains { $0.status == .waitingPermission })
    }

    // MARK: Sahne (SKAction'sız, anlık mod)

    func testSceneIsStaticWithoutAgentsOrWhenAllIdle() throws {
        let scene = OfficeScene(assets: try XCTUnwrap(OfficeAssets.shared), size: CGSize(width: 1000, height: 640))
        var changes: [Bool] = []
        scene.onAnimationStateChange = { changes.append($0) }
        XCTAssertFalse(scene.isAnimating, "ajan yokken animasyon yok")
        XCTAssertEqual(scene.roomCount, 1, "ajan yokken tek boş oda")
        XCTAssertEqual(scene.room(OfficeRoomPlanner.emptyRoomID)?.tier, .medium)
        let emptyZoom = OfficeCamera.fitZoom(view: CGSize(width: 1000, height: 640), content: scene.arrangement.contentSize)
        XCTAssertEqual(scene.zoom, CGFloat(emptyZoom))
        scene.apply(members: [member("s1", status: .idle), member("s2", status: .done)], animated: false)
        XCTAssertEqual(scene.actorCount, 2)
        XCTAssertEqual(scene.roomCount, 2, "oturum başına oda")
        XCTAssertFalse(scene.isAnimating, "hepsi boşta/bitti: durağan, ev sahibi duraklatabilir")
        scene.apply(members: [member("s1", status: .thinking), member("s2", status: .done)], animated: false)
        XCTAssertTrue(scene.isAnimating)
        scene.apply(members: [member("s1", status: .waitingPermission)], animated: false)
        XCTAssertEqual(scene.memberIDs, ["s1"], "kaybolan üye sahneden kalktı")
        XCTAssertEqual(scene.roomCount, 1)
        XCTAssertTrue(scene.isAnimating, "izin balonu hareketli")
        scene.apply(members: [], animated: false)
        XCTAssertFalse(scene.isAnimating)
        XCTAssertEqual(changes, [true, false])
        scene.size = CGSize(width: 700, height: 460)
        XCTAssertEqual(scene.zoom, CGFloat(OfficeCamera.fitZoom(view: CGSize(width: 700, height: 460), content: scene.arrangement.contentSize)),
                       "yeniden boyutlandırmada uyum zoom'u yeniden hesaplanır")
    }

    func testAgentOfficeSectionWired() {
        XCTAssertEqual(MainSection.agentOffice.shortcutKey, "9")
        XCTAssertEqual(MainSection.agentOffice.title, "Ajan ofisi")
        XCTAssertEqual(MainSection(id: "agentOffice"), .agentOffice)
    }
}
