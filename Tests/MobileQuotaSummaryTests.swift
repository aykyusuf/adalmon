import XCTest
@testable import Adalmon

final class MobileQuotaSummaryTests: XCTestCase {
    func testWithoutBudgetUsesDailyCap() {
        var data = PanelData()
        data.mobileToday = 1_240_000_000
        data.dailyCapBytes = 3_000_000_000
        let q = MobileQuotaSummary(data)
        XCTAssertEqual(q.capBytes, 3_000_000_000)
        XCTAssertEqual(q.percentText, "%41")
        XCTAssertEqual(q.usageText, "1,24 / 3 GB")
        XCTAssertNil(q.etaText())
        XCTAssertEqual(q.level, .normal)
    }

    func testEtaTextAndLevels() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let at = cal.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 21, minute: 40))!
        var q = MobileQuotaSummary(usedBytes: 2_500_000_000, capBytes: 3_000_000_000, eta: .at(at))
        XCTAssertEqual(q.level, .warning)
        XCTAssertTrue(q.isUrgent)
        XCTAssertNotNil(q.etaText())
        q.eta = .reached
        q.usedBytes = 3_100_000_000
        XCTAssertEqual(q.level, .critical)
        XCTAssertEqual(q.etaText(), "Limit doldu")
        q.eta = .notToday
        XCTAssertNil(q.etaText())
        XCTAssertFalse(q.isUrgent)
    }

    /// Günlük limit esas (2026-11-12): aylık tempo daha düşük olsa da tahmin günlük limite göre.
    func testDailyCapETAWinsOverMonthlyPace() {
        var b = BudgetSnapshot.sample
        b.dynamicDailyBudgetBytes = 500_000_000
        b.effectiveDailyCapBytes = 500_000_000
        b.etaBudgetRecentRate = .reached
        b.etaRecentRate = .notToday
        var data = PanelData()
        data.dailyCapBytes = 3_000_000_000
        data.budget = b
        XCTAssertEqual(MobileQuotaSummary(data).eta, .notToday)
        b.dynamicDailyBudgetBytes = 5_000_000_000
        data.budget = b
        XCTAssertEqual(MobileQuotaSummary(data).eta, .notToday)
    }

    func testSplitRate() {
        XCTAssertEqual(PanelCardModel.splitRate("12,4 MB/s").0, "12,4")
        XCTAssertEqual(PanelCardModel.splitRate("12,4 MB/s").1, "MB/s")
        XCTAssertEqual(PanelCardModel.splitRate("0 B/s").1, "B/s")
    }

    func testCardModelsForSample() {
        for kind in PanelCardKind.allCases {
            let card = PanelCardModel.make(kind, .sample)
            XCTAssertFalse(card.value.isEmpty, "\(kind)")
            XCTAssertFalse(card.accessibilityLabel.isEmpty, "\(kind)")
        }
        XCTAssertEqual(PanelCardModel.make(.cpu, .sample).value, "%23")
        XCTAssertEqual(PanelCardModel.make(.temperature, .sample).value, "54°")
        let empty = PanelCardModel.make(.temperature, PanelData())
        XCTAssertEqual(empty.value, "—")
    }

    func testTemperatureCardShowsCPUGPUBatteryAverages() {
        let card = PanelCardModel.make(.temperature, .sample)
        XCTAssertEqual(card.value, "54°")
        XCTAssertEqual(card.unit, "CPU")
        XCTAssertEqual(card.caption, "GPU 48° · Pil 31°")
        XCTAssertEqual(card.accessibilityLabel,
                       "Sıcaklık, işlemci ortalama 54 derece, ekran kartı ortalama 48 derece, pil 31 derece")

        var noGPU = PanelData.sample
        noGPU.snapshot?.temperature?.gpu = nil
        XCTAssertEqual(PanelCardModel.make(.temperature, noGPU).caption, "Pil 31°")
        noGPU.snapshot?.temperature?.battery = nil
        let bare = PanelCardModel.make(.temperature, noGPU)
        XCTAssertEqual(bare.caption, "")
        XCTAssertEqual(bare.accessibilityLabel, "Sıcaklık, işlemci ortalama 54 derece")
    }
}
