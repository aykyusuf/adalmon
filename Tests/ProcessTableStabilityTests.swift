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

/// Kullanıcı sütun düzeni: sırala / gizle / sıfırla / kalıcılık (saf mantık).
@MainActor
final class ProcessColumnLayoutTests: XCTestCase {
    private let wide: CGFloat = 2_200
    private let narrow: CGFloat = 900

    func testDefaultMatchesLegacyLayoutAtEveryWidth() {
        XCTAssertEqual(ProcessColumnLayout.defaultOrder,
                       ProcessTableLayout.numericColumns + ProcessTableLayout.extraColumnThresholds.map(\.column))
        for w in stride(from: CGFloat(0), through: 3_000, by: 41) {
            let legacyMetrics = ProcessTableLayout.numericColumns + ProcessTableLayout.extraColumnThresholds.filter { w >= $0.minWidth }.map(\.column)
            XCTAssertEqual(ProcessTableLayout.columns(forWidth: w, layout: .default).entries.map(\.column), legacyMetrics, "\(w)")
        }
    }

    func testMoveBeforeAfterAndToFront() {
        var l = ProcessColumnLayout.default
        l.move(.gpu, before: .cpu)
        XCTAssertEqual(Array(l.order.prefix(3)), [.gpu, .cpu, .memory])
        l.move(.gpu, after: .memory)
        XCTAssertEqual(Array(l.order.prefix(3)), [.cpu, .memory, .gpu])
        l.move(.pid, before: .name)
        XCTAssertEqual(l.order.first, .pid)
        l.move(.pid, before: nil)
        XCTAssertEqual(l.order.last, .pid)
        l.move(.cpu, after: .pid)
        XCTAssertEqual(l.order.last, .cpu)
        XCTAssertEqual(Set(l.order).count, l.order.count, "her sütun bir kez")
        XCTAssertFalse(l.order.contains(.name))
    }

    func testReorderIsReflectedInComputedColumnsForHeaderAndRows() {
        var l = ProcessColumnLayout.default
        l.move(.energy, before: .cpu)
        let c = ProcessTableLayout.columns(forWidth: narrow, layout: l)
        XCTAssertEqual(c.entries.first?.column, .energy)
        XCTAssertEqual(c.entries.first?.width, ProcessTableLayout.columns(forWidth: narrow).entries.first { $0.column == .energy }?.width,
                       "genişlik sütunla birlikte taşınır")
    }

    func testMoveLeftRightSkipsInvisibleColumns() {
        var l = ProcessColumnLayout.default
        l.setVisible(.memory, false)
        XCTAssertFalse(l.canMoveLeft(.cpu, width: narrow))
        l.moveLeft(.disk, width: narrow)
        XCTAssertEqual(l.visibleColumns(width: narrow).prefix(2), [.disk, .cpu])
        l.moveRight(.disk, width: narrow)
        XCTAssertEqual(l.visibleColumns(width: narrow).prefix(2), [.cpu, .disk])
        // Dar pencerede bilgi sütunları görünmez: Enerji en sağdadır.
        XCTAssertFalse(l.canMoveRight(.energy, width: narrow))
        XCTAssertTrue(l.canMoveRight(.energy, width: wide))
        let before = l
        l.moveRight(.energy, width: narrow)
        XCTAssertEqual(l, before)
    }

    func testHideShowAndNameCannotBeHidden() {
        var l = ProcessColumnLayout.default
        l.setVisible(.gpu, false)
        XCTAssertFalse(l.isVisible(.gpu, width: wide))
        XCTAssertFalse(ProcessTableLayout.columns(forWidth: wide, layout: l).entries.contains { $0.column == .gpu })
        l.setVisible(.gpu, true)
        XCTAssertTrue(l.isVisible(.gpu, width: narrow))
        l.setVisible(.name, false)
        XCTAssertTrue(l.isVisible(.name, width: narrow))
    }

    func testInfoColumnsAutoByWidthUntilUserDecides() {
        var l = ProcessColumnLayout.default
        XCTAssertFalse(l.isVisible(.pid, width: narrow))
        XCTAssertTrue(l.isVisible(.pid, width: wide))
        l.setVisible(.pid, true)
        XCTAssertTrue(l.isVisible(.pid, width: narrow), "açıkça açılan bilgi sütunu dar pencerede de görünür")
        l.setVisible(.processCount, false)
        XCTAssertFalse(l.isVisible(.processCount, width: wide))
    }

    func testAllColumnsHiddenLeavesOnlyNameWithoutNaN() {
        var l = ProcessColumnLayout.default
        for c in l.order { l.setVisible(c, false) }
        for w in [CGFloat(0), 300, 900, 2_200] {
            let c = ProcessTableLayout.columns(forWidth: w, layout: l)
            XCTAssertTrue(c.entries.isEmpty)
            XCTAssertFalse(c.nameWidth.isNaN)
            XCTAssertLessThanOrEqual(c.totalWidth, w + 0.5)
        }
    }

    func testCustomLayoutNeverExceedsWidth() {
        var l = ProcessColumnLayout.default
        l.setVisible(.pid, true)
        l.setVisible(.category, true)
        l.move(.pid, before: .cpu)
        for w in stride(from: CGFloat(300), through: 3_000, by: 53) {
            XCTAssertLessThanOrEqual(ProcessTableLayout.columns(forWidth: w, layout: l).totalWidth, w + 0.5, "\(w)")
        }
    }

    func testResetRestoresDefault() {
        var l = ProcessColumnLayout.default
        l.move(.gpu, before: .cpu)
        l.setVisible(.disk, false)
        XCTAssertFalse(l.isDefault)
        l.reset()
        XCTAssertEqual(l, .default)
        XCTAssertTrue(l.isDefault)
    }

    func testSortFallbackWhenSortColumnHidden() {
        var l = ProcessColumnLayout.default
        XCTAssertNil(l.sortFallback(for: .gpu, width: narrow))
        l.setVisible(.gpu, false)
        XCTAssertEqual(l.sortFallback(for: .gpu, width: narrow), .cpu)
        l.setVisible(.cpu, false)
        XCTAssertEqual(l.sortFallback(for: .gpu, width: narrow), .name)
        XCTAssertNil(l.sortFallback(for: .name, width: narrow))
    }

    func testCodableRoundTrip() throws {
        var l = ProcessColumnLayout.default
        l.move(.network, before: .cpu)
        l.setVisible(.energy, false)
        l.setVisible(.pid, true)
        let data = try XCTUnwrap(l.encoded())
        XCTAssertEqual(ProcessColumnLayout.decode(data), l)
    }

    func testCorruptOrMissingDataFallsBackToDefault() {
        XCTAssertEqual(ProcessColumnLayout.decode(nil), .default)
        XCTAssertEqual(ProcessColumnLayout.decode(Data("çöp".utf8)), .default)
        XCTAssertEqual(ProcessColumnLayout.decode(Data("{}".utf8)), .default)
        XCTAssertEqual(ProcessColumnLayout.decode(Data(#"{"order":["yok","bilinmez"]}"#.utf8)), .default)
        XCTAssertEqual(ProcessColumnLayout.decode(Data(#"{"order":42}"#.utf8)), .default)
    }

    func testOldRecordGetsMissingColumnsAppendedAndJunkDropped() {
        // Eski sürüm: yalnızca birkaç sütun, yinelenen, bilinmeyen ve "name" içeriyor.
        let json = #"{"version":1,"order":["gpu","cpu","gpu","name","eskiSutun"],"hidden":["name","disk","yok"],"shown":["cpu","pid"]}"#
        let l = ProcessColumnLayout.decode(Data(json.utf8))
        XCTAssertEqual(Array(l.order.prefix(2)), [.gpu, .cpu])
        XCTAssertEqual(Array(l.order.dropFirst(2)), [.memory, .disk, .network, .energy, .processCount, .category, .pid],
                       "kayıtta olmayan sütunlar varsayılan sırayla sona")
        XCTAssertFalse(l.order.contains(.name))
        XCTAssertTrue(l.isVisible(.name, width: 0))
        XCTAssertFalse(l.isVisible(.disk, width: wide))
        XCTAssertTrue(l.isVisible(.pid, width: narrow))
        XCTAssertTrue(l.isVisible(.cpu, width: narrow))
    }

    func testPersistenceInUserDefaults() throws {
        let suite = "ProcessColumnLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ProcessColumnLayout.load(from: defaults), .default)
        var l = ProcessColumnLayout.default
        l.move(.memory, before: .cpu)
        l.save(to: defaults)
        XCTAssertEqual(ProcessColumnLayout.load(from: defaults), l)
        defaults.set(Data([0xFF, 0x00]), forKey: ProcessColumnLayout.defaultsKey)
        XCTAssertEqual(ProcessColumnLayout.load(from: defaults), .default)
        ProcessColumnLayout.default.save(to: defaults)
        XCTAssertNil(defaults.data(forKey: ProcessColumnLayout.defaultsKey), "varsayılan kaydedilmez")
    }
}
