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
}
