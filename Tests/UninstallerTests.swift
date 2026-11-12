import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Kaldırıcı + yetim bulucu. Her şey geçici bir sahte ev klasöründe (Applications + Library); gerçek Çöp Sepeti, gerçek günlük,
/// launchctl ya da gerçek ev klasörü kullanılmaz (Çöp'e taşıma fixture içindeki FakeTrash'e yapılır).
final class UninstallerTests: XCTestCase {
    private var fixture: URL!
    private var home: String { fixture.path }
    private var fakeTrash: URL { fixture.appending(path: "FakeTrash", directoryHint: .isDirectory) }
    private var logURL: URL { fixture.appending(path: "log.jsonl") }
    private let uuid = "0123ABCD-4567-89AB-CDEF-0123456789AB"

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var _trash: [String] = []
        private var _agents: [String] = []
        var trash: [String] { lock.withLock { _trash } }
        var agents: [String] { lock.withLock { _agents } }
        func addTrash(_ p: String) { lock.withLock { _trash.append(p) } }
        func addAgent(_ p: String) { lock.withLock { _agents.append(p) } }
    }

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory.appending(path: "uninstaller-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fixture)
    }

    // MARK: Yardımcılar

    @discardableResult
    private func makeApp(_ rel: String, id: String, name: String? = nil, appStore: Bool = false) throws -> String {
        let app = fixture.appending(path: rel, directoryHint: .isDirectory)
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleShortVersionString": "1.2"]
        if let name { plist["CFBundleName"] = name }
        XCTAssertTrue((plist as NSDictionary).write(toFile: contents.appending(path: "Info.plist").path, atomically: true))
        try Data("bin".utf8).write(to: contents.appending(path: "payload"))
        if appStore { try FileManager.default.createDirectory(at: contents.appending(path: "_MASReceipt"), withIntermediateDirectories: true) }
        return app.path
    }

    @discardableResult
    private func makeEntry(_ rel: String, dir: Bool = true, size: Int = 8) throws -> String {
        let url = fixture.appending(path: rel)
        if dir {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(repeating: 1, count: size).write(to: url.appending(path: "data.bin"))
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: size).write(to: url)
        }
        return url.path
    }

    private var applications: AppRoot { AppRoot(path: home + "/Applications", subfolders: false) }

    private func scan(subfolders: Bool = false, running: Set<String> = [], resolver: @escaping @Sendable (String) -> Bool = { _ in false },
                      minOrphan: UInt64 = OrphanFinder.minFolderBytes) -> AppScanOutput {
        InstalledAppScanner.scan(home: home, roots: [AppRoot(path: home + "/Applications", subfolders: subfolders)], running: running,
                                 ownIDs: [AdalmonIdentity.appBundleID], ownBundlePaths: [], resolver: resolver, minOrphanFolderBytes: minOrphan)
    }

    private func deleter() -> CleanupDeleter {
        CleanupDeleter(home: home, runningBundleIDs: { [] }, logURL: logURL, ownPaths: [],
                       moveToTrash: { _ in nil }, removePermanently: { _ in })
    }

    private func remover(running: Set<String> = [], calls: Calls = Calls(), failTrash: Set<String> = [], realRemove: Bool = false) -> AppRemover {
        let trashDir = fakeTrash
        let removal: @Sendable (URL) throws -> Void = realRemove ? CleanupDeleter.systemRemove : { @Sendable _ in }
        return AppRemover(
            home: home, runningBundleIDs: { running }, logURL: logURL, ownPaths: [],
            trash: { url in
                calls.addTrash(url.path)
                if failTrash.contains(url.path) { throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError) }
                let dest = trashDir.appending(path: UUID().uuidString + "-" + url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: dest)
                return dest
            },
            remove: removal,
            launchAgentRemoval: { candidate in calls.addAgent(candidate.path); return .success }
        )
    }

    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    private func rel(_ paths: [String]) -> Set<String> {
        let canonicalHome = CleanupDeleter.realPath(home) ?? home
        return Set(paths.map { $0.hasPrefix(home + "/") ? String($0.dropFirst(home.count + 1)) : String($0.dropFirst(canonicalHome.count + 1)) })
    }

    /// Bar (com.foo.Bar) ve Bar2 (com.foo.Bar2) için tam bir Library.
    private func makeBarFixture() throws {
        try makeApp("Applications/Bar.app", id: "com.foo.Bar", name: "Bar")
        try makeApp("Applications/Bar2.app", id: "com.foo.Bar2", name: "Bar2")
        for id in ["com.foo.Bar", "com.foo.Bar2"] {
            try makeEntry("Library/Caches/\(id)")
            try makeEntry("Library/Preferences/\(id).plist", dir: false)
            try makeEntry("Library/Preferences/ByHost/\(id).\(uuid).plist", dir: false)
            try makeEntry("Library/Application Support/\(id)")
            try makeEntry("Library/Saved Application State/\(id).savedState")
            try makeEntry("Library/HTTPStorages/\(id)")
            try makeEntry("Library/HTTPStorages/\(id).binarycookies", dir: false)
            try makeEntry("Library/WebKit/\(id)")
            try makeEntry("Library/Cookies/\(id).binarycookies", dir: false)
            try makeEntry("Library/LaunchAgents/\(id).plist", dir: false)
            try makeEntry("Library/Application Scripts/\(id)")
            try makeEntry("Library/Containers/\(id)")
            try makeEntry("Library/Group Containers/group.\(id)")
        }
        try makeEntry("Library/Application Support/Bar")
        try makeEntry("Library/Application Support/Bar2")
        try makeEntry("Library/Logs/Bar")
        try makeEntry("Library/Logs/Bar2")
        try makeEntry("Library/Preferences/ByHost/com.foo.Bar.Helper.\(uuid).plist", dir: false)
        try makeEntry("Library/LaunchAgents/com.foo.Bar.helper.plist", dir: false)
        try makeEntry("Library/Group Containers/ABCDE12345.com.foo.Bar")
        try makeEntry("Library/Group Containers/x.y.com.foo.Bar")
    }

    // MARK: Uygulama taraması

    func testScannerListsAppsAndSkipsApplesSelfSymlinksAndSystem() throws {
        try makeApp("Applications/Bar.app", id: "com.foo.Bar", name: "Bar")
        try makeApp("Applications/Calc.app", id: "com.apple.calculator")
        try makeApp("Applications/Adalmon.app", id: AdalmonIdentity.appBundleID)
        try makeApp("Applications/Store.app", id: "com.store.App", appStore: true)
        try makeApp("Applications/Suite/Inner.app", id: "com.foo.Inner")
        try FileManager.default.createSymbolicLink(atPath: home + "/Applications/Link.app", withDestinationPath: home + "/Applications/Bar.app")
        try makeEntry("Applications/NotAnApp.txt", dir: false)

        let flat = InstalledAppScanner.scanBundles(roots: [applications], ownIDs: [AdalmonIdentity.appBundleID], ownBundlePaths: [])
        XCTAssertEqual(Set(flat.map(\.bundleID)), ["com.foo.Bar", "com.store.App"], "Apple, Adalmon, sembolik bağ ve .app olmayanlar atlanır")
        let bar = try XCTUnwrap(flat.first { $0.bundleID == "com.foo.Bar" })
        XCTAssertEqual(bar.version, "1.2")
        XCTAssertEqual(bar.names, ["Bar"])
        XCTAssertGreaterThan(bar.bytes, 0)
        XCTAssertNil(bar.removalBlock)
        XCTAssertEqual(flat.first { $0.bundleID == "com.store.App" }?.removalBlock, .appStore)

        let deep = InstalledAppScanner.scanBundles(roots: [AppRoot(path: home + "/Applications", subfolders: true)],
                                                   ownIDs: [AdalmonIdentity.appBundleID], ownBundlePaths: [])
        XCTAssertTrue(deep.contains { $0.bundleID == "com.foo.Inner" }, "bir düzey alt klasör taranır")

        // Kendi paket yolu verilirse o da atlanır.
        let withSelf = InstalledAppScanner.scanBundles(roots: [applications], ownIDs: [], ownBundlePaths: [home + "/Applications/Bar.app"])
        XCTAssertFalse(withSelf.contains { $0.bundleID == "com.foo.Bar" })

        // /System altındaki kök hiç taranmaz.
        let system = "/System/Applications"
        if exists(system) {
            XCTAssertEqual(InstalledAppScanner.scanBundles(roots: [AppRoot(path: system, subfolders: true)], ownIDs: [], ownBundlePaths: []), [])
        }
    }

    // MARK: Artık eşleşmesi

    func testLeftoversMatchExactIDsOnly() throws {
        try makeBarFixture()
        let out = scan()
        let bar = try XCTUnwrap(out.apps.first { $0.bundleID == "com.foo.Bar" })
        let bar2 = try XCTUnwrap(out.apps.first { $0.bundleID == "com.foo.Bar2" })

        XCTAssertEqual(rel(bar.leftovers.map(\.path)), [
            "Library/Caches/com.foo.Bar",
            "Library/Preferences/com.foo.Bar.plist",
            "Library/Preferences/ByHost/com.foo.Bar.\(uuid).plist",
            "Library/Application Support/com.foo.Bar",
            "Library/Application Support/Bar",
            "Library/Saved Application State/com.foo.Bar.savedState",
            "Library/HTTPStorages/com.foo.Bar",
            "Library/HTTPStorages/com.foo.Bar.binarycookies",
            "Library/WebKit/com.foo.Bar",
            "Library/Logs/Bar",
            "Library/Cookies/com.foo.Bar.binarycookies",
            "Library/LaunchAgents/com.foo.Bar.plist",
            "Library/LaunchAgents/com.foo.Bar.helper.plist",
            "Library/Application Scripts/com.foo.Bar",
            "Library/Containers/com.foo.Bar",
            "Library/Group Containers/group.com.foo.Bar",
            "Library/Group Containers/ABCDE12345.com.foo.Bar",
        ])
        XCTAssertFalse(bar.leftovers.contains { $0.path.contains("Bar2") }, "com.foo.Bar2, com.foo.Bar ile eşleşmez")
        XCTAssertFalse(bar.leftovers.contains { $0.path.contains("Bar.Helper") }, "ByHost'ta UUID olmayan orta parça eşleşmez")
        XCTAssertFalse(bar.leftovers.contains { $0.path.hasSuffix("x.y.com.foo.Bar") })
        XCTAssertTrue(bar2.leftovers.allSatisfy { $0.path.contains("Bar2") && !$0.path.hasSuffix("com.foo.Bar.plist") })
        XCTAssertEqual(bar2.leftovers.count, 15, "Bar2: 13 kimlik girdisi + Application Support/Bar2 + Logs/Bar2")
        XCTAssertTrue(bar.leftovers.allSatisfy { $0.blockingBundleIDs == ["com.foo.Bar"] })
        XCTAssertGreaterThan(bar.leftoverBytes, 0)
    }

    func testEveryProducedCandidatePassesTheRealDeleterChecks() throws {
        try makeBarFixture()
        let out = scan()
        let d = deleter()
        for app in out.apps {
            XCTAssertNil(d.validate(app.bundleCandidate, running: []), app.path)
            for leftover in app.leftovers {
                XCTAssertNil(d.validate(leftover, running: []), leftover.path)
            }
        }
    }

    func testSymlinkedLeftoverIsNotListed() throws {
        try makeApp("Applications/Bar.app", id: "com.foo.Bar")
        let target = try makeEntry("Elsewhere/data")
        try FileManager.default.createDirectory(atPath: home + "/Library/Caches", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: home + "/Library/Caches/com.foo.Bar", withDestinationPath: target)
        let bar = try XCTUnwrap(scan().apps.first)
        XCTAssertTrue(bar.leftovers.isEmpty)
    }

    func testLaunchAgentClaimedByLongerInstalledID() throws {
        try makeApp("Applications/Bar.app", id: "com.foo.Bar")
        try makeApp("Applications/BarPro.app", id: "com.foo.Bar.Pro")
        try makeEntry("Library/LaunchAgents/com.foo.Bar.Pro.helper.plist", dir: false)
        try makeEntry("Library/LaunchAgents/com.foo.Bar.plist", dir: false)
        let out = scan()
        let bar = try XCTUnwrap(out.apps.first { $0.bundleID == "com.foo.Bar" })
        let pro = try XCTUnwrap(out.apps.first { $0.bundleID == "com.foo.Bar.Pro" })
        XCTAssertEqual(rel(bar.leftovers.map(\.path)), ["Library/LaunchAgents/com.foo.Bar.plist"])
        XCTAssertEqual(rel(pro.leftovers.map(\.path)), ["Library/LaunchAgents/com.foo.Bar.Pro.helper.plist"])
    }

    // MARK: Yetimler

    func testOrphanDetectionWithInjectedResolver() throws {
        try makeApp("Applications/Bar.app", id: "com.foo.Bar")
        let big = 2 << 20
        try makeEntry("Library/Caches/com.gone.App", size: big)
        try makeEntry("Library/Group Containers/group.com.gone.App", size: big)
        try makeEntry("Library/Preferences/com.gone.App.plist", dir: false)
        try makeEntry("Library/Caches/com.small.Gone", size: 100)
        try makeEntry("Library/Caches/com.resolved.App", size: big)
        try makeEntry("Library/Caches/com.foo.Bar", size: big)
        try makeEntry("Library/Caches/com.foo.Bar.ShipIt", size: big)
        try makeEntry("Library/Caches/com.apple.Safari", size: big)
        try makeEntry("Library/Caches/NotReverseDNS", size: big)
        try makeEntry("Library/Caches/com.two", size: big)
        try makeEntry("Library/Caches/\(AdalmonIdentity.appBundleID)", size: big)
        try makeEntry("Library/Caches/org.running.App", size: big)
        try makeEntry("Library/LaunchAgents/com.gone.Agent.plist", dir: false)

        let out = scan(running: ["org.running.App"], resolver: { $0 == "com.resolved.App" })
        XCTAssertEqual(out.orphans.map(\.bundleID), ["com.gone.App"])
        let group = try XCTUnwrap(out.orphans.first)
        XCTAssertEqual(rel(group.items.map(\.path)), [
            "Library/Caches/com.gone.App", "Library/Group Containers/group.com.gone.App", "Library/Preferences/com.gone.App.plist",
        ])
        XCTAssertGreaterThan(group.bytes, UInt64(2 * big) - 1)
        let d = deleter()
        for item in group.items { XCTAssertNil(d.validate(item, running: []), item.path) }
    }

    func testResolverKnownParentIDMakesHelperEntryNotOrphan() throws {
        try makeEntry("Library/Caches/com.vendor.App.ShipIt", size: 2 << 20)
        try makeEntry("Library/Caches/com.vendor.Other", size: 2 << 20)
        let out = scan(resolver: { $0 == "com.vendor.App" })
        XCTAssertEqual(out.orphans.map(\.bundleID), ["com.vendor.Other"])
    }

    @MainActor
    func testOrphansAreNeverPreselectedAndLeftoversAre() throws {
        try makeBarFixture()
        try makeEntry("Library/Caches/com.gone.App", size: 2 << 20)
        let model = UninstallerModel(home: home, remover: remover())
        model.runningProvider = { [] }
        model.apply(scan())
        XCTAssertTrue(model.orphanSelection.isEmpty, "yetimler varsayılan seçili değil")
        XCTAssertFalse(model.orphans.isEmpty)
        let app = try XCTUnwrap(model.selectedApp)
        XCTAssertEqual(model.leftoverSelection, Set(app.leftovers.filter { !LeftoverRules.isNameMatch($0, app: app.identity) }.map(\.path)),
                       "kimlikle eşleşen artıklar seçili, ada göre eşleşenler değil")
        XCTAssertTrue(model.includeBundle)
        model.search = "bar2"
        XCTAssertEqual(model.visibleApps.map(\.bundleID), ["com.foo.Bar2"])
        model.tab = .orphans
        XCTAssertNil(model.orphansPending, "seçim yoksa silinecek yok")
    }

    func testNameMatchedLeftoversAreSkippedWhenAnotherInstalledAppClaimsTheName() throws {
        // İki farklı uygulama aynı adı taşıyor: "Application Support/Shared" ve "Logs/Shared" kime ait belli değil.
        try makeApp("Applications/Shared.app", id: "com.a.Shared", name: "Shared")
        try makeApp("Applications/Shared Beta.app", id: "com.b.SharedBeta", name: "Shared")
        try makeApp("Applications/Solo.app", id: "com.c.Solo", name: "Solo")
        for rel in ["Library/Application Support/Shared", "Library/Logs/Shared", "Library/Application Support/com.a.Shared",
                    "Library/Application Support/Solo", "Library/Logs/Solo", "Library/Application Support/com.c.Solo"] { try makeEntry(rel) }
        let out = scan()
        let shared = try XCTUnwrap(out.apps.first { $0.bundleID == "com.a.Shared" })
        let beta = try XCTUnwrap(out.apps.first { $0.bundleID == "com.b.SharedBeta" })
        let solo = try XCTUnwrap(out.apps.first { $0.bundleID == "com.c.Solo" })
        XCTAssertEqual(rel(shared.leftovers.map(\.path)), ["Library/Application Support/com.a.Shared"], "ortak ad atlanır, kimlik eşleşmesi kalır")
        XCTAssertTrue(beta.leftovers.isEmpty)
        XCTAssertEqual(rel(solo.leftovers.map(\.path)), ["Library/Application Support/com.c.Solo", "Library/Application Support/Solo", "Library/Logs/Solo"])
    }

    func testNameMatchRuleSkipsEntriesThatAreAnotherInstalledAppsIDOrName() {
        let app = AppMatchKey(bundleID: "com.q.Zed", names: ["Zed"])
        XCTAssertTrue(LeftoverRules.matches(.applicationSupport, entry: "Zed", app: app, otherIDs: ["com.q.Zed"]))
        XCTAssertFalse(LeftoverRules.matches(.applicationSupport, entry: "Zed", app: app, otherIDs: ["com.q.Zed"], otherNames: ["Zed"]))
        XCTAssertFalse(LeftoverRules.matches(.logs, entry: "Zed", app: app, otherIDs: ["com.q.Zed", "Zed"]), "girdi başka uygulamanın kimliği")
        XCTAssertTrue(LeftoverRules.matches(.applicationSupport, entry: "com.q.Zed", app: app, otherIDs: ["com.q.Zed"], otherNames: ["com.q.Zed"]),
                      "tam kimlik eşleşmesi her zaman geçerli")
    }

    @MainActor
    func testNameMatchedLeftoversAreNotPreselectedButIDMatchedAre() throws {
        try makeBarFixture()
        let model = UninstallerModel(home: home, remover: remover())
        model.runningProvider = { [] }
        model.apply(scan())
        let bar = try XCTUnwrap(model.apps.first { $0.bundleID == "com.foo.Bar" })
        model.select(bar)
        let byName: Set<String> = ["Library/Application Support/Bar", "Library/Logs/Bar"]
        let all = rel(bar.leftovers.map(\.path))
        XCTAssertTrue(byName.isSubset(of: all), "ada göre eşleşenler listede")
        XCTAssertTrue(rel(Array(model.leftoverSelection)).isDisjoint(with: byName), "ada göre eşleşenler varsayılan seçili değil")
        XCTAssertFalse(all.subtracting(byName).isEmpty)
        XCTAssertEqual(rel(Array(model.leftoverSelection)), all.subtracting(byName), "bundle kimliğiyle eşleşenlerin hepsi seçili")
        // Kullanıcı elle seçebilir; seçilince silinecekler arasına girer.
        model.leftoverSelection.formUnion(bar.leftovers.filter { byName.contains(rel([$0.path]).first ?? "") }.map(\.path))
        XCTAssertTrue(byName.isSubset(of: rel(try XCTUnwrap(model.appsPending).leftovers.map(\.path))))
    }

    // MARK: Kaldırma

    func testRunningAppIsRefusedAtDeleteTime() async throws {
        try makeBarFixture()
        let bar = try XCTUnwrap(scan().apps.first { $0.bundleID == "com.foo.Bar" })
        let calls = Calls()
        let fileLeftovers = bar.leftovers.filter { $0.kind != LeftoverLocation.launchAgents.kind }
        let report = await remover(running: ["com.foo.Bar"], calls: calls).run(app: bar, leftovers: fileLeftovers, mode: .trash)
        XCTAssertTrue(calls.trash.isEmpty, "çalışan uygulamaya ve artıklarına dokunulmaz")
        XCTAssertTrue(report.removedPaths.isEmpty)
        XCTAssertTrue(exists(bar.path))
        if case .skipped(.appRunning)? = report.results.first?.outcome {} else { XCTFail("paket appRunning ile reddedilmeli: \(String(describing: report.results.first))") }

        // Yalnız artık (paket yok) da çalışırken reddedilir.
        let only = await remover(running: ["com.foo.Bar"], calls: calls).run(app: nil, leftovers: fileLeftovers, mode: .trash)
        XCTAssertTrue(only.results.allSatisfy { if case .skipped(.appRunning) = $0.outcome { true } else { false } })
        XCTAssertTrue(calls.trash.isEmpty)
    }

    func testBundleFirstThenLeftoversAndLaunchAgentGoesThroughStartupRemover() async throws {
        try makeBarFixture()
        let out = scan()
        let bar = try XCTUnwrap(out.apps.first { $0.bundleID == "com.foo.Bar" })
        let bar2 = try XCTUnwrap(out.apps.first { $0.bundleID == "com.foo.Bar2" })
        let calls = Calls()
        let report = await remover(calls: calls).run(app: bar, leftovers: bar.leftovers, mode: .trash)
        XCTAssertEqual(calls.trash.first.map { $0.hasSuffix("/Bar.app") }, true, "önce uygulama paketi")
        XCTAssertFalse(exists(bar.path))
        XCTAssertEqual(rel(calls.agents), ["Library/LaunchAgents/com.foo.Bar.plist", "Library/LaunchAgents/com.foo.Bar.helper.plist"])
        XCTAssertFalse(calls.trash.contains { $0.contains("/LaunchAgents/") }, "plist deleter ile değil StartupItemActions ile kaldırılır")
        XCTAssertEqual(report.results.filter(\.isRemoved).count, 1 + bar.leftovers.count)
        XCTAssertTrue(exists(bar2.path), "komşu uygulama dokunulmadan kalır")
        XCTAssertTrue(bar2.leftovers.allSatisfy { exists($0.path) })
        XCTAssertTrue(CleanupAuditLog.read(url: logURL, limit: 50).contains { $0.path.hasSuffix("/Bar.app") && $0.result == "moved" })
    }

    func testPermissionErrorMapsToAppManagementAndLeftoversStay() async throws {
        try makeBarFixture()
        let bar = try XCTUnwrap(scan().apps.first { $0.bundleID == "com.foo.Bar" })
        let calls = Calls()
        let report = await remover(calls: calls, failTrash: [bar.path]).run(app: bar, leftovers: bar.leftovers, mode: .trash)
        XCTAssertEqual(calls.trash, [bar.path], "paket kaldırılamayınca artıklara dokunulmaz")
        XCTAssertTrue(calls.agents.isEmpty)
        XCTAssertEqual(report.accessFailures, [bar.path: .appManagement])
        XCTAssertEqual(UninstallerModel.mainIssue(report.accessFailures), .appManagement)
        XCTAssertTrue(bar.leftovers.allSatisfy { exists($0.path) })
        XCTAssertTrue(TrashPermissionLog.isPermissionError(NSError(domain: NSCocoaErrorDomain, code: 999,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])))
        XCTAssertFalse(TrashPermissionLog.isPermissionError(NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)))
    }

    func testAppStoreAppIsNotRemovedButItsLeftoversCanBe() async throws {
        let path = try makeApp("Applications/Store.app", id: "com.store.App", appStore: true)
        let cache = try makeEntry("Library/Caches/com.store.App")
        let store = try XCTUnwrap(scan().apps.first)
        XCTAssertEqual(store.removalBlock, .appStore)
        let calls = Calls()
        let blocked = await remover(calls: calls).run(app: store, leftovers: store.leftovers, mode: .trash)
        XCTAssertTrue(calls.trash.isEmpty)
        XCTAssertTrue(exists(path) && exists(cache))
        XCTAssertFalse(blocked.removedPaths.contains(path))
        // Yalnız artıklar: paket seçilmeden silinebilir.
        let only = await remover(calls: calls).run(app: nil, leftovers: store.leftovers, mode: .trash)
        XCTAssertEqual(only.removedPaths, [cache])
        XCTAssertTrue(exists(path))
    }

    func testPermanentModeRemovesInsideFixtureOnly() async throws {
        try makeApp("Applications/Bar2.app", id: "com.foo.Bar2")
        let cache = try makeEntry("Library/Caches/com.foo.Bar2")
        let pref = try makeEntry("Library/Preferences/com.foo.Bar2.plist", dir: false)
        let bar2 = try XCTUnwrap(scan().apps.first)
        let calls = Calls()
        let report = await remover(calls: calls, realRemove: true).run(app: bar2, leftovers: bar2.leftovers, mode: .permanent)
        XCTAssertTrue(calls.trash.isEmpty)
        XCTAssertFalse(exists(bar2.path) || exists(cache) || exists(pref))
        XCTAssertTrue(report.results.allSatisfy { if case .deleted = $0.outcome { true } else { false } })
        XCTAssertTrue(exists(home), "fixture ev klasörü yerinde")
    }

    // MARK: Reddedilen yollar

    func testSystemApplicationsAndSymlinkedAppAreRefused() throws {
        let system = "/System/Applications"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: system))?.filter { $0.hasSuffix(".app") } ?? []
        let sample = try XCTUnwrap(names.first.map { system + "/" + $0 }, "bu makinede /System/Applications boş")
        var st = stat()
        XCTAssertEqual(lstat(sample, &st), 0)
        let systemCandidate = DeletionCandidate(path: sample, dev: st.st_dev, ino: st.st_ino, bytes: 1, kind: "apps.bundle", scope: .appBundle,
                                                displayName: "x")
        XCTAssertEqual(deleter().validate(systemCandidate, running: []), .notUnderAllowedRoot)

        try makeApp("Applications/Bar.app", id: "com.foo.Bar")
        let link = home + "/Applications/Link.app"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: home + "/Applications/Bar.app")
        var lst = stat()
        XCTAssertEqual(lstat(link, &lst), 0)
        let linkCandidate = DeletionCandidate(path: link, dev: lst.st_dev, ino: lst.st_ino, bytes: 1, kind: "apps.bundle", scope: .appBundle,
                                              displayName: "Link")
        XCTAssertEqual(deleter().validate(linkCandidate, running: []), .symlink)
    }

    func testDeleterRefusesAppleBundlesEvenWhenForged() throws {
        let path = try makeApp("Applications/Fake.app", id: "com.apple.fake")
        var st = stat()
        XCTAssertEqual(lstat(path, &st), 0)
        let forged = DeletionCandidate(path: path, dev: st.st_dev, ino: st.st_ino, bytes: 1, kind: "apps.bundle", scope: .appBundle, displayName: "Fake")
        XCTAssertEqual(deleter().validate(forged, running: []), .appleApp)
    }
    // MARK: Önizleme (isteğe bağlı)

    /// Yalnızca ADALMON_PREVIEW_DIR (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır; fixture verisiyle PNG yazar.
    @MainActor
    func testRenderUninstallerPreview() async throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        try makeBarFixture()
        try makeApp("Applications/Store.app", id: "com.store.App", name: "Store", appStore: true)
        try makeEntry("Library/Caches/com.gone.App", size: 3 << 20)
        try makeEntry("Library/Preferences/com.gone.App.plist", dir: false)
        let model = UninstallerModel(home: home, remover: remover())
        model.runningProvider = { ["com.foo.Bar2"] }
        model.apply(scan())
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (tab, name) in [(UninstallerModel.Tab.apps, "uninstaller-apps"), (.orphans, "uninstaller-orphans")] {
            model.tab = tab
            let view = UninstallerSection(model: model).padding(24).frame(width: 980, height: 620)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 980, height: 620),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .seconds(1))
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appending(path: "\(name).png"))
            print("UNINSTALLER_PREVIEW: \(dir.appending(path: "\(name).png").path)")
            window.close()
        }
    }
}
