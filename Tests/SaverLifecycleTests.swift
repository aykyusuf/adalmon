import XCTest
@testable import Adalmon

/// Ekran koruyucu örnek kaydı (saf mantık): yığılma, çoklu ekran, önizleme, süreç kapatma koşulları.
final class SaverLifecycleTests: XCTestCase {
    func testNewFullInstanceOnSameScreenEvictsOldOne() {
        var r = SaverLifecycleRegistry()
        XCTAssertTrue(r.register(token: 1, screenKey: "display-1", isPreview: false).isEmpty)
        XCTAssertEqual(r.register(token: 2, screenKey: "display-1", isPreview: false), [1])
        XCTAssertEqual(r.entries.keys.sorted(), [2])
    }

    func testOtherScreensAreNotEvicted() {
        var r = SaverLifecycleRegistry()
        _ = r.register(token: 1, screenKey: "display-1", isPreview: false)
        XCTAssertTrue(r.register(token: 2, screenKey: "display-2", isPreview: false).isEmpty)
        XCTAssertEqual(r.runningCount, 2)
        // Ekranı bilinmeyen örnekler benzersiz anahtar kullanır: birbirini atmaz
        XCTAssertTrue(r.register(token: 3, screenKey: "view-3", isPreview: false).isEmpty)
        XCTAssertTrue(r.register(token: 4, screenKey: "view-4", isPreview: false).isEmpty)
    }

    func testPreviewReplacesOnlyPreviewAndNeverFullInstances() {
        var r = SaverLifecycleRegistry()
        _ = r.register(token: 1, screenKey: "display-1", isPreview: false)
        _ = r.register(token: 2, screenKey: "p", isPreview: true)
        XCTAssertEqual(r.register(token: 3, screenKey: "p", isPreview: true), [2])
        XCTAssertEqual(r.entries.keys.sorted(), [1, 3])
    }

    func testWillStopStopsFullInstancesButLeavesPreview() {
        var r = SaverLifecycleRegistry()
        _ = r.register(token: 1, screenKey: "display-1", isPreview: false)
        _ = r.register(token: 2, screenKey: "display-2", isPreview: false)
        _ = r.register(token: 3, screenKey: "p", isPreview: true)
        XCTAssertEqual(r.hostWillStop(), [1, 2])
        XCTAssertEqual(r.hostWillStop(), [], "ikinci willstop yeni iş çıkarmaz")
        XCTAssertEqual(r.runningCount, 1)
    }

    func testHostExitOnlyAfterFullRunWithNothingRunningAndNoPreview() {
        var r = SaverLifecycleRegistry()
        XCTAssertFalse(r.canExitHost(enabled: true), "hiç çalıştırma görülmedi")
        _ = r.register(token: 1, screenKey: "display-1", isPreview: false)
        XCTAssertFalse(r.canExitHost(enabled: true), "hâlâ çalışıyor")
        for t in r.hostWillStop() { r.remove(token: t) }
        XCTAssertTrue(r.canExitHost(enabled: true))
        XCTAssertFalse(r.canExitHost(enabled: false), "kullanıcı kapattı")
        _ = r.register(token: 2, screenKey: "p", isPreview: true)
        XCTAssertFalse(r.canExitHost(enabled: true), "Ayarlar önizlemesi açık: süreç kapatılmaz")
    }

    func testPreviewOnlySessionNeverExits() {
        var r = SaverLifecycleRegistry()
        _ = r.register(token: 1, screenKey: "p", isPreview: true)
        r.remove(token: 1)
        XCTAssertFalse(r.canExitHost(enabled: true))
    }

    func testReclassifyZeroFrameInstanceToFull() {
        var r = SaverLifecycleRegistry()
        _ = r.register(token: 1, screenKey: "view-1", isPreview: true)
        r.reclassify(token: 1, isPreview: false)
        XCTAssertEqual(r.previewCount, 0)
        XCTAssertTrue(r.sawFullRun)
    }

    func testPreviewHeuristic() {
        XCTAssertTrue(SaverPreviewHeuristic.isPreview(flag: true, size: CGSize(width: 3840, height: 2160)))
        XCTAssertTrue(SaverPreviewHeuristic.isPreview(flag: false, size: .zero), "0x0 çerçeveli önizleme hatası")
        XCTAssertTrue(SaverPreviewHeuristic.isPreview(flag: false, size: CGSize(width: 296, height: 184)))
        XCTAssertFalse(SaverPreviewHeuristic.isPreview(flag: false, size: CGSize(width: 1512, height: 982)))
    }
}
