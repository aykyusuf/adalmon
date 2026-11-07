import XCTest
@testable import Adalmon

/// Etkileşimli grafik mantığı: en yakın örnek, ort/min/maks özeti, ipucu satırları, yapay örnek ekseni, geçmiş tamponu.
@MainActor
final class ChartInteractionTests: XCTestCase {
    private func points(_ values: [Double], step: TimeInterval = 10) -> [ChartPoint] {
        values.enumerated().map { ChartPoint(date: Date(timeIntervalSince1970: 1_000 + Double($0.offset) * step), value: $0.element) }
    }

    func testNearestPicksClosestSampleAndRespectsTolerance() {
        let p = points([1, 2, 3, 4])
        func t(_ s: Double) -> Date { Date(timeIntervalSince1970: 1_000 + s) }
        XCTAssertEqual(ChartNearest.index(in: p, to: t(0)), 0)
        XCTAssertEqual(ChartNearest.index(in: p, to: t(14)), 1)
        XCTAssertEqual(ChartNearest.index(in: p, to: t(16)), 2)
        XCTAssertEqual(ChartNearest.index(in: p, to: t(29)), 3)
        XCTAssertEqual(ChartNearest.index(in: p, to: t(500)), 3, "tolerans yoksa en yakın uç")
        XCTAssertNil(ChartNearest.index(in: p, to: t(500), tolerance: ChartNearest.tolerance(for: p)), "veri olmayan boş alan")
        XCTAssertNil(ChartNearest.index(in: [], to: t(0)))
        XCTAssertEqual(ChartNearest.index(in: p, to: t(-100)), 0)
    }

    func testStatsAndSummaryText() throws {
        let stats = try XCTUnwrap(ChartStats(values: [21.5, 33.4, 26.4, 27.1]))
        XCTAssertEqual(stats.minimum, 21.5)
        XCTAssertEqual(stats.maximum, 33.4)
        XCTAssertEqual(stats.average, 27.1, accuracy: 0.001)
        XCTAssertEqual(stats.text { String(format: "%.1f", $0) }, "27.1 Ort · 21.5 Min · 33.4 Maks")
        XCTAssertNil(ChartStats(values: []))
    }

    func testReadoutListsEverySeriesAtTheNearestPoint() throws {
        let down = ChartLine(name: "İndirme", color: .blue, points: points([100, 200, 300]))
        let up = ChartLine(name: "Yükleme", color: .orange, points: points([1, 2, 3]))
        let r = try XCTUnwrap(ChartReadout.make(lines: [down, up], at: Date(timeIntervalSince1970: 1_011), title: { _ in "t" }, value: { "\(Int($0))" }))
        XCTAssertEqual(r.rows.map(\.text), ["200", "2"])
        XCTAssertEqual(r.rows.map(\.name), ["İndirme", "Yükleme"])
        XCTAssertEqual(r.rows.first?.date, Date(timeIntervalSince1970: 1_010))
        XCTAssertNil(ChartReadout.make(lines: [down], at: Date(timeIntervalSince1970: 9_000), title: { _ in "" }, value: { _ in "" }))
    }

    func testSampleAxisPlacesNewestAtRightAndFormatsAge() {
        let pts = SampleAxis.points([1, 2, 3], capacity: 60)
        XCTAssertEqual(pts.last?.date, SampleAxis.date(59))
        XCTAssertEqual(pts.first?.date, SampleAxis.date(57))
        XCTAssertEqual(SampleAxis.ageText(of: SampleAxis.date(59), count: 3, secondsPerPoint: 2), "şimdi")
        XCTAssertEqual(SampleAxis.ageText(of: SampleAxis.date(57), count: 3, secondsPerPoint: 2), "~4 sn önce")
        XCTAssertEqual(SampleAxis.ageText(of: SampleAxis.date(0), count: 60, secondsPerPoint: 3), "~2 dk önce")
    }

    // MARK: Geçmiş tamponu

    private func sample(_ t: Double, cpu: Double = 0.1) -> SystemSample {
        SystemSample(time: Date(timeIntervalSince1970: t), cpu: cpu, memory: 0.5, gpu: 0.2, diskRead: 10, diskWrite: 20, down: 30, up: 40)
    }

    func testRingKeepsLastCapacitySamplesInOrder() {
        let ring = SystemHistoryBuffer(capacity: 5)
        for i in 1...8 { ring.append(sample(Double(i), cpu: Double(i) / 10), notify: false) }
        XCTAssertEqual(ring.count, 5)
        XCTAssertEqual(ring.samples().map(\.time.timeIntervalSince1970), [4, 5, 6, 7, 8])
        XCTAssertEqual(ring.recentValues(.cpu, count: 2), [0.7, 0.8])
        XCTAssertEqual(ring.samples(window: 2).map(\.time.timeIntervalSince1970), [6, 7, 8], "pencere en yeni örneğe göre")
        XCTAssertEqual(ring.recentValues(.disk, count: 1), [30])
        XCTAssertEqual(ring.recentValues(.network, count: 1), [70])
    }

    func testRingIgnoresDuplicateTimestampsAndOnlyNotifiesWhenAsked() {
        let ring = SystemHistoryBuffer(capacity: 4)
        ring.append(sample(1), notify: true)
        ring.append(sample(1), notify: true)
        XCTAssertEqual(ring.count, 1)
        XCTAssertEqual(ring.revision, 1)
        ring.append(sample(2), notify: false)
        XCTAssertEqual(ring.revision, 1, "gizliyken görünümler uyandırılmaz")
        XCTAssertEqual(ring.latestTime, Date(timeIntervalSince1970: 2))
    }

    func testLiveSeriesUseRealTimestamps() {
        let samples = [sample(100), sample(101), sample(105)]
        let cpu = PerformanceSeriesBuilder.live(metric: .cpu, samples: samples)
        XCTAssertEqual(cpu.first?.points.map(\.date.timeIntervalSince1970), [100, 101, 105])
        XCTAssertEqual(cpu.first?.points.first?.value ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(PerformanceSeriesBuilder.live(metric: .network, samples: samples).map(\.name), ["İndirme", "Yükleme"])
    }
}
