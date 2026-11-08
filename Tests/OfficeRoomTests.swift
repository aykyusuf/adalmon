import XCTest
@testable import Adalmon

/// Oturum başına oda: oda atama/kademe/taşma, ızgara yerleşimi, kamera zoom'u, sahne davranışı ve düğüm sayısı.
@MainActor
final class OfficeRoomTests: XCTestCase {
    private func assets() throws -> OfficeAssets { try XCTUnwrap(OfficeAssets.shared, "ofis varlıkları yüklenemedi") }

    private func planner() throws -> OfficeRoomPlanner {
        OfficeRoomPlanner(seats: try assets().kits.mapValues { $0.spots.seats })
    }

    private func session(_ id: String, status: AgentStatus = .thinking) -> OfficeMember {
        OfficeMember(id: id, parentID: nil, kind: .session, label: "oturum-\(id)", badge: .opus, status: status, groupIndex: 0)
    }

    private func sub(_ id: String, of parent: String, status: AgentStatus = .thinking) -> OfficeMember {
        OfficeMember(id: "\(parent)#\(id)", parentID: parent, kind: .subagent, label: id, badge: .haiku, status: status, groupIndex: 0)
    }

    private func room(_ session: String, subs: Int) -> [OfficeMember] {
        [self.session(session)] + (0..<subs).map { sub("a\($0)", of: session) }
    }

    // MARK: Şablonlar / kademeler

    func testTierTemplatesHaveExpectedSeats() throws {
        let a = try assets()
        // Koltuk sayısı yönetici dahil: küçük 1+2+1 = 4, orta 1+6+1 = 8, büyük 1+10+1 = 12.
        let expected: [(OfficeRoomTier, Int, Int, Bool)] = [(.s2, 2, 0, true), (.s6, 6, 0, true), (.s16, 16, 0, true)]
        for (tier, desks, lounges, coffee) in expected {
            let kit = a.kit(tier)
            XCTAssertEqual(kit.spots.seats.filter { $0.kind == .executive }.count, 1, "\(tier): tek yönetici koltuğu")
            XCTAssertEqual(kit.spots.deskSeats.count, desks, "\(tier) masa koltuğu")
            XCTAssertEqual(kit.spots.loungeSeats.count, lounges, "\(tier) salon koltuğu")
            XCTAssertEqual(kit.spots.seats.count, 1 + desks + lounges)
            XCTAssertEqual(kit.spots.seats.count, tier.capacity)
            // Yönetici köşesi: koltuk id 0, yukarı (masaya) bakar, PC'si var, tüm masa koltuklarının üstünde (duvar tarafı);
            // beyaz tahtanın önüne yol var.
            let exec = try XCTUnwrap(kit.spots.executiveSeat, "\(tier)")
            XCTAssertEqual(exec.id, 0)
            XCTAssertEqual(exec.facing, .up)
            XCTAssertNotNil(exec.pcIndex)
            XCTAssertTrue(kit.spots.deskSeats.allSatisfy { $0.tile.row > exec.tile.row }, "\(tier): alt ajan masaları yönetici köşesinin altında")
            let board = try XCTUnwrap(kit.spots.board, "\(tier): beyaz tahta önü")
            XCTAssertEqual(kit.layout.furniture[try XCTUnwrap(kit.spots.boardIndex)].assetID, "WHITEBOARD")
            XCTAssertEqual(kit.layout.furniture.filter { $0.assetID == "WHITEBOARD" }.count, 1, "\(tier): tek beyaz tahta (yönetici)")
            XCTAssertNotNil(kit.grid.path(from: exec.tile, to: board), "\(tier): koltuktan tahtaya yol")
            XCTAssertNotNil(kit.grid.path(from: board, to: exec.tile), "\(tier): tahtadan koltuğa yol")
            // Yönetici alanı: tahta duvarda ortada, bölge (halı şeridi) tahta önünden yönetici masasına, alt ajan masalarından ayrı.
            let zone = try XCTUnwrap(kit.spots.zone, "\(tier): yönetici bölgesi")
            XCTAssertEqual([zone.minRow, zone.maxRow], [2, 4])
            XCTAssertTrue(zone.contains(board) && zone.contains(exec.tile))
            let boardF = kit.layout.furniture[try XCTUnwrap(kit.spots.boardIndex)]
            XCTAssertLessThanOrEqual(abs((boardF.col * 2 + 2) - (zone.minCol + zone.maxCol + 1)), 1, "\(tier): tahta odanın ortasında")
            XCTAssertTrue(kit.spots.seats.filter { $0.kind != .executive }.allSatisfy { !zone.contains($0.tile) }, "\(tier): yalnızca yönetici koltuğu bölgede")
            XCTAssertTrue(kit.spots.zoneTiles.allSatisfy { kit.grid.isWalkable($0) })
            XCTAssertEqual(kit.spots.coffee != nil, coffee, "her odada kahve makinesi")
            XCTAssertEqual(tier.hasCoffee, coffee)
            for seat in kit.spots.seats { XCTAssertNotNil(kit.grid.path(from: kit.spots.entrance, to: seat.tile), "\(tier) koltuğa yol yok: \(seat)") }
            for s in kit.spots.deskSeats { XCTAssertNotNil(s.pcIndex, "\(tier) masa koltuğunda PC yok") }
            if let c = kit.spots.coffee { XCTAssertNotNil(kit.grid.path(from: kit.spots.entrance, to: c)) }
        }
        XCTAssertLessThan(a.kit(.small).worldWidth, a.kit(.large).worldWidth)
    }

    // MARK: Oturum → oda, koltuk, taşma

    func testEachSessionGetsItsOwnRoomAndSubagentsSitInSameRoom() throws {
        var p = try planner()
        let plan = p.update(members: room("s1", subs: 2) + room("s2", subs: 0) + room("s3", subs: 5))
        XCTAssertEqual(plan.rooms.map(\.id), ["s1", "s2", "s3"], "oturum sırası korunur")
        XCTAssertEqual(plan.rooms.map(\.tier), [.small, .small, .medium], "3, 1 ve 6 üye")
        let r1 = plan.rooms[0]
        XCTAssertEqual(Set(r1.placements.keys), ["s1", "s1#a0", "s1#a1"], "alt ajanlar üst oturumunun odasında")
        XCTAssertEqual(r1.placements["s1"], .seat(0), "ana karakter odanın ilk masasında")
        for (_, pl) in r1.placements { if case .seat(let s) = pl { XCTAssertLessThan(s, 4) } else { XCTFail("taşma olmamalı") } }
        XCTAssertEqual(r1.title, "oturum-s1")
        XCTAssertEqual(r1.badge, .opus)
        XCTAssertEqual(plan.rooms[1].memberCount, 1)
        // Alt ajanlar önce boş masalara oturur (small: 2 masa).
        let seats = try assets().kit(.small).spots.seats
        let exec = try XCTUnwrap(seats.first { $0.kind == .executive })
        let nearest = try XCTUnwrap(seats.filter { $0.kind == .desk }.min { ($0.tile.manhattan(to: exec.tile), $0.id) < ($1.tile.manhattan(to: exec.tile), $1.id) })
        XCTAssertEqual(r1.placements["s1#a0"], .seat(nearest.id), "alt ajan ebeveynin (yönetici koltuğunun) en yakın masasına")
        for (id, pl) in r1.placements where id != "s1" {
            guard case .seat(let sid) = pl else { return XCTFail("taşma olmamalı") }
            XCTAssertNotEqual(seats[sid].kind, .executive, "yönetici koltuğu yalnızca ana ajana")
        }
        XCTAssertTrue(plan.removed.isEmpty)
    }

    func testOverflowShowsPlusNAfterTwelve() throws {
        var p = try planner()
        let plan = p.update(members: room("big", subs: 19))   // 20 üye
        let r = plan.rooms[0]
        XCTAssertEqual(r.tier, .s16)
        XCTAssertEqual(r.overflowCount, 3, "17 gösterilir, kalan 3 \"+3\"")
        XCTAssertEqual(r.placements.values.filter { if case .seat = $0 { true } else { false } }.count, 17)
        var q = try planner()
        let exactly12 = q.update(members: room("e", subs: 16)).rooms[0]
        XCTAssertEqual(exactly12.overflowCount, 0)
        XCTAssertEqual(exactly12.tier, .s16)
        // Taşan alt ajan sonra boş koltuğa kavuşur; sayaç azalır.
        let fewer = p.update(members: room("big", subs: 17))
        XCTAssertEqual(fewer.rooms[0].overflowCount, 1)
    }

    func testRoomRemovedWhenSessionEndsAndEmptyRoomReturns() throws {
        var p = try planner()
        let first = p.update(members: [])
        XCTAssertEqual(first.rooms.map(\.id), [OfficeRoomPlanner.emptyRoomID])
        XCTAssertEqual(first.rooms[0].tier, OfficeRoomPlanner.emptyTier)
        XCTAssertTrue(first.rooms[0].isPlaceholder)
        let two = p.update(members: room("a", subs: 1) + room("b", subs: 0))
        XCTAssertEqual(two.removed, [OfficeRoomPlanner.emptyRoomID], "boş oda oturum gelince kalkar")
        XCTAssertEqual(two.rooms.map(\.id), ["a", "b"])
        let one = p.update(members: room("b", subs: 0))
        XCTAssertEqual(one.removed, ["a"], "kapanan oturumun odası kalkar")
        XCTAssertEqual(one.rooms.map(\.id), ["b"])
        XCTAssertEqual(one.rooms[0].placements["b"], .seat(0), "kalan oda koltuğunu korur")
        let none = p.update(members: [])
        XCTAssertEqual(none.removed, ["b"])
        XCTAssertEqual(none.rooms.map(\.id), [OfficeRoomPlanner.emptyRoomID])
    }

    func testSubagentLeavingFreesSeatInItsRoom() throws {
        var p = try planner()
        _ = p.update(members: room("s", subs: 2))
        let q = p.update(members: [session("s"), sub("a1", of: "s")])
        XCTAssertEqual(q.rooms[0].departed, ["s#a0"])
    }

    // MARK: Izgara yerleşimi

    private func sizes(_ n: Int, w: Double = 176, h: Double = 202) -> [OfficeRoomSize] {
        (0..<n).map { OfficeRoomSize(id: "r\($0)", width: w + Double($0 % 3) * 16, height: h) }
    }

    func testArrangementForRoomCounts() {
        for n in [1, 2, 5, 10, 20] {
            let arr = OfficeRoomArranger.best(sizes(n), viewWidth: 1000, viewHeight: 640)
            XCTAssertEqual(arr.cells.map(\.id), (0..<n).map { "r\($0)" }, "sıra korunur (\(n))")
            XCTAssertGreaterThanOrEqual(arr.zoom, 1)
            XCTAssertLessThanOrEqual(arr.columns, n)
            let cells = arr.cells
            for (i, a) in cells.enumerated() {
                XCTAssertGreaterThanOrEqual(a.x, OfficeRoomArranger.margin)
                XCTAssertLessThanOrEqual(a.x + a.width, arr.contentWidth - OfficeRoomArranger.margin + 1e-9)
                XCTAssertLessThanOrEqual(a.y + a.height, arr.contentHeight - OfficeRoomArranger.margin + 1e-9)
                for b in cells[(i + 1)...] { XCTAssertFalse(a.rect.intersects(b.rect), "odalar çakışmaz: \(a.id) \(b.id)") }
            }
        }
        XCTAssertEqual(OfficeRoomArranger.best(sizes(1), viewWidth: 1000, viewHeight: 640).columns, 1)
        XCTAssertEqual(OfficeRoomArranger.best(sizes(1), viewWidth: 1000, viewHeight: 640).zoom, 2, "tek orta oda: 640/222 → 2")
    }

    func testArrangeFixedColumnsRowMajor() {
        let arr = OfficeRoomArranger.arrange(sizes(5, w: 100, h: 80).map { OfficeRoomSize(id: $0.id, width: 100, height: 80) }, columns: 3)
        XCTAssertEqual(arr.columns, 3)
        XCTAssertEqual(arr.cells.map { [$0.x, $0.y] }, [[10, 10], [130, 10], [250, 10], [10, 110], [130, 110]])
        XCTAssertEqual(arr.contentWidth, 10 + 300 + 40 + 10)
        XCTAssertEqual(arr.contentHeight, 10 + 160 + 20 + 10)
        XCTAssertEqual(OfficeRoomArranger.arrange([OfficeRoomSize(id: "x", width: 50, height: 50)], columns: 9).columns, 1, "sütun oda sayısını aşmaz")
        XCTAssertEqual(arr.cell(at: CGPoint(x: 140, y: 20))?.id, "r1")
        XCTAssertNil(arr.cell(at: CGPoint(x: 115, y: 20)), "koridor")
    }

    func testBestArrangementPicksFewerColumnsForNarrowWindowAndKeepsZoomAtLeastOne() {
        let narrow = OfficeRoomArranger.best(sizes(10), viewWidth: 400, viewHeight: 900)
        let wide = OfficeRoomArranger.best(sizes(10), viewWidth: 1800, viewHeight: 500)
        XCTAssertLessThan(narrow.columns, wide.columns)
        let huge = OfficeRoomArranger.best(sizes(20, w: 240, h: 250), viewWidth: 700, viewHeight: 400)
        XCTAssertEqual(huge.zoom, 1, "çok büyük sahnede odalar küçülmez: zoom 1, kaydırılır")
        XCTAssertTrue(huge.contentWidth > 700 || huge.contentHeight > 400)
    }

    // MARK: Kamera

    func testCameraFitZoomClampFocus() {
        let view = CGSize(width: 1000, height: 640)
        XCTAssertEqual(OfficeCamera.fitZoom(view: view, content: CGSize(width: 196, height: 222)), 2)
        XCTAssertEqual(OfficeCamera.fitZoom(view: view, content: CGSize(width: 160, height: 150)), 4)
        XCTAssertEqual(OfficeCamera.fitZoom(view: view, content: CGSize(width: 3000, height: 2000)), 1, "en az 1")
        XCTAssertEqual(OfficeCamera.fitZoom(view: CGSize(width: 9000, height: 9000), content: CGSize(width: 50, height: 50)), OfficeCamera.maxZoom)
        // Sığan içerik ortalanır; sığmayan kıstırılır.
        let small = CGSize(width: 196, height: 222)
        XCTAssertEqual(OfficeCamera.clamp(center: CGPoint(x: 0, y: 0), content: small, view: view, zoom: 2), CGPoint(x: 98, y: 111))
        let big = CGSize(width: 3000, height: 2000)
        XCTAssertEqual(OfficeCamera.clamp(center: .zero, content: big, view: view, zoom: 1), CGPoint(x: 500, y: 320), "sol-üst köşe")
        XCTAssertEqual(OfficeCamera.clamp(center: CGPoint(x: 9999, y: 9999), content: big, view: view, zoom: 1), CGPoint(x: 2500, y: 1680))
        // Odaya odak.
        let f = OfficeCamera.focus(on: CGRect(x: 1000, y: 700, width: 176, height: 202), content: big, view: view)
        XCTAssertEqual(f.zoom, 2)
        XCTAssertEqual(f.center, CGPoint(x: 1088, y: 801))
        let vp = OfficeCamera.viewport(center: f.center, view: view, zoom: f.zoom)
        XCTAssertTrue(vp.contains(CGRect(x: 1000, y: 700, width: 176, height: 202)))
        // Görünüm → içerik: görünüm merkezi kamera merkezidir; y ters.
        XCTAssertEqual(OfficeCamera.contentPoint(fromView: CGPoint(x: 500, y: 320), view: view, center: f.center, zoom: 2), f.center)
        XCTAssertEqual(OfficeCamera.contentPoint(fromView: CGPoint(x: 600, y: 420), view: view, center: f.center, zoom: 2), CGPoint(x: f.center.x + 50, y: f.center.y - 50))
    }

    // MARK: Sahne

    private func scene(_ size: CGSize = CGSize(width: 1000, height: 640)) throws -> OfficeScene { OfficeScene(assets: try assets(), size: size) }

    func testSceneBuildsRoomPerSessionAndSubagentsJoinTheSameRoom() throws {
        let s = try scene()
        let now = Date()
        let sessions = [AgentSession(id: "b", project: "ikinci", model: "claude-sonnet-5-5", status: .thinking, startedAt: now, lastEventAt: now),
                        AgentSession(id: "a", project: "birinci", model: "claude-opus-4-8", status: .tool("Edit"), startedAt: now.addingTimeInterval(-9), lastEventAt: now,
                                     subagents: [AgentSubagent(agentID: "x", agentType: "Explore", model: "claude-haiku-4-5", status: .thinking)])]
        s.apply(members: OfficeMember.members(from: sessions), animated: false)
        XCTAssertEqual(s.roomIDs, ["a", "b"], "başlangıç sırası: eski önce")
        XCTAssertEqual(Set(try XCTUnwrap(s.room("a")).actors.keys), ["a", "a#x"])
        XCTAssertEqual(Set(try XCTUnwrap(s.room("b")).actors.keys), ["b"])
        XCTAssertEqual(s.actorCount, 3)
        let r = try XCTUnwrap(s.room("a"))
        XCTAssertEqual(r.actors["a"]?.seat.id, 0)
        XCTAssertEqual(r.actors["a#x"]?.seat.kind, .desk)
        // Oturum kapanınca odası kalkar, ızgara yeniden dizilir.
        let before = try XCTUnwrap(s.arrangement.cell(id: "b")).x
        s.apply(members: OfficeMember.members(from: [sessions[0]]), animated: false)
        XCTAssertEqual(s.roomIDs, ["b"])
        XCTAssertNil(s.room("a"))
        XCTAssertLessThan(try XCTUnwrap(s.arrangement.cell(id: "b")).x, before + 1, "kalan oda öne kayar")
        XCTAssertEqual(s.arrangement.cells.count, 1)
    }

    func testAnimatedRoomRemovalKeepsSceneBusyUntilFadeEnds() throws {
        let s = try scene()
        let now = Date()
        let sessions = (0..<2).map { AgentSession(id: "k\($0)", project: "p\($0)", model: "claude-opus-4-8", status: .idle, startedAt: now.addingTimeInterval(Double(-$0)), lastEventAt: now) }
        s.apply(members: OfficeMember.members(from: sessions), animated: false)
        XCTAssertFalse(s.isAnimating)
        s.apply(members: OfficeMember.members(from: [sessions[0]]), animated: true)
        XCTAssertTrue(s.isAnimating, "kararma sürerken görünüm duraklatılmaz")
        XCTAssertEqual(s.roomIDs, ["k0"])
    }

    func testIdleCrowdHasNoAnimationAndNodeCountIsBounded() throws {
        let now = Date()
        let busy = OfficeDemo.crowd(now: now)
        let idle = busy.map { sess -> AgentSession in
            var c = sess; c.status = .idle
            c.subagents = c.subagents.map { var x = $0; x.status = .idle; return x }
            return c
        }
        let s = try scene()
        s.apply(members: OfficeMember.members(from: idle), animated: false)
        XCTAssertEqual(s.roomCount, 10)
        XCTAssertEqual(s.actorCount, 110)
        XCTAssertFalse(s.isAnimating, "hepsi boşta: animasyon yok")
        XCTAssertTrue(s.roomIDs.allSatisfy { s.room($0)?.tier == .large })
        let idleNodes = s.nodeCount

        let t = try scene()
        t.apply(members: OfficeMember.members(from: busy), animated: false)
        XCTAssertEqual(t.actorCount, 110)
        XCTAssertTrue(t.isAnimating)
        print("DUGUM-SAYISI idle=\(idleNodes) busy=\(t.nodeCount) odalar=\(t.roomCount) zoom=\(t.zoom) gorunur=\(t.visibleRoomCount) icerik=\(t.arrangement.contentWidth)x\(t.arrangement.contentHeight) sutun=\(t.arrangement.columns)")
        XCTAssertLessThan(t.nodeCount, 2500)
        // Etiketler kalabalıkta kurulmaz (düğüm tasarrufu); odaklanınca kurulur.
        let first = try XCTUnwrap(t.roomIDs.first)
        let before = t.nodeCount
        t.select(first, animated: false)
        XCTAssertGreaterThan(t.nodeCount, before, "odaklanınca etiketler kurulur")
        XCTAssertLessThan(t.nodeCount - before, 12 * 5 + 12 * 3, "yalnızca o odanın etiketleri ve metin balonları (karakter başına arka plan + etiket + kap)")
        XCTAssertTrue(t.roomIDs.dropFirst().allSatisfy { id in t.room(id)!.actors.values.allSatisfy { $0.textBubble == nil } }, "odak dışı odalarda balon düğümü yok")
        print("DUGUM-SAYISI odakli=\(t.nodeCount) gorunur=\(t.visibleRoomCount) zoom=\(t.zoom)")
    }

    func testOffscreenRoomsPauseWhenZoomedIn() throws {
        let s = try scene()
        s.apply(members: OfficeMember.members(from: OfficeDemo.crowd()), animated: false)
        let all = s.visibleRoomCount
        let target = try XCTUnwrap(s.roomIDs.last)
        s.select(target, animated: false)
        XCTAssertLessThan(s.visibleRoomCount, all, "dışarıda kalan odalar duraklar")
        XCTAssertGreaterThanOrEqual(s.visibleRoomCount, 1)
        XCTAssertTrue(try XCTUnwrap(s.room(target)).isVisible)
        s.select(nil, animated: false)
        XCTAssertEqual(s.visibleRoomCount, all, "geri çıkınca aynı görünürlük")
        XCTAssertNil(s.selectedRoomID)
    }

    func testSelectZoomsInAndEscapeOrSecondClickLeaves() throws {
        let s = try scene(CGSize(width: 1000, height: 640))
        var events: [String?] = []
        s.onSelectionChange = { events.append($0) }
        s.apply(members: OfficeMember.members(from: OfficeDemo.crowd()), animated: false)
        let overviewZoom = s.zoom
        let id = try XCTUnwrap(s.roomIDs.dropFirst(3).first)
        let cell = try XCTUnwrap(s.arrangement.cell(id: id))
        // Odanın görünümdeki konumunu kamera merkezinden hesapla ve tıkla.
        func viewPoint(of cell: OfficeRoomCell) -> CGPoint {
            let z = CGFloat(s.zoom)
            return CGPoint(x: 500 + (CGFloat(cell.x + cell.width / 2) - s.cameraCenter.x) * z, y: 320 - (CGFloat(cell.y + cell.height / 2) - s.cameraCenter.y) * z)
        }
        let p = viewPoint(of: cell)
        s.pointerDown(at: p); s.pointerUp(at: p)
        XCTAssertEqual(s.selectedRoomID, id)
        XCTAssertGreaterThanOrEqual(s.zoom, overviewZoom)
        XCTAssertGreaterThan(s.zoom, 1, "odaya yakınlaşıldı")
        let focused = OfficeCamera.focus(on: cell.rect, content: s.arrangement.contentSize, view: s.size)
        XCTAssertEqual(s.zoom, focused.zoom)
        XCTAssertEqual(s.cameraCenter, focused.center)
        // Aynı odaya tekrar tıklayınca geri çıkar.
        let p2 = viewPoint(of: cell)
        s.pointerDown(at: p2); s.pointerUp(at: p2)
        XCTAssertNil(s.selectedRoomID)
        XCTAssertEqual(s.zoom, overviewZoom)
        // Esc.
        s.select(id, animated: false)
        s.escape()
        XCTAssertNil(s.selectedRoomID)
        XCTAssertEqual(events, [id, nil, id, nil])
        // Sürükleme tıklama sayılmaz.
        s.pointerDown(at: CGPoint(x: 500, y: 320)); s.pointerDragged(to: CGPoint(x: 520, y: 320)); s.pointerUp(at: CGPoint(x: 520, y: 320))
        XCTAssertNil(s.selectedRoomID)
    }

    func testPlaceholderRoomIsNotSelectableAndResizeRefits() throws {
        let s = try scene()
        s.select(OfficeRoomPlanner.emptyRoomID, animated: false)
        XCTAssertNil(s.selectedRoomID)
        s.apply(members: OfficeMember.members(from: OfficeDemo.crowd()), animated: false)
        let big = s.zoom
        s.size = CGSize(width: 400, height: 300)
        XCTAssertEqual(s.zoom, 1)
        XCTAssertLessThanOrEqual(s.zoom, big)
        // Kaydırma: zoom 1 ve içerik büyük → merkez değişir, içerik sınırında kalır.
        let c0 = s.cameraCenter
        s.scroll(deltaX: -50, deltaY: 0)
        XCTAssertNotEqual(s.cameraCenter, c0)
        s.scroll(deltaX: 99_999, deltaY: 99_999)
        XCTAssertEqual(s.cameraCenter, OfficeCamera.clamp(center: .zero, content: s.arrangement.contentSize, view: s.size, zoom: 1))
    }

    func testDemoCrowdAndSingle() {
        let crowd = OfficeDemo.crowd()
        XCTAssertEqual(crowd.count, 10)
        XCTAssertTrue(crowd.allSatisfy { $0.subagents.count == 10 })
        let members = OfficeMember.members(from: crowd)
        XCTAssertEqual(members.count, 110)
        XCTAssertEqual(Set(members.map(\.badge)), [.opus, .sonnet, .haiku, .fable], "model karışımı")
        XCTAssertEqual(Set(members.filter { $0.kind == .session }.map(\.label)).count, 10)
        let single = OfficeMember.members(from: OfficeDemo.single())
        XCTAssertEqual(single.filter { $0.kind == .session }.count, 1)
        XCTAssertGreaterThanOrEqual(single.count, 3)
    }

    // MARK: Yönetici köşesi (sahne)

    private func leadSession(_ status: AgentStatus, subs: [AgentSubagent] = [], activity: String? = nil, target: String? = nil, at: Date? = nil) -> [AgentSession] {
        let now = Date()
        return [AgentSession(id: "L", project: "p", model: "claude-opus-4-8", status: status, startedAt: now, lastEventAt: now, subagents: subs,
                             activity: activity, target: target, activityAt: at)]
    }

    func testExecutiveWritesAtBoardWhenWorkingAndSitsWhenIdle() throws {
        let s = try scene()
        s.apply(members: OfficeMember.members(from: leadSession(.idle)), animated: false)
        let room = try XCTUnwrap(s.room("L"))
        let exec = try XCTUnwrap(room.actors["L"])
        XCTAssertEqual(exec.seat.kind, .executive)
        XCTAssertEqual(exec.tile, exec.seat.tile, "boşta: masasında oturur")
        XCTAssertFalse(exec.atBoard)
        XCTAssertFalse(room.isBoardWriting)
        XCTAssertFalse(s.isAnimating)

        s.apply(members: OfficeMember.members(from: leadSession(.thinking)), animated: false)
        XCTAssertTrue(exec.atBoard, "çalışırken beyaz tahtanın önünde ayakta")
        XCTAssertEqual(exec.tile, room.kit.spots.board)
        XCTAssertEqual(exec.direction, .up)
        XCTAssertEqual(exec.body.position.y, 0, "ayakta: oturma çökmesi yok")
        XCTAssertTrue(room.isBoardWriting, "tahtada yazma animasyonu")
        XCTAssertTrue(s.isAnimating)

        s.apply(members: OfficeMember.members(from: leadSession(.waitingPermission)), animated: false)
        XCTAssertFalse(exec.atBoard, "izin beklerken tahtadan ayrılıp yönetici bölgesinde volta atar")
        XCTAssertTrue(exec.strolling)
        XCTAssertTrue(try XCTUnwrap(room.kit.spots.zone).contains(exec.tile), "volta yönetici bölgesinde")
        XCTAssertEqual(exec.behavior.bubble, .alert, "izin beklerken \"!\" balonu")
        XCTAssertFalse(room.isBoardWriting, "okuma pozunda yazma animasyonu yok")
        XCTAssertTrue(s.isAnimating)

        s.apply(members: OfficeMember.members(from: leadSession(.tool("Bash"))), animated: false)
        XCTAssertTrue(exec.atBoard)
        XCTAssertFalse(exec.strolling)
        XCTAssertTrue(room.isBoardWriting)

        s.apply(members: OfficeMember.members(from: leadSession(.done)), animated: false)
        XCTAssertFalse(exec.atBoard)
        XCTAssertFalse(exec.strolling, "animasyonsuz uygulamada volta yok: doğrudan masada")
        XCTAssertEqual(exec.tile, exec.seat.tile, "iş bitince masasına döner")
        XCTAssertFalse(room.isBoardWriting)
        XCTAssertFalse(s.isAnimating, "boşta animasyon yok")

        s.apply(members: [], animated: false)
        XCTAssertNil(s.room("L"), "oturum kapanınca oda kalkar")
    }

    func testExecutiveWalksToBoardAnimatedAndLeavesThroughDoor() throws {
        let s = try scene()
        s.apply(members: OfficeMember.members(from: leadSession(.idle)), animated: false)
        s.apply(members: OfficeMember.members(from: leadSession(.tool("Edit"))), animated: true)
        let room = try XCTUnwrap(s.room("L"))
        let exec = try XCTUnwrap(room.actors["L"])
        XCTAssertTrue(exec.moving, "tahtaya yürüyor")
        XCTAssertTrue(s.isAnimating)
        // Yürürken iş biterse tahtaya varınca masaya geri döner (karar yürüyüşün sonunda).
        s.apply(members: OfficeMember.members(from: leadSession(.done)), animated: true)
        XCTAssertFalse(exec.behavior.standing)
        XCTAssertEqual(exec.strollUntil.map { $0 > Date() }, true, "boşa geçince 60 sn volta penceresi")
        s.apply(members: [], animated: true)
        XCTAssertNil(s.room("L"), "kapanan oturumun odası kalkar")
    }

    // MARK: Konuşma balonları (sahne)

    func testTextBubbleShowsToolVerbAndReusesNodesOnChange() throws {
        let s = try scene()
        let now = Date()
        let subs = [AgentSubagent(agentID: "a", agentType: "x", model: nil, status: .tool("Grep"), activity: "Grep", activityAt: now),
                    AgentSubagent(agentID: "b", agentType: "y", model: nil, status: .thinking, activityAt: now)]
        s.apply(members: OfficeMember.members(from: leadSession(.tool("Edit"), subs: subs, activity: "Edit", target: "main.swift", at: now)), animated: false, now: now)
        XCTAssertGreaterThanOrEqual(s.zoom, 2)
        let room = try XCTUnwrap(s.room("L"))
        func bubble(_ id: String) -> OfficeTextBubble? { room.actors[id]?.textBubble }
        XCTAssertEqual(bubble("L")?.text, "main.swift düzenliyor")
        XCTAssertEqual(bubble("L#a")?.text, "Arıyor")
        XCTAssertEqual(bubble("L#b")?.text, "Düşünüyor…")
        XCTAssertEqual(bubble("L")?.node.isHidden, false)
        let first = try XCTUnwrap(bubble("L#a"))
        XCTAssertEqual(first.node.children.count, 2, "tek arka plan sprite'ı + tek etiket")
        // Metin değişince aynı düğümler yeniden kullanılır; değişmeyen karaktere dokunulmaz.
        let untouched = try XCTUnwrap(bubble("L"))
        let later = now.addingTimeInterval(2)
        let subs2 = [AgentSubagent(agentID: "a", agentType: "x", model: nil, status: .tool("Bash"), activity: "Bash", target: "swift", activityAt: later),
                     subs[1]]
        s.apply(members: OfficeMember.members(from: leadSession(.tool("Edit"), subs: subs2, activity: "Edit", target: "main.swift", at: now)), animated: false, now: later)
        XCTAssertTrue(bubble("L#a") === first, "balon düğümü yeniden kullanılır")
        XCTAssertEqual(first.text, "swift çalıştırıyor")
        XCTAssertTrue(bubble("L") === untouched)
        XCTAssertEqual(untouched.text, "main.swift düzenliyor")
    }

    func testTextBubbleDisappearsAfterTenSecondsAndSkippedWhenNotWorking() throws {
        let s = try scene()
        let now = Date()
        s.apply(members: OfficeMember.members(from: leadSession(.tool("Read"), activity: "Read", at: now.addingTimeInterval(-11))), animated: false, now: now)
        let room = try XCTUnwrap(s.room("L"))
        XCTAssertNil(room.actors["L"]?.bubbleText, "10 sn olay yok: balon yok")
        XCTAssertTrue(room.actors["L"]?.bubbleExpired ?? false)
        s.apply(members: OfficeMember.members(from: leadSession(.tool("Read"), activity: "Read", at: now.addingTimeInterval(-3))), animated: false, now: now)
        XCTAssertEqual(room.actors["L"]?.bubbleText, "Dosya okuyor")
        XCTAssertTrue(room.actors["L"]?.bubbleTimer ?? false, "kalan süre için sayaç kurulur (görünüm duraklatılmaz)")
        XCTAssertTrue(s.isAnimating)
        s.apply(members: OfficeMember.members(from: leadSession(.idle)), animated: false, now: now)
        XCTAssertNil(room.actors["L"]?.bubbleText)
        XCTAssertFalse(room.actors["L"]?.bubbleTimer ?? true)
        XCTAssertEqual(room.actors["L"]?.textBubble?.node.isHidden, true)
    }

    func testNoTextBubbleNodesWhenZoomedOut() throws {
        let s = try scene()
        s.apply(members: OfficeMember.members(from: OfficeDemo.crowd()), animated: false)
        XCTAssertEqual(s.zoom, 1)
        XCTAssertTrue(s.roomIDs.allSatisfy { id in s.room(id)!.actors.values.allSatisfy { $0.textBubble == nil } }, "uzaktayken metin balonu düğümü kurulmaz")
    }
}
