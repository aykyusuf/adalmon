import XCTest
@testable import Adalmon

/// Elle ilerletilen zaman kaynağı.
@MainActor
private final class TestClock {
    var now = ContinuousClock.now
    func advance(by d: Duration) { now = now + d }
}

/// "İşlemler" tablosu: sütun yerleşimi (genişliğe göre) ve sıra kararlılığı (satırlar her ölçümde zıplamasın).
@MainActor
final class ProcessTableStabilityTests: XCTestCase {
    // MARK: Sütun yerleşimi

    func testColumnsNeverExceedWidthAndKeepNameMinimum() {
        for width in stride(from: CGFloat(300), through: 3_000, by: 37) {
            let c = ProcessTableLayout.columns(forWidth: width)
            XCTAssertLessThanOrEqual(c.totalWidth, width + 0.5, "toplam genişlik aşıldı: \(width)")
            if width >= 700 { XCTAssertGreaterThanOrEqual(c.nameWidth, ProcessTableLayout.nameMinWidth, "ad en azını korur: \(width)") }
        }
    }

    func testExtraColumnsAppearOnlyWhenWide() {
        func extras(_ w: CGFloat) -> [ProcessColumn] {
            ProcessTableLayout.columns(forWidth: w).entries.map(\.column).filter { !$0.isMetric }
        }
        XCTAssertEqual(extras(700), [])
        XCTAssertEqual(extras(1_100), [])
        XCTAssertEqual(extras(1_200), [.processCount])
        XCTAssertEqual(extras(1_400), [.processCount, .category])
        XCTAssertEqual(extras(2_200), [.processCount, .category, .pid])
    }

    func testMetricColumnsGrowAtMost1_5xAndNameIsCapped() {
        let narrow = ProcessTableLayout.columns(forWidth: 700)
        let wide = ProcessTableLayout.columns(forWidth: 2_200)
        XCTAssertLessThanOrEqual(wide.nameWidth, ProcessTableLayout.nameMaxWidth)
        let cpuNarrow = narrow.entries.first { $0.column == .cpu }?.width ?? 0
        let cpuWide = wide.entries.first { $0.column == .cpu }?.width ?? 0
        XCTAssertGreaterThan(cpuWide, cpuNarrow)
        XCTAssertLessThanOrEqual(cpuWide, ProcessTableLayout.baseWidth(.cpu) * ProcessTableLayout.maxMetricScale + 1)
        XCTAssertLessThan(wide.totalWidth, 2_200, "artan boşluk sağda kalır, sayılar adın yanında durur")
    }

    func testAtMinimumWindowAllMetricColumnsAreVisibleAndFit() {
        // 940 pt pencere: kenar çubuğu ~210, sayfa içi boşluklar 32.
        let w = ProcessTableLayout.contentWidth(forContainer: 940 - 210)
        let c = ProcessTableLayout.columns(forWidth: w)
        XCTAssertEqual(c.entries.map(\.column), ProcessTableLayout.numericColumns)
        XCTAssertLessThanOrEqual(c.totalWidth, w)
        XCTAssertGreaterThanOrEqual(c.nameWidth, 150)
    }

    // MARK: Sıra kararlılığı

    private func snapshot(_ cpu: [String: UInt64]) -> LiveSnapshot {
        LiveSnapshot(groups: cpu.map { key, ns in
            LiveGroup(key: key, usage: ResourceUsage(cpuNs: ns, footprint: 80_000_000), processCount: 1, pids: [1], members: [])
        }, elapsed: 1, totalProcessCount: cpu.count)
    }

    private func order(_ live: ProcessLiveModel) -> [String] {
        live.sections.flatMap(\.rows).map { ($0.key as NSString).lastPathComponent }
    }

    func testOrderIsStableBetweenResortsAndFollowsAfterwards() {
        let live = ProcessLiveModel()
        let a = "/Applications/A.app", b = "/Applications/B.app"
        live.apply(snapshot([a: 3_000_000_000, b: 1_000_000_000]), snapshot: nil, net: [:])
        XCTAssertEqual(order(live), ["A.app", "B.app"], "ilk ölçüm sıralar")
        live.apply(snapshot([a: 1_000_000_000, b: 3_000_000_000]), snapshot: nil, net: [:])
        XCTAssertEqual(order(live), ["A.app", "B.app"], "2. ölçümde sıra korunur")
        XCTAssertEqual(live.sections.first?.rows.last?.key, b)
        XCTAssertGreaterThan(live.sections.first?.rows.last?.cpu ?? 0, live.sections.first?.rows.first?.cpu ?? 0, "değerler güncellenir")
        live.apply(snapshot([a: 1_000_000_000, b: 3_000_000_000]), snapshot: nil, net: [:])
        XCTAssertEqual(order(live), ["B.app", "A.app"], "\(ProcessLiveModel.resortEvery). ölçümde yeniden sıralanır")
    }

    func testOrderFreezesWhilePointerIsInsideAndResortsAfterLeaving() {
        let clock = TestClock()
        let live = ProcessLiveModel()
        live.now = { clock.now }
        let a = "/Applications/A.app", b = "/Applications/B.app"
        live.apply(snapshot([a: 3_000_000_000, b: 1_000_000_000]), snapshot: nil, net: [:])
        live.isPointerInside = true
        for _ in 0..<(ProcessLiveModel.resortEvery * 2) {
            live.apply(snapshot([a: 1_000_000_000, b: 3_000_000_000]), snapshot: nil, net: [:])
            XCTAssertEqual(order(live), ["A.app", "B.app"], "imleç listedeyken sıra donar")
        }
        live.isPointerInside = false
        clock.advance(by: ProcessLiveModel.reorderHoldOff + .milliseconds(1))
        live.apply(snapshot([a: 1_000_000_000, b: 3_000_000_000]), snapshot: nil, net: [:])
        XCTAssertEqual(order(live), ["B.app", "A.app"], "imleç çıkınca (bekleme dolunca) bir sonraki ölçümde yenilenir")
    }

    func testNoPeriodicReorderShortlyAfterPointerEntersOrSelection() {
        let clock = TestClock()
        let live = ProcessLiveModel()
        live.now = { clock.now }
        let a = "/Applications/A.app", b = "/Applications/B.app"
        live.apply(snapshot([a: 3_000_000_000, b: 1_000_000_000]), snapshot: nil, net: [:])
        let swapped = snapshot([a: 1_000_000_000, b: 3_000_000_000])

        // İmleç girdi ve hemen çıktı: bekleme süresince periyodik yeniden sıralama olmaz.
        live.isPointerInside = true
        live.isPointerInside = false
        for _ in 0..<(ProcessLiveModel.resortEvery * 2) { live.apply(swapped, snapshot: nil, net: [:]) }
        XCTAssertEqual(order(live), ["A.app", "B.app"], "imleç girişinden sonra 1,5 sn sıra değişmez")
        clock.advance(by: ProcessLiveModel.reorderHoldOff + .milliseconds(1))
        live.apply(swapped, snapshot: nil, net: [:])
        XCTAssertEqual(order(live), ["B.app", "A.app"], "bekleme dolunca bekleyen yeniden sıralama uygulanır")

        // Tıklama/klavye seçimi de bekleme başlatır.
        let back = snapshot([a: 3_000_000_000, b: 1_000_000_000])
        live.selection = live.sections.first?.rows.first?.id
        for _ in 0..<(ProcessLiveModel.resortEvery * 2) { live.apply(back, snapshot: nil, net: [:]) }
        XCTAssertEqual(order(live), ["B.app", "A.app"], "seçimden sonra 1,5 sn sıra değişmez")
        clock.advance(by: ProcessLiveModel.reorderHoldOff + .milliseconds(1))
        for _ in 0..<ProcessLiveModel.resortEvery { live.apply(back, snapshot: nil, net: [:]) }
        XCTAssertEqual(order(live), ["A.app", "B.app"])
    }

    func testSortChangeAndQueryResortImmediately() {
        let live = ProcessLiveModel()
        let a = "/Applications/A.app", b = "/Applications/B.app"
        live.apply(snapshot([a: 3_000_000_000, b: 1_000_000_000]), snapshot: nil, net: [:])
        live.sortColumn = .name
        live.sortAscending = false
        XCTAssertEqual(order(live), ["B.app", "A.app"], "sütun/yön değişimi hemen uygulanır")
        live.query = "A"
        XCTAssertEqual(order(live), ["A.app"])
    }

    func testNewRowsAppearAtTheirSortedPositionWithoutReshufflingOthers() {
        let live = ProcessLiveModel()
        let a = "/Applications/A.app", b = "/Applications/B.app", c = "/Applications/C.app"
        live.apply(snapshot([a: 5_000_000_000, c: 1_000_000_000]), snapshot: nil, net: [:])
        live.apply(snapshot([a: 1_000_000_000, c: 5_000_000_000, b: 3_000_000_000]), snapshot: nil, net: [:])
        XCTAssertEqual(order(live), ["A.app", "B.app", "C.app"], "A ve C eski sırada; yeni B sıralı konumunda (A'dan sonra, C'den önce)")
    }

    func testHeatTintIsStableAtZeroAndQuantized() {
        XCTAssertEqual(HeatTint.quantized(0), 0)
        XCTAssertEqual(HeatTint.quantized(0.51), HeatTint.quantized(0.52), accuracy: 0.0001, "ufak dalgalanma aynı basamağa düşer")
    }
}
