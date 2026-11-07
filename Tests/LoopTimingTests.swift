import XCTest
@testable import Adalmon

/// Döngü zamanlaması (saf mantık): kırpma aralığı, kısa video kıskacı, geçiş süresi, hazırlık zamanı.
final class LoopTimingTests: XCTestCase {
    private let timing = LoopTiming(trimStart: 5, trimEnd: 3, crossfade: 1.5)

    func testDefaults() {
        XCTAssertEqual(LoopTiming.default, LoopTiming(trimStart: 5, trimEnd: 3, crossfade: 1.5))
        XCTAssertEqual(LoopSettings().trimStart, 5)
        XCTAssertEqual(LoopSettings().trimEnd, 3)
        XCTAssertEqual(LoopSettings().transition, .crossfade)
        XCTAssertEqual(LoopSettings().crossfadeSeconds, 1.5)
    }

    func testTrimmedRangeForLongVideo() {
        let r = timing.range(duration: 60)
        XCTAssertEqual(r.start, 5)
        XCTAssertEqual(r.end, 57)
        XCTAssertEqual(r.length, 52)
        XCTAssertTrue(r.isTrimmed)
        XCTAssertTrue(r.isKnown)
    }

    func testShortVideoIgnoresTrimsExactlyAtBoundary() {
        // eşik: süre < baştan + sondan + 10 = 18
        let below = timing.range(duration: 17.99)
        XCTAssertFalse(below.isTrimmed)
        XCTAssertEqual(below.start, 0)
        XCTAssertEqual(below.end, 17.99, accuracy: 1e-9)
        let at = timing.range(duration: 18)
        XCTAssertTrue(at.isTrimmed)
        XCTAssertEqual(at.start, 5)
        XCTAssertEqual(at.end, 15)
        XCTAssertEqual(at.length, 10, accuracy: 1e-9)
    }

    func testZeroTrimsAreNeverTrimmed() {
        let r = LoopTiming(trimStart: 0, trimEnd: 0, crossfade: 1).range(duration: 4)
        XCTAssertFalse(r.isTrimmed)
        XCTAssertEqual(r.length, 4)
    }

    func testUnknownDurationMeansNoTrimAndNoFade() {
        for d in [nil, 0, -3, .nan, .infinity] as [Double?] {
            let r = timing.range(duration: d)
            XCTAssertFalse(r.isKnown, "\(String(describing: d))")
            XCTAssertFalse(r.isTrimmed)
            XCTAssertEqual(timing.fade(in: r, reduceMotion: false), 0)
            XCTAssertNil(timing.prepareTime(in: r, fade: 0))
        }
    }

    func testFadeIsClampedToQuarterOfRange() {
        let long = timing.range(duration: 60)
        XCTAssertEqual(timing.fade(in: long, reduceMotion: false), 1.5)
        let tenSeconds = timing.range(duration: 18)             // aralık 10 sn → en çok 2,5 sn
        XCTAssertEqual(LoopTiming(trimStart: 5, trimEnd: 3, crossfade: 3).fade(in: tenSeconds, reduceMotion: false), 2.5, accuracy: 1e-9)
        let fiveSeconds = LoopTiming(trimStart: 0, trimEnd: 0, crossfade: 3).range(duration: 5)
        XCTAssertEqual(LoopTiming(trimStart: 0, trimEnd: 0, crossfade: 3).fade(in: fiveSeconds, reduceMotion: false), 1.25, accuracy: 1e-9)
    }

    func testVeryShortRangesNeverCrossfade() {
        let t = LoopTiming(trimStart: 0, trimEnd: 0, crossfade: 1.5)
        XCTAssertEqual(t.fade(in: t.range(duration: 2.99), reduceMotion: false), 0)
        XCTAssertGreaterThan(t.fade(in: t.range(duration: 3), reduceMotion: false), 0)
        XCTAssertEqual(t.fade(in: t.range(duration: 0.4), reduceMotion: false), 0, "minik test klipleri geçiş yapmaz")
    }

    func testCrossfadeOffMeansZeroFade() {
        let t = LoopTiming(trimStart: 5, trimEnd: 3, crossfade: 0)
        XCTAssertEqual(t.fade(in: t.range(duration: 60), reduceMotion: false), 0)
    }

    func testReduceMotionUsesShortDissolve() {
        XCTAssertEqual(timing.fade(in: timing.range(duration: 60), reduceMotion: true), 0.3, accuracy: 1e-9)
        // geçiş kapalıysa Hareketi Azalt bir şey eklemez
        let off = LoopTiming(trimStart: 5, trimEnd: 3, crossfade: 0)
        XCTAssertEqual(off.fade(in: off.range(duration: 60), reduceMotion: true), 0)
    }

    func testPrepareTimeIsFadePlusPrerollBeforeEnd() throws {
        let r = timing.range(duration: 60)                      // 5…57
        let fade = timing.fade(in: r, reduceMotion: false)
        XCTAssertEqual(try XCTUnwrap(timing.prepareTime(in: r, fade: fade)), 57 - 1.5 - LoopTiming.preroll, accuracy: 1e-9)
        // hard geçiş (fade 0): yalnızca ön hazırlık
        XCTAssertEqual(try XCTUnwrap(timing.prepareTime(in: r, fade: 0)), 57 - LoopTiming.preroll, accuracy: 1e-9)
        // asla aralığın başından önce olmaz
        let tiny = LoopTiming.none.range(duration: 0.3)
        XCTAssertEqual(try XCTUnwrap(LoopTiming.none.prepareTime(in: tiny, fade: 0)), 0, accuracy: 1e-9)
    }

    func testLooperOnlyForSingleClipWithoutCrossfade() {
        let off = LoopTiming(trimStart: 5, trimEnd: 3, crossfade: 0)
        XCTAssertTrue(off.usesLooper(clipCount: 1))
        XCTAssertFalse(off.usesLooper(clipCount: 2), "oynatma listesi: iki örnekli sert geçiş")
        XCTAssertFalse(timing.usesLooper(clipCount: 1))
    }

    func testNextIndexWraps() {
        XCTAssertEqual(LoopTiming.nextIndex(after: 0, count: 3), 1)
        XCTAssertEqual(LoopTiming.nextIndex(after: 2, count: 3), 0)
        XCTAssertEqual(LoopTiming.nextIndex(after: 0, count: 1), 0)
        XCTAssertEqual(LoopTiming.nextIndex(after: 5, count: 0), 0)
    }

    func testSanitizedClampsGarbage() {
        let bad = LoopTiming(trimStart: -4, trimEnd: .nan, crossfade: 99).sanitized
        XCTAssertEqual(bad.trimStart, 0)
        XCTAssertEqual(bad.trimEnd, LoopTiming.default.trimEnd)
        XCTAssertEqual(bad.crossfade, 3)
        XCTAssertEqual(LoopTiming(trimStart: 100, trimEnd: 0, crossfade: 0.1).sanitized.trimStart, 30)
        XCTAssertEqual(LoopTiming(trimStart: 0, trimEnd: 0, crossfade: 0.1).sanitized.crossfade, 0.5)
        XCTAssertEqual(LoopTiming(trimStart: 0, trimEnd: 0, crossfade: 0).sanitized.crossfade, 0, "0 = kapalı korunur")
    }

    func testLoopSettingsMapToTiming() {
        var s = LoopSettings()
        XCTAssertEqual(s.timing, .default)
        s.transition = .off
        XCTAssertEqual(s.timing.crossfade, 0)
        XCTAssertEqual(s.crossfadeSeconds, 1.5, "kapalıyken süre saklanır")
    }
}
