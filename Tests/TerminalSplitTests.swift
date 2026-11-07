import XCTest
@testable import Adalmon

final class TerminalSplitTests: XCTestCase {
    private let warp = "/Applications/Warp.app"
    private let identity = MachTimebase(numer: 1, denom: 1)

    // MARK: Terminal tanıma ve anahtar

    func testKnownTerminalsAndIDEs() {
        for path in ["/Applications/Warp.app", "/System/Applications/Utilities/Terminal.app", "/Applications/iTerm.app",
                     "/Applications/Ghostty.app", "/Applications/Alacritty.app", "/Applications/kitty.app", "/Applications/WezTerm.app",
                     "/Applications/Visual Studio Code.app", "/Applications/Cursor.app"] {
            XCTAssertTrue(TerminalApps.isTerminal(key: path), path)
        }
        for path in ["/Applications/Safari.app", "/Applications/Xcode.app", "/usr/bin/zsh", ResourceKeys.system, "/Applications/Warp.app|/usr/bin/git"] {
            XCTAssertFalse(TerminalApps.isTerminal(key: path), path)
        }
    }

    func testChildKeyRoundTripAndDisplay() {
        let key = TerminalChildKey.make(terminal: warp, child: "/usr/bin/git")
        XCTAssertEqual(key, "/Applications/Warp.app|/usr/bin/git")
        let parts = try? XCTUnwrap(TerminalChildKey.split(key))
        XCTAssertEqual(parts?.terminal, warp)
        XCTAssertEqual(parts?.child, "/usr/bin/git")
        XCTAssertNil(TerminalChildKey.split(warp))
        XCTAssertNil(TerminalChildKey.split(ResourceKeys.other))
        XCTAssertTrue(TerminalChildKey.isResidual(TerminalChildKey.residualKey(terminal: warp)))
        XCTAssertFalse(TerminalChildKey.isResidual(key))
        XCTAssertEqual(TerminalChildKey.displayName(key, appName: { _ in "Warp" }), "Warp › Git")
        XCTAssertEqual(TerminalChildKey.displayName(TerminalChildKey.residualKey(terminal: warp), appName: { _ in "Warp" }),
                       "Warp › diğer (kısa ömürlü süreçler)")
        XCTAssertNil(TerminalChildKey.displayName(warp, appName: { _ in "Warp" }))
    }

    func testExecutableNamesResolveToolsNotEnclosingApp() {
        let xcode = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
        XCTAssertEqual(AppNaming.executableName("\(xcode)/swift-frontend"), "Swift derleyici")
        XCTAssertEqual(AppNaming.executableName("/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"), "xcodebuild")
        XCTAssertEqual(AppNaming.executableName("/Users/u/.local/share/claude/versions/2.1.3"), "Claude Code")
        XCTAssertEqual(AppNaming.executableName("/opt/homebrew/Cellar/node/25.1.0/bin/node"), "Node.js")
        XCTAssertEqual(AppNaming.executableName("/bin/zsh"), "zsh")
        XCTAssertEqual(AppNaming.executableName("/usr/bin/git"), "Git")
    }

    // MARK: Bölme ve kalan

    private func usage(cpu: UInt64 = 0, gpu: UInt64 = 0, write: UInt64 = 0, read: UInt64 = 0, energy: UInt64 = 0, fp: UInt64 = 0) -> ResourceUsage {
        ResourceUsage(cpuNs: cpu, gpuNs: gpu, writeBytes: write, readBytes: read, energyNj: energy, footprint: fp)
    }

    func testResidualIsTotalMinusSeenChildren() {
        let total = usage(cpu: 1_000, write: 735_000, read: 50, energy: 90)
        let parts = TerminalSplit.split(
            total: total, own: usage(cpu: 100, write: 5_000, fp: 300),
            children: ["xcodebuild": usage(cpu: 400, write: 200_000, read: 20, energy: 40, fp: 500),
                       "claude": usage(cpu: 200, write: 30_000, energy: 10, fp: 700)])
        XCTAssertEqual(parts.residual.cpuNs, 300)
        XCTAssertEqual(parts.residual.writeBytes, 500_000)
        XCTAssertEqual(parts.residual.readBytes, 30)
        XCTAssertEqual(parts.residual.energyNj, 40)
        XCTAssertEqual(parts.residual.footprint, 0, "ölmüş süreçlerin belleği olmaz")
    }

    func testSplitConservesCoalitionTotals() {
        let total = usage(cpu: 5_000, write: 1_000_000, read: 123, energy: 777, fp: 900)
        let parts = TerminalSplit.split(total: total, own: usage(cpu: 700, write: 1_000, fp: 100),
                                        children: ["a": usage(cpu: 1_000, write: 300_000, read: 100, energy: 70, fp: 400),
                                                   "b": usage(cpu: 2_000, write: 100_000, energy: 7, fp: 400)])
        var sum = parts.own
        for u in parts.children.values { sum.add(u) }
        sum.add(parts.residual)
        XCTAssertEqual(sum.cpuNs, total.cpuNs)
        XCTAssertEqual(sum.writeBytes, total.writeBytes)
        XCTAssertEqual(sum.readBytes, total.readBytes)
        XCTAssertEqual(sum.energyNj, total.energyNj)
        XCTAssertEqual(sum.footprint, 900, "bellek anlık: yalnız yaşayan süreçlerin toplamı")
    }

    func testResidualClampsAtZeroWhenChildrenExceedTotal() {
        let parts = TerminalSplit.split(total: usage(cpu: 100, write: 10), own: usage(),
                                        children: ["a": usage(cpu: 300, write: 50)])
        XCTAssertEqual(parts.residual, .zero)
    }

    func testCoalitionGPUStaysWithTerminalItself() {
        let parts = TerminalSplit.split(total: usage(gpu: 9_000), own: usage(gpu: 1_000),
                                        children: ["a": usage(gpu: 0)])
        XCTAssertEqual(parts.own.gpuNs, 9_000)
        XCTAssertEqual(parts.residual.gpuNs, 0)
    }

    func testNoChildrenAllUnseenGoesToResidual() {
        let parts = TerminalSplit.split(total: usage(cpu: 50, write: 1_000), own: usage(), children: [:])
        XCTAssertEqual(parts.residual.writeBytes, 1_000)
        XCTAssertTrue(parts.children.isEmpty)
    }

    // MARK: Süreç izleyici (kısa ömürlü süreçler)

    private func key(_ pid: Int32, start: UInt64) -> ProcessKey { ProcessKey(pid: pid, start: start) }

    func testTrackerFirstSweepIsBaseline() {
        var t = TerminalChildTracker()
        let k = key(10, start: 100)
        let out = t.update([k: ProcessCounters(cpuTicks: 5_000, bytesWritten: 9_000, footprint: 42)], sweepStartTicks: 1_000, timebase: identity)
        XCTAssertEqual(out[k]?.writeBytes, 0)
        XCTAssertEqual(out[k]?.footprint, 42)
    }

    func testTrackerKnownProcessGivesDelta() {
        var t = TerminalChildTracker()
        let k = key(10, start: 100)
        _ = t.update([k: ProcessCounters(cpuTicks: 1_000, bytesWritten: 9_000)], sweepStartTicks: 1_000, timebase: identity)
        let out = t.update([k: ProcessCounters(cpuTicks: 1_600, bytesWritten: 9_500)], sweepStartTicks: 2_000, timebase: identity)
        XCTAssertEqual(out[k]?.cpuNs, 600)
        XCTAssertEqual(out[k]?.writeBytes, 500)
    }

    func testTrackerProcessBornBetweenSweepsCountsFullCumulative() {
        var t = TerminalChildTracker()
        _ = t.update([:], sweepStartTicks: 1_000, timebase: identity)
        let born = key(20, start: 1_500)
        let old = key(21, start: 400)
        let out = t.update([born: ProcessCounters(cpuTicks: 700, bytesWritten: 4_000),
                            old: ProcessCounters(cpuTicks: 700, bytesWritten: 4_000)], sweepStartTicks: 2_000, timebase: identity)
        XCTAssertEqual(out[born]?.writeBytes, 4_000, "aralıkta doğan süreç baştan sayılır")
        XCTAssertEqual(out[born]?.cpuNs, 700)
        XCTAssertEqual(out[old]?.writeBytes, 0, "önceden var olup ilk kez görülen taban çizgisidir")
    }

    func testTrackerReusedPidIsANewProcessAndDeadOnesAreDropped() {
        var t = TerminalChildTracker()
        let first = key(30, start: 100)
        _ = t.update([first: ProcessCounters(bytesWritten: 8_000)], sweepStartTicks: 1_000, timebase: identity)
        let reused = key(30, start: 1_200)
        let out = t.update([reused: ProcessCounters(bytesWritten: 100)], sweepStartTicks: 2_000, timebase: identity)
        XCTAssertEqual(out[reused]?.writeBytes, 100)
        XCTAssertNil(out[first])
    }

    func testShortLivedChildEndsUpInResidual() {
        // Süpürme 1: kalıcı süreç görülür. Aralıkta: kalıcı 300 yazar, kısa ömürlü süreç 700 yazıp ölür.
        var t = TerminalChildTracker()
        let longLived = key(40, start: 100)
        _ = t.update([longLived: ProcessCounters(bytesWritten: 1_000)], sweepStartTicks: 1_000, timebase: identity)
        let deltas = t.update([longLived: ProcessCounters(bytesWritten: 1_300)], sweepStartTicks: 2_000, timebase: identity)
        let parts = TerminalSplit.split(total: usage(write: 1_000), own: .zero,
                                        children: ["/usr/bin/xcodebuild": deltas[longLived] ?? .zero])
        XCTAssertEqual(parts.children["/usr/bin/xcodebuild"]?.writeBytes, 300)
        XCTAssertEqual(parts.residual.writeBytes, 700)
    }

    // MARK: Aynı ad ipuçları

    private func hints(_ keys: [String], names: [String: String] = [:]) -> [String: String] {
        DuplicateNameHints.hints(keys: keys, name: { names[$0] ?? "Adalmon" }, home: "/Users/u")
    }

    func testDuplicateNamesGetLocationHints() {
        let a = "/Applications/Adalmon.app"
        let b = "/Users/u/Library/Developer/Xcode/DerivedData/Adalmon-abc/Build/Products/Debug/Adalmon.app"
        let h = hints([a, b])
        XCTAssertEqual(h[a], "/Applications")
        XCTAssertEqual(h[b], "DerivedData")
    }

    func testUniqueNamesGetNoHint() {
        let h = hints(["/Applications/Adalmon.app", "/Applications/Safari.app"], names: ["/Applications/Safari.app": "Safari"])
        XCTAssertTrue(h.isEmpty)
    }

    func testCollidingShortLabelsEscalateToSpecificOnes() {
        let a = "/Users/u/Library/Developer/Xcode/DerivedData/Adalmon-abc/Build/Products/Debug/Adalmon.app"
        let b = "/Users/u/Library/Developer/Xcode/DerivedData/Adalmon-xyz/Build/Products/Debug/Adalmon.app"
        let c = "/Applications/Adalmon.app"
        let h = hints([a, b, c])
        XCTAssertEqual(h[a], "DerivedData/Adalmon-abc")
        XCTAssertEqual(h[b], "DerivedData/Adalmon-xyz")
        XCTAssertEqual(h[c], "/Applications", "benzersiz kısa etiketi olan satır kısa kalır")
    }

    func testHomeApplicationsAndNestedFolders() {
        let a = "/Applications/Foo.app"
        let b = "/Users/u/Applications/Foo.app"
        let c = "/Users/u/Downloads/Foo.app"
        let h = hints([a, b, c], names: [a: "Foo", b: "Foo", c: "Foo"])
        XCTAssertEqual(h[a], "/Applications")
        XCTAssertEqual(h[b], "~/Applications")
        XCTAssertEqual(h[c], "~/Downloads")
    }

    func testTerminalChildDuplicatesUseChildExecutableDirectory() {
        let n1 = TerminalChildKey.make(terminal: warp, child: "/opt/homebrew/Cellar/node/24.1.0/bin/node")
        let n2 = TerminalChildKey.make(terminal: warp, child: "/opt/homebrew/Cellar/node/25.0.0/bin/node")
        let h = DuplicateNameHints.hints(keys: [n1, n2], name: { _ in "Warp › Node.js" }, home: "/Users/u")
        XCTAssertEqual(h[n1], "/opt/homebrew/Cellar/node/24.1.0/bin")
        XCTAssertEqual(h[n2], "/opt/homebrew/Cellar/node/25.0.0/bin")
    }

    func testSpecialKeysAreIgnored() {
        let h = DuplicateNameHints.hints(keys: [ResourceKeys.other, ResourceKeys.system], name: { _ in "x" }, home: "/Users/u")
        XCTAssertTrue(h.isEmpty)
    }

    // MARK: Gerçek süpürme

    func testRealSweepTerminalGroupsAreConsistent() {
        let sweeper = ResourceSweeper()
        _ = sweeper.sweep()
        let r = sweeper.sweep()
        for (terminal, children) in r.terminalChildren {
            XCTAssertTrue(TerminalApps.isTerminal(key: terminal))
            XCTAssertNotNil(r.groups[terminal], "terminalin kendi grubu her zaman var")
            XCTAssertNil(r.groups[terminal]?.terminalParent)
            for ck in children {
                XCTAssertEqual(TerminalChildKey.split(ck)?.terminal, terminal)
                XCTAssertEqual(r.groups[ck]?.terminalParent, terminal)
            }
            let pids = ([terminal] + children).flatMap { r.groups[$0]?.pids ?? [] }
            XCTAssertEqual(pids.count, Set(pids).count, "bir süreç yalnız bir alt grupta")
        }
        let plain = ResourceSweeper(splitsTerminals: false).sweep()
        XCTAssertTrue(plain.terminalChildren.isEmpty)
    }

    func testSplitSweepCostStaysLow() {
        func perSweepMs(_ sweeper: ResourceSweeper) -> Double {
            _ = sweeper.sweep()
            _ = sweeper.sweep()
            let n = 40
            let t0 = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<n { _ = sweeper.sweep() }
            return Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6 / Double(n)
        }
        let without = perSweepMs(ResourceSweeper(splitsTerminals: false))
        let with = perSweepMs(ResourceSweeper(splitsTerminals: true))
        let terminals = ResourceSweeper().sweep().terminalChildren
        print("TERMINAL_SWEEP_BENCH without-split ms:", without, "with-split ms:", with, "extra ms:", with - without,
              "terminal coalitions:", terminals.count, "child groups:", terminals.values.reduce(0) { $0 + $1.count })
        XCTAssertLessThan(with - without, 5, "terminal bölme tur başına ~5 ms altında kalmalı")
    }
}
