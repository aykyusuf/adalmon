import XCTest
@testable import Adalmon

/// Duraklatma kuralları durum makinesi: girdiler (pil, düşük güç, masaüstü görünür, kilit, ekran uykusu, tam ekran, elle karar) → oynat / duraklat.
final class WallpaperPolicyTests: XCTestCase {
    private let all = WallpaperPauseRules()

    private func decide(_ edit: (inout WallpaperPolicyInput) -> Void = { _ in }, rules: WallpaperPauseRules? = nil,
                        override: WallpaperUserOverride = .auto) -> WallpaperDecision {
        var input = WallpaperPolicyInput()
        edit(&input)
        return WallpaperPolicy.decide(input, rules: rules ?? all, override: override)
    }

    func testDefaultsAreAllOn() {
        XCTAssertTrue(all.pauseOnBattery && all.pauseOnLowPower && all.pauseWhenDesktopHidden)
    }

    func testPlaysWhenNothingIsWrong() {
        XCTAssertEqual(decide(), .play)
    }

    func testEachConditionPausesWithItsReason() {
        XCTAssertEqual(decide { $0.onBattery = true }, .pause(.battery))
        XCTAssertEqual(decide { $0.lowPower = true }, .pause(.lowPower))
        XCTAssertEqual(decide { $0.desktopVisible = false }, .pause(.covered))
        XCTAssertEqual(decide { $0.locked = true }, .pause(.locked))
        XCTAssertEqual(decide { $0.displayAsleep = true }, .pause(.displayAsleep))
        XCTAssertEqual(decide { $0.fullScreen = true }, .pause(.fullScreen))
    }

    func testEachRuleCanBeTurnedOffSeparately() {
        var noBattery = all; noBattery.pauseOnBattery = false
        XCTAssertEqual(decide({ $0.onBattery = true }, rules: noBattery), .play)
        XCTAssertEqual(decide({ $0.lowPower = true }, rules: noBattery), .pause(.lowPower))

        var noLPM = all; noLPM.pauseOnLowPower = false
        XCTAssertEqual(decide({ $0.lowPower = true }, rules: noLPM), .play)
        XCTAssertEqual(decide({ $0.onBattery = true }, rules: noLPM), .pause(.battery))

        var noHidden = all; noHidden.pauseWhenDesktopHidden = false
        for edit: (inout WallpaperPolicyInput) -> Void in [{ $0.desktopVisible = false }, { $0.fullScreen = true }, { $0.locked = true }, { $0.displayAsleep = true }] {
            XCTAssertEqual(decide(edit, rules: noHidden), .play)
        }
        XCTAssertEqual(decide({ $0.onBattery = true }, rules: noHidden), .pause(.battery))
    }

    func testAllRulesOffAlwaysPlays() {
        let off = WallpaperPauseRules(pauseOnBattery: false, pauseOnLowPower: false, pauseWhenDesktopHidden: false)
        let result = decide({ $0.onBattery = true; $0.lowPower = true; $0.desktopVisible = false; $0.locked = true; $0.displayAsleep = true; $0.fullScreen = true }, rules: off)
        XCTAssertEqual(result, .play)
    }

    func testPriorityOrder() {
        // Ekran uykuda her şeyden önce; sonra kilit; sonra pil; sonra Düşük Güç; sonra tam ekran; sonra örtülme.
        XCTAssertEqual(decide { $0 = WallpaperPolicyInput(onBattery: true, lowPower: true, desktopVisible: false, locked: true, displayAsleep: true, fullScreen: true) }, .pause(.displayAsleep))
        XCTAssertEqual(decide { $0 = WallpaperPolicyInput(onBattery: true, lowPower: true, desktopVisible: false, locked: true, displayAsleep: false, fullScreen: true) }, .pause(.locked))
        XCTAssertEqual(decide { $0 = WallpaperPolicyInput(onBattery: true, lowPower: true, desktopVisible: false, fullScreen: true) }, .pause(.battery))
        XCTAssertEqual(decide { $0 = WallpaperPolicyInput(lowPower: true, desktopVisible: false, fullScreen: true) }, .pause(.lowPower))
        XCTAssertEqual(decide { $0 = WallpaperPolicyInput(desktopVisible: false, fullScreen: true) }, .pause(.fullScreen))
    }

    func testUserOverrides() {
        XCTAssertEqual(decide(override: .forcePause), .pause(.user))
        XCTAssertEqual(decide({ $0.onBattery = true }, override: .forcePause), .pause(.user))
        // "Yine de oynat": pil ve Düşük Güç yok sayılır.
        XCTAssertEqual(decide({ $0.onBattery = true; $0.lowPower = true }, override: .forcePlay), .play)
        // ...ama kilitli / uykudaki ekranda yine de durur (kimse görmüyor).
        XCTAssertEqual(decide({ $0.locked = true }, override: .forcePlay), .pause(.locked))
        XCTAssertEqual(decide({ $0.displayAsleep = true }, override: .forcePlay), .pause(.displayAsleep))
        // ...örtülü masaüstü kuralı açıksa yine durur.
        XCTAssertEqual(decide({ $0.onBattery = true; $0.desktopVisible = false }, override: .forcePlay), .pause(.covered))
    }

    func testStatusTextsAreTurkish() {
        XCTAssertEqual(WallpaperPauseReason.battery.statusText, "Duraklatıldı: pilde")
        XCTAssertEqual(WallpaperPauseReason.lowPower.statusText, "Duraklatıldı: Düşük Güç Modu")
    }

    func testRulesCodableRoundTrip() throws {
        var r = WallpaperPauseRules(); r.pauseOnLowPower = false
        let back = try JSONDecoder().decode(WallpaperPauseRules.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
    }
}

struct SplitMix64: RandomNumberGenerator, Sendable {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class PlaylistRotationTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    func testSingleModeNeverAdvances() {
        var r = PlaylistRotation(ids: [a, b, c], mode: .single, current: b, rng: SplitMix64(state: 1))
        XCTAssertEqual(r.advance(), b)
        XCTAssertEqual(r.advance(), b)
    }

    func testSequenceWraps() {
        var r = PlaylistRotation(ids: [a, b, c], mode: .sequence, current: a, rng: SplitMix64(state: 1))
        XCTAssertEqual([r.advance(), r.advance(), r.advance(), r.advance()], [b, c, a, b])
    }

    func testShuffleVisitsEveryItemPerRoundWithoutImmediateRepeat() {
        var r = PlaylistRotation(ids: [a, b, c], mode: .shuffle, current: a, rng: SplitMix64(state: 42))
        var seq: [UUID] = [a]
        for _ in 0..<30 { seq.append(r.advance()!) }
        for (x, y) in zip(seq, seq.dropFirst()) { XCTAssertNotEqual(x, y) }
        // İlk üç çekiliş bir tur: hepsi farklı.
        XCTAssertEqual(Set(seq[1...3]).count, 3)
    }

    func testShuffleIsDeterministicForSameSeed() {
        var x = PlaylistRotation(ids: [a, b, c], mode: .shuffle, rng: SplitMix64(state: 7))
        var y = PlaylistRotation(ids: [a, b, c], mode: .shuffle, rng: SplitMix64(state: 7))
        XCTAssertEqual((0..<9).map { _ in x.advance() }, (0..<9).map { _ in y.advance() })
    }

    func testEmptyAndSingleItem() {
        var empty = PlaylistRotation(ids: [], mode: .sequence, rng: SplitMix64(state: 1))
        XCTAssertNil(empty.advance())
        var one = PlaylistRotation(ids: [a], mode: .shuffle, rng: SplitMix64(state: 1))
        XCTAssertEqual(one.advance(), a)
    }

    func testRemovingCurrentFallsBackToFirst() {
        var r = PlaylistRotation(ids: [a, b, c], mode: .sequence, current: c, rng: SplitMix64(state: 1))
        r.update(ids: [a, b])
        XCTAssertEqual(r.current, a)
        XCTAssertEqual(r.advance(), b)
    }
}

final class ScreenMappingTests: XCTestCase {
    private func screen(_ key: String, y: CGFloat = 0) -> WallpaperScreenInfo {
        WallpaperScreenInfo(key: key, name: key, pixelSize: CGSize(width: 3024, height: 1964), scale: 2,
                            cgBounds: CGRect(x: 0, y: y, width: 1512, height: 982))
    }
    private let a = UUID(), b = UUID(), gone = UUID()

    func testSameOnAllUsesDefaultEverywhere() {
        let m = ScreenMapping.assignments(screens: [screen("s1"), screen("s2")], sameOnAll: true, defaultItem: a,
                                          perScreen: ["s1": b], available: [a, b])
        XCTAssertEqual(m, ["s1": a, "s2": a])
    }

    func testPerScreenAssignmentWithFallback() {
        let m = ScreenMapping.assignments(screens: [screen("s1"), screen("s2")], sameOnAll: false, defaultItem: a,
                                          perScreen: ["s1": b], available: [a, b])
        XCTAssertEqual(m, ["s1": b, "s2": a])
    }

    func testDeletedItemsAreIgnoredAndMirroredScreensCollapse() {
        let m = ScreenMapping.assignments(screens: [screen("s1"), screen("s1"), screen("s2")], sameOnAll: false, defaultItem: gone,
                                          perScreen: ["s1": gone, "s2": b], available: [a, b])
        XCTAssertEqual(m, ["s2": b])
        XCTAssertEqual(ScreenMapping.unique([screen("s1"), screen("s1")]).count, 1)
    }

    func testNoDefaultNoAssignmentMeansNoWindow() {
        XCTAssertTrue(ScreenMapping.assignments(screens: [screen("s1")], sameOnAll: true, defaultItem: nil, perScreen: [:], available: [a]).isEmpty)
    }
}

final class OcclusionCheckTests: XCTestCase {
    private let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
    /// Ana ekranın ÜSTÜNDE duran ikinci ekran: global koordinatlarda (sol üst orijin) negatif y.
    private let above = CGRect(x: 0, y: -1080, width: 1920, height: 1080)

    private func win(_ r: CGRect, layer: Int = 0, alpha: Double = 1, pid: Int32 = 100) -> WindowSnapshot {
        WindowSnapshot(layer: layer, alpha: alpha, bounds: r, ownerPID: pid)
    }

    func testEmptyDesktopIsVisible() {
        let r = OcclusionCheck.analyze(windows: [win(CGRect(x: 100, y: 100, width: 400, height: 300))], display: main)
        XCTAssertLessThan(r.coverage, 0.2)
        XCTAssertFalse(OcclusionCheck.isCovered(r))
    }

    func testMaximizedWindowCoversButIsNotFullScreen() {
        let r = OcclusionCheck.analyze(windows: [win(CGRect(x: 0, y: 25, width: 1440, height: 875))], display: main)
        XCTAssertTrue(OcclusionCheck.isCovered(r))
        XCTAssertFalse(r.fullScreen)
    }

    func testFullScreenWindow() {
        let r = OcclusionCheck.analyze(windows: [win(main)], display: main)
        XCTAssertTrue(r.fullScreen)
        XCTAssertTrue(OcclusionCheck.isCovered(r))
    }

    func testSideBySideWindowsUnionCover() {
        let r = OcclusionCheck.analyze(windows: [win(CGRect(x: 0, y: 25, width: 720, height: 875)), win(CGRect(x: 720, y: 25, width: 720, height: 875))], display: main)
        XCTAssertTrue(OcclusionCheck.isCovered(r))
    }

    func testTranslucentAndNonNormalLayersAreIgnored() {
        let r = OcclusionCheck.analyze(windows: [win(main, alpha: 0.5), win(main, layer: 25), win(main, layer: -2_147_483_623)], display: main)
        XCTAssertFalse(OcclusionCheck.isCovered(r))
    }

    func testExcludedPIDIsIgnored() {
        let r = OcclusionCheck.analyze(windows: [win(main, pid: 7)], display: main, excludingPID: 7)
        XCTAssertFalse(OcclusionCheck.isCovered(r))
    }

    func testWindowOnOtherDisplayDoesNotCoverThisOne() {
        // İkinci ekranın (üstte) tam ekran penceresi ana ekranı örtmez; dikey ofsetli ekranda koordinatlar yine doğru.
        let w = [win(above)]
        XCTAssertFalse(OcclusionCheck.isCovered(OcclusionCheck.analyze(windows: w, display: main)))
        XCTAssertTrue(OcclusionCheck.analyze(windows: w, display: above).fullScreen)
    }

    /// Pil kuralı: 2 sn'lik yoklama ucuz olmalı. Gerçek pencere listesi + analiz, birden çok ekran için ölçülür.
    func testLiveCheckIsCheap() {
        let iterations = 200
        _ = OcclusionCheck.liveWindows() // ısınma
        let clock = ContinuousClock()
        var count = 0
        let elapsed = clock.measure {
            for _ in 0..<iterations {
                let windows = OcclusionCheck.liveWindows()
                count = windows.count
                _ = OcclusionCheck.analyze(windows: windows, display: main)
                _ = OcclusionCheck.analyze(windows: windows, display: above)
            }
        }
        let perCallMicros = Double(elapsed.components.attoseconds / 1_000_000_000_000 + elapsed.components.seconds * 1_000_000) / Double(iterations)
        print("ADALMON_BENCH occlusion check: \(Int(perCallMicros)) µs/call (\(count) layer-0 windows, 2 displays, \(iterations) runs)")
        // 2 sn'de bir çağrılırsa bile bütçe: çağrı başına < 5 ms => CPU < %0,25 tek çekirdek.
        XCTAssertLessThan(perCallMicros, 5_000)
    }

    func testAnalyzeAloneIsMicroseconds() {
        let windows = (0..<60).map { win(CGRect(x: CGFloat($0 * 20), y: CGFloat($0 * 10), width: 400, height: 300)) }
        let clock = ContinuousClock()
        let elapsed = clock.measure { for _ in 0..<1_000 { _ = OcclusionCheck.analyze(windows: windows, display: main) } }
        let micros = Double(elapsed.components.attoseconds / 1_000_000_000_000) / 1_000
        print("ADALMON_BENCH occlusion analyze (60 windows): \(Int(micros)) µs/call")
        XCTAssertLessThan(micros, 2_000)
    }
}
