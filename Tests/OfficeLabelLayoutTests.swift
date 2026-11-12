import SpriteKit
import XCTest
@testable import Adalmon

/// Vektör etiket çakışma çözücüsü (saf mantık).
final class OfficeLabelLayoutTests: XCTestCase {
    private func row(_ n: Int, spacing: CGFloat, widths: [CGFloat] = [150, 100, 70]) -> [OfficeLabelItem] {
        (0..<n).map { OfficeLabelItem(id: "a\(String(format: "%02d", $0))", x: 10 + CGFloat($0) * spacing, y: 40, widths: widths) }
    }

    func testVariants() {
        XCTAssertEqual(OfficeLabelLayout.variants(of: "crew-chief:scanner"), ["crew-chief:scanner", "scanner"])
        XCTAssertEqual(OfficeLabelLayout.variants(of: "scanner"), ["scanner"])
        XCTAssertEqual(OfficeLabelLayout.variants(of: "★ adalmon"), ["★ adalmon"])
        let v = OfficeLabelLayout.variants(of: "crew-chief:implementer-hard")
        XCTAssertEqual(v.count, 3)
        XCTAssertEqual(v[1], "implementer-hard")
        XCTAssertEqual(v[2].count, 14)
        XCTAssertTrue(v[2].hasSuffix("…"))
    }

    func testNoOverlapNoChange() {
        let r = OfficeLabelLayout.resolve(row(3, spacing: 100), zoom: 2)
        XCTAssertEqual(r.overlaps, 0)
        XCTAssertTrue(r.placements.values.allSatisfy { $0.level == 0 && $0.variant == 0 })
    }

    func testTwoStaggerVertically() {
        let r = OfficeLabelLayout.resolve(row(2, spacing: 40), zoom: 2)
        XCTAssertEqual(r.overlaps, 0)
        XCTAssertEqual(r.placements["a00"], OfficeLabelPlacement(variant: 0, level: 0))
        XCTAssertEqual(r.placements["a01"], OfficeLabelPlacement(variant: 0, level: 1))
    }

    func testThreeUseTwoLevelsAtMost() {
        let r = OfficeLabelLayout.resolve(row(3, spacing: 40), zoom: 2)
        XCTAssertEqual(r.overlaps, 0)
        XCTAssertEqual(Set(r.placements.values.map(\.level)), [0, 1])
        XCTAssertTrue(r.placements.values.allSatisfy { $0.variant == 0 }, "kademe yetiyorsa metin kısaltılmaz")
    }

    func testSixStaggerThreeLevelsWithoutShortening() {
        let r = OfficeLabelLayout.resolve(row(6, spacing: 30), zoom: 2)
        XCTAssertEqual(r.overlaps, 0)
        XCTAssertTrue(r.placements.values.allSatisfy { $0.variant == 0 })
        XCTAssertEqual(Set(r.placements.values.map(\.level)), [0, 1, 2])
    }

    func testSixShortenWhenStaggerNotEnough() {
        let r = OfficeLabelLayout.resolve(row(6, spacing: 15), zoom: 2)
        XCTAssertEqual(r.overlaps, 0)
        XCTAssertTrue(r.placements.values.allSatisfy { $0.variant == 2 })
        XCTAssertTrue(r.placements.values.allSatisfy { $0.level <= OfficeLabelLayout.maxLevel })
    }

    func testTwelveAreBoundedAndImprove() {
        let items = row(12, spacing: 12)
        let r = OfficeLabelLayout.resolve(items, zoom: 2)
        XCTAssertEqual(r.placements.count, 12)
        XCTAssertTrue(r.placements.values.allSatisfy { $0.level <= OfficeLabelLayout.maxLevel && $0.variant == 2 })
        let flat = Dictionary(uniqueKeysWithValues: items.map { ($0.id, OfficeLabelPlacement(variant: 2, level: 0)) })
        XCTAssertLessThan(r.overlaps, OfficeLabelLayout.overlapCount(items, flat, zoom: 2), "kademe çakışmayı azaltır")
        // En az görünürlük: her etiketin en az biri, soldaki komşusunun üstünde kalmayan seviyede (üç kademe de farklı kullanılır).
        XCTAssertEqual(Set(r.placements.values.map(\.level)), [0, 1, 2])
    }

    func testDeterministicAndOrderIndependent() {
        let items = row(12, spacing: 25)
        let a = OfficeLabelLayout.resolve(items, zoom: 1.5)
        XCTAssertEqual(a.placements, OfficeLabelLayout.resolve(items.reversed(), zoom: 1.5).placements)
        XCTAssertEqual(a.placements, OfficeLabelLayout.resolve(items, zoom: 1.5).placements)
    }

    func testSingleVariantItemsStillResolve() {
        let items = row(4, spacing: 20, widths: [120])
        let r = OfficeLabelLayout.resolve(items, zoom: 2)
        XCTAssertEqual(r.placements.count, 4)
        XCTAssertTrue(r.placements.values.allSatisfy { $0.variant == 0 })
    }

    func testEmpty() {
        XCTAssertTrue(OfficeLabelLayout.resolve([], zoom: 1).placements.isEmpty)
    }

    func testLowPriorityHiddenInsteadOfOverlapping() {
        var items = row(12, spacing: 12)
        for i in items.indices { items[i].priority = i == 5 ? OfficeLabelLayout.protectedPriority : (i % 2 == 0 ? OfficeLabelLayout.runningPriority : OfficeLabelLayout.idlePriority) }
        let r = OfficeLabelLayout.resolve(items, zoom: 2)
        XCTAssertEqual(r.placements.count, 12)
        XCTAssertEqual(r.overlaps, 0, "gizlenenler sayılmaz, görünenler çakışmaz")
        XCTAssertTrue(r.placements.values.contains { $0.hidden })
        XCTAssertEqual(r.placements["a05"]?.hidden, false, "öncelikli etiket gizlenmez")
        // Çalışan, boştakinden önce yerleşir: gizlenen bir çalışan varsa tüm boştakiler de gizlidir.
        let hiddenRunning = items.filter { $0.priority == 1 && r.placements[$0.id]?.hidden == true }
        if !hiddenRunning.isEmpty { XCTAssertTrue(items.filter { $0.priority == 0 }.allSatisfy { r.placements[$0.id]?.hidden == true }) }
    }

    func testDefaultPriorityNeverHides() {
        let r = OfficeLabelLayout.resolve(row(12, spacing: 12), zoom: 2)
        XCTAssertTrue(r.placements.values.allSatisfy { !$0.hidden })
    }

    @MainActor
    func testCrowdDemoHasNoOverlappingVisibleLabels() throws {
        let assets = try XCTUnwrap(OfficeAssets.shared)
        let size = CGSize(width: 1600, height: 1000)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        let scene = OfficeScene(assets: assets, size: size, theme: .vector)
        view.presentScene(scene)
        scene.apply(members: OfficeMember.members(from: OfficeDemo.crowd()), animated: false)
        defer { scene.shutdown() }
        var checked = 0
        for id in scene.roomIDs {
            scene.select(id, animated: false)
            let rects = try XCTUnwrap(scene.room(id)).visibleLabelRects
            checked += rects.count
            for i in rects.indices { for j in rects.indices where j > i {
                XCTAssertFalse(rects[i].rect.intersects(rects[j].rect), "\(id): \(rects[i].id) / \(rects[j].id)")
            } }
        }
        XCTAssertGreaterThan(checked, 0)
    }
}
