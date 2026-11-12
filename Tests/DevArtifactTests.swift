import XCTest
@testable import Adalmon

/// Geliştirici bölümü: global önbellekler, proje artıkları (ProjectArtifactScanner), proje klasörü deposu ve araç komutları (sahte çalıştırıcı).
/// Gerçek brew/docker çalışmaz; her şey geçici sahte ev klasöründe geçer.
final class DevArtifactTests: XCTestCase {
    private var fixture: URL!
    private var home: String { fixture.path }
    private var projects: String { home + "/Projects" }
    private var fakeTrash: URL { fixture.appending(path: "FakeTrash", directoryHint: .isDirectory) }
    private let mb = 1_048_576
    private var suites: [String] = []

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory.appending(path: "dev-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
    }

    override func tearDown() {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        suites = []
        try? FileManager.default.removeItem(at: fixture)
    }

    @discardableResult
    private func write(_ rel: String, bytes: Int) throws -> URL {
        let url = fixture.appending(path: rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data(count: bytes)
        for i in stride(from: 0, to: bytes, by: 4096) { data[i] = UInt8(truncatingIfNeeded: i / 4096 + 1) }
        try data.write(to: url)
        return url
    }

    private func scanProjects(running: Set<String> = [], cancelled: @escaping () -> Bool = { false }) -> [CleanupItem] {
        ProjectArtifactScanner.scan(root: projects, runningBundleIDs: running, isCancelled: cancelled) ?? []
    }

    private func relNames(_ items: [CleanupItem]) -> [String] {
        items.map { String($0.path.dropFirst(projects.count + 1)) }.sorted()
    }

    private func deleter(running: Set<String> = []) -> CleanupDeleter {
        let trash = fakeTrash
        return CleanupDeleter(
            home: home, runningBundleIDs: { running }, logURL: fixture.appending(path: "log.jsonl"), ownPaths: [],
            moveToTrash: { url in
                let dest = trash.appending(path: url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: dest)
                return dest
            },
            removePermanently: { _ in throw CocoaError(.featureUnsupported) }
        )
    }

    // MARK: Global önbellekler

    func testGlobalDevCachesAreInPkgCachesRoots() throws {
        try write(".gradle/caches/modules/g.bin", bytes: 2 * mb)
        try write(".gradle/wrapper/dists/keep.bin", bytes: 2 * mb)
        try write(".cargo/registry/cache/c.crate", bytes: 2 * mb)
        try write(".cargo/registry/src/s/s.rs", bytes: 2 * mb)
        try write(".cargo/registry/index/i.bin", bytes: 2 * mb)
        try write(".cargo/bin/cargo", bytes: 2 * mb)
        try write("Library/Caches/CocoaPods/Pods/p.bin", bytes: 2 * mb)
        let out = CleanupScanner.scan(categories: [.pkgCaches, .appCaches], home: home, runningBundleIDs: [], ownBundleID: nil)
        let paths = Set(out.items.map(\.path))
        XCTAssertTrue(paths.isSuperset(of: [
            home + "/.gradle/caches", home + "/.cargo/registry/cache", home + "/.cargo/registry/src",
            home + "/Library/Caches/CocoaPods/Pods",
        ]), "\(paths)")
        XCTAssertFalse(paths.contains(home + "/.gradle/wrapper"))
        XCTAssertFalse(paths.contains { $0.contains("/.cargo/bin") || $0.hasSuffix("registry/index") })
        XCTAssertFalse(paths.contains(home + "/Library/Caches/CocoaPods"), "CocoaPods appCaches'e girmez")
        XCTAssertTrue(out.items.allSatisfy { $0.category == .pkgCaches })
        // Docker.raw hiçbir kuralda yok.
        XCTAssertFalse(CleanupCatalog.roots(home: home, ownBundleID: nil).contains { $0.path.localizedCaseInsensitiveContains("docker") })
    }

    func testGlobalDevCacheCanBeTrashedButNotAnythingElseInGradle() throws {
        try write(".gradle/caches/modules/g.bin", bytes: 2 * mb)
        try write(".gradle/wrapper/dists/keep.bin", bytes: 2 * mb)
        let roots = CleanupCatalog.roots(home: home, ownBundleID: nil)
        let items = CleanupScanner.scan(categories: [.pkgCaches], home: home, runningBundleIDs: [], ownBundleID: nil).items
        let results = deleter().delete(items.map { DeletionCandidate(item: $0, roots: roots) }, mode: .trash)
        XCTAssertEqual(results.filter(\.isRemoved).count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home + "/.gradle/wrapper/dists/keep.bin"))
        // wrapper, izin listesinde olmadığı için elle hazırlanan aday da reddedilir.
        let wrapper = home + "/.gradle/wrapper"
        var st = stat()
        XCTAssertEqual(lstat(wrapper, &st), 0)
        let candidate = DeletionCandidate(
            path: wrapper, dev: st.st_dev, ino: st.st_ino, bytes: 1, kind: "dev.pkgCaches",
            scope: .directChild(roots: roots.filter { $0.category == .pkgCaches }.map(\.deletionRoot)), displayName: "wrapper")
        XCTAssertEqual(deleter().validate(candidate), .nameNotAllowed)
    }

    // MARK: Proje artıkları

    func testFindsArtifactsAndSkipsNestedOnes() throws {
        try write("Projects/web/node_modules/a/a.bin", bytes: 2 * mb)
        try write("Projects/web/node_modules/a/node_modules/b/b.bin", bytes: 2 * mb)
        try write("Projects/pkg/.build/debug/x.bin", bytes: 2 * mb)
        try write("Projects/ios/DerivedData/D/d.bin", bytes: 2 * mb)
        let items = scanProjects()
        XCTAssertEqual(relNames(items), ["ios/DerivedData", "pkg/.build", "web/node_modules"])
        XCTAssertTrue(items.allSatisfy { $0.category == .projectArtifacts && $0.rootPath == projects && $0.isDirectory })
        XCTAssertGreaterThanOrEqual(items.first { $0.path.hasSuffix("web/node_modules") }?.bytes ?? 0, UInt64(2 * mb))
        XCTAssertFalse(items.contains { $0.path.contains("node_modules/a") }, "iç içe olanda yalnızca dıştaki")
    }

    func testConditionalArtifactsNeedTheirProjectFile() throws {
        try write("Projects/nocargo/target/t.bin", bytes: 2 * mb)
        try write("Projects/rust/Cargo.toml", bytes: 10)
        try write("Projects/rust/target/t.bin", bytes: 2 * mb)
        try write("Projects/nopods/Pods/p.bin", bytes: 2 * mb)
        try write("Projects/ios/Podfile", bytes: 10)
        try write("Projects/ios/Pods/p.bin", bytes: 2 * mb)
        try write("Projects/noGradle/build/b.bin", bytes: 2 * mb)
        try write("Projects/g1/build.gradle", bytes: 10)
        try write("Projects/g1/build/b.bin", bytes: 2 * mb)
        try write("Projects/g2/build.gradle.kts", bytes: 10)
        try write("Projects/g2/build/b.bin", bytes: 2 * mb)
        XCTAssertEqual(relNames(scanProjects()), ["g1/build", "g2/build", "ios/Pods", "rust/target"])
    }

    func testDepthCapHiddenDirsAndSmallArtifacts() throws {
        try write("Projects/a/b/c/d/e/node_modules/x.bin", bytes: 2 * mb) // derinlik 6
        try write("Projects/a/b/c/d/e/f/node_modules/x.bin", bytes: 2 * mb) // derinlik 7
        try write("Projects/.hidden/node_modules/x.bin", bytes: 2 * mb)
        try write("Projects/tiny/node_modules/x.bin", bytes: 1_000)
        XCTAssertEqual(relNames(scanProjects()), ["a/b/c/d/e/node_modules"])
    }

    func testSymlinksAreNeverFollowedOrListed() throws {
        try write("Outside/node_modules/o.bin", bytes: 2 * mb)
        try write("Projects/real/node_modules/r.bin", bytes: 2 * mb)
        try FileManager.default.createDirectory(at: fixture.appending(path: "Projects/linkdir"), withIntermediateDirectories: true)
        XCTAssertEqual(symlink(fixture.appending(path: "Outside").path, projects + "/linked"), 0)
        XCTAssertEqual(symlink(fixture.appending(path: "Outside/node_modules").path, projects + "/linkdir/node_modules"), 0)
        XCTAssertEqual(relNames(scanProjects()), ["real/node_modules"])
    }

    func testSymlinkedProjectRootIsRefused() throws {
        try write("Outside/proj/node_modules/o.bin", bytes: 2 * mb)
        let link = home + "/ProjLink"
        XCTAssertEqual(symlink(fixture.appending(path: "Outside/proj").path, link), 0)
        XCTAssertNil(ProjectArtifactScanner.scan(root: link))
        let out = CleanupScanner.scan(categories: [.projectArtifacts], home: home, runningBundleIDs: [], ownBundleID: nil, projectRoots: [link])
        XCTAssertTrue(out.items.isEmpty)
        XCTAssertEqual(out.states[link], .missing)
        // Depo da sembolik bağı kabul etmez.
        XCTAssertEqual(makeStore().add(link), .symlink)
    }

    func testScannerStatesForRoots() throws {
        try write("Projects/web/node_modules/a.bin", bytes: 2 * mb)
        let missing = home + "/Nope"
        let out = CleanupScanner.scan(categories: [.projectArtifacts], home: home, runningBundleIDs: [], ownBundleID: nil,
                                      projectRoots: [projects, missing, projects])
        XCTAssertEqual(out.states[projects], .scanned)
        XCTAssertEqual(out.states[missing], .missing)
        XCTAssertEqual(out.items.count, 1, "aynı kök iki kez listelenmez")
        // Erişim reddi sahte probe ile.
        let denied = CleanupScanner.scan(categories: [.projectArtifacts], home: home, runningBundleIDs: [], ownBundleID: nil,
                                         projectRoots: [projects], probe: PathProbe { _ in .denied })
        XCTAssertEqual(denied.states[projects], .noAccess)
        XCTAssertTrue(denied.items.isEmpty)
        // Proje artıkları varsayılan taramaya girmez ve seçili gelmez.
        XCTAssertFalse(CleanupCategory.defaultScan.contains(.projectArtifacts))
        XCTAssertFalse(CleanupCategory.projectArtifacts.defaultSelected)
    }

    func testCancellationStopsTheWalk() throws {
        for i in 0..<5 { try write("Projects/p\(i)/node_modules/x.bin", bytes: 2 * mb) }
        var calls = 0
        let items = scanProjects(cancelled: { calls += 1; return calls > 2 })
        XCTAssertLessThan(items.count, 5)
        XCTAssertTrue(scanProjects(cancelled: { true }).isEmpty)
    }

    func testXcodeBlocksDerivedDataArtifacts() throws {
        try write("Projects/ios/DerivedData/D/d.bin", bytes: 2 * mb)
        try write("Projects/web/node_modules/n.bin", bytes: 2 * mb)
        let items = scanProjects(running: [CleanupCatalog.xcodeBundleID])
        XCTAssertEqual(items.first { $0.path.hasSuffix("DerivedData") }?.blockedReason, CleanupCatalog.runningBadge)
        XCTAssertNil(items.first { $0.path.hasSuffix("node_modules") }?.blockedReason)
        let derived = try XCTUnwrap(items.first { $0.path.hasSuffix("DerivedData") })
        let candidate = DeletionCandidate(item: derived, roots: [])
        XCTAssertEqual(deleter(running: [CleanupCatalog.xcodeBundleID]).validate(candidate), .appRunning)
    }

    func testArtifactDeletionGoesThroughDescendantScope() throws {
        try write("Projects/web/node_modules/a/a.bin", bytes: 2 * mb)
        try write("Projects/web/src/main.js", bytes: 10)
        let items = scanProjects()
        XCTAssertEqual(items.count, 1)
        let candidate = DeletionCandidate(item: items[0], roots: [])
        XCTAssertEqual(candidate.kind, "dev.projectArtifacts")
        XCTAssertEqual(candidate.scope, .descendant(roots: [projects], nameAllowlist: DevRules.artifactNames))
        let results = deleter().delete([candidate], mode: .trash)
        XCTAssertEqual(results.first?.isRemoved, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: projects + "/web/node_modules"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: projects + "/web/src/main.js"))
    }

    func testDeleterRefusesNonArtifactNamesAndTheRootItself() throws {
        try write("Projects/web/src/main.js", bytes: 10)
        let scope = ProjectArtifactScanner.scope(root: projects)
        func candidate(_ path: String) -> DeletionCandidate {
            var st = stat()
            _ = lstat(path, &st)
            return DeletionCandidate(path: path, dev: st.st_dev, ino: st.st_ino, bytes: 1, kind: "dev.projectArtifacts", scope: scope, displayName: "x")
        }
        XCTAssertEqual(deleter().validate(candidate(projects + "/web/src")), .nameNotAllowed)
        XCTAssertEqual(deleter().validate(candidate(projects)), .isRoot)
        // Seçilen kök ev klasörünün kendisi olursa reddedilmez ama Library kökü reddedilir.
        try write("Library/Foo/node_modules/x.bin", bytes: 10)
        var st = stat()
        _ = lstat(home + "/Library/Foo/node_modules", &st)
        let libScope = ProjectArtifactScanner.scope(root: home + "/Library")
        let c = DeletionCandidate(path: home + "/Library/Foo/node_modules", dev: st.st_dev, ino: st.st_ino, bytes: 1,
                                  kind: "dev.projectArtifacts", scope: libScope, displayName: "x")
        XCTAssertEqual(deleter().validate(c), .rootNotAllowed)
    }

    // MARK: Proje klasörü deposu

    private func makeStore() -> ProjectFoldersStore {
        let suite = "dev-\(UUID().uuidString)"
        suites.append(suite)
        return ProjectFoldersStore(defaults: UserDefaults(suiteName: suite)!, home: home)
    }

    func testStoreAddsRemovesAndPersists() throws {
        try write("Projects/web/x.txt", bytes: 10)
        let store = makeStore()
        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertNil(store.add(projects))
        let canonical = try XCTUnwrap(CleanupDeleter.realPath(projects))
        XCTAssertEqual(store.folders, [canonical])
        XCTAssertEqual(store.add(projects), .alreadyAdded)
        XCTAssertEqual(ProjectFoldersStore(defaults: store.defaults, home: home).folders, [canonical], "aynı depo yeniden okunur")
        store.remove(canonical)
        XCTAssertTrue(store.folders.isEmpty)
    }

    func testStoreRejectsHomeLibraryFilesAndMissing() throws {
        try write("Library/Foo/x.txt", bytes: 10)
        try write("Projects/file.txt", bytes: 10)
        let store = makeStore()
        XCTAssertEqual(store.add(home), .notAllowed)
        XCTAssertEqual(store.add(home + "/Library"), .notAllowed)
        XCTAssertEqual(store.add(home + "/Library/Foo"), .notAllowed)
        XCTAssertEqual(store.add("/"), .notAllowed)
        XCTAssertEqual(store.add("/System"), .notAllowed)
        XCTAssertEqual(store.add(projects + "/file.txt"), .notDirectory)
        XCTAssertEqual(store.add(home + "/Nope"), .notDirectory)
        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertNotNil(ProjectFoldersStore.AddError.notAllowed.message)
    }

    // MARK: Araç komutları (sahte çalıştırıcı)

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [[String]] = []
        func add(_ call: [String]) { lock.lock(); _calls.append(call); lock.unlock() }
        var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return _calls }
    }

    private func fakeRunner(_ recorder: Recorder, existing: Set<String>, results: [String: CommandResult]) -> CleanupToolRunner {
        CleanupToolRunner(
            run: { exe, args, _ in
                recorder.add([exe] + args)
                return results[(exe as NSString).lastPathComponent + " " + args.joined(separator: " ")] ?? CommandResult(status: 1, output: "unexpected")
            },
            isExecutable: { existing.contains($0) }
        )
    }

    func testBrewPreviewParsesEstimateAndNeverUsesSudoOrRunsCleanup() async throws {
        let rec = Recorder()
        let runner = fakeRunner(rec, existing: ["/opt/homebrew/bin/brew"], results: [
            "brew cleanup -n": CommandResult(status: 0, output: "Would remove: /x/foo (1MB)\n==> This operation would free approximately 1.2GB of disk space.\n"),
        ])
        let outcome = await ToolCommands.preview(.brew, home: home, runner: runner)
        guard case .preview(let p) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(p.estimate, "1.2GB")
        XCTAssertFalse(p.nothingToClean)
        XCTAssertEqual(rec.calls, [["/opt/homebrew/bin/brew", "cleanup", "-n"]], "önizleme yalnızca -n çalıştırır")
        XCTAssertFalse(rec.calls.flatMap { $0 }.contains("sudo"))
    }

    func testBrewEmptyPreviewMeansNothingToClean() async {
        let runner = fakeRunner(Recorder(), existing: ["/usr/local/bin/brew"], results: ["brew cleanup -n": CommandResult(status: 0, output: "")])
        guard case .preview(let p) = await ToolCommands.preview(.brew, home: home, runner: runner) else { return XCTFail() }
        XCTAssertTrue(p.nothingToClean)
    }

    func testMissingBinaryIsUnavailableAndNothingRuns() async {
        let rec = Recorder()
        let runner = fakeRunner(rec, existing: [], results: [:])
        for tool in CleanupTool.allCases {
            XCTAssertNil(ToolCommands.locate(tool, home: home, runner: runner))
            let preview = await ToolCommands.preview(tool, home: home, runner: runner)
            let run = await ToolCommands.execute(tool, home: home, runner: runner)
            XCTAssertEqual(preview, .unavailable)
            XCTAssertEqual(run, .unavailable)
        }
        XCTAssertTrue(rec.calls.isEmpty)
    }

    func testDockerPreviewAndBuilderPruneOnly() async {
        let rec = Recorder()
        let df = """
        TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
        Images          3         1         1.5GB     900MB (60%)
        Build Cache     45        0         2.1GB     2.1GB
        """
        let runner = fakeRunner(rec, existing: ["/usr/local/bin/docker"], results: [
            "docker system df": CommandResult(status: 0, output: df),
            "docker builder prune -f": CommandResult(status: 0, output: "Total:  2.1GB\n"),
        ])
        guard case .preview(let p) = await ToolCommands.preview(.docker, home: home, runner: runner) else { return XCTFail() }
        XCTAssertEqual(p.estimate, "2.1GB")
        let done = await ToolCommands.execute(.docker, home: home, runner: runner)
        XCTAssertEqual(done, .done("Total:  2.1GB"))
        XCTAssertEqual(rec.calls, [["/usr/local/bin/docker", "system", "df"], ["/usr/local/bin/docker", "builder", "prune", "-f"]])
        for tool in CleanupTool.allCases {
            XCTAssertFalse(tool.runArguments.contains("--all") || tool.runArguments.contains("system") && tool == .docker, "imaj/birim silinmez")
        }
    }

    func testDockerDownReportsFailure() async {
        let runner = fakeRunner(Recorder(), existing: ["/usr/local/bin/docker"], results: [
            "docker system df": CommandResult(status: 1, output: "Cannot connect to the Docker daemon at unix:///var/run/docker.sock."),
        ])
        guard case .failed(let text) = await ToolCommands.preview(.docker, home: home, runner: runner) else { return XCTFail() }
        XCTAssertTrue(text.contains("Docker çalışmıyor"), text)
    }

    @MainActor
    func testModelRequiresPreviewBeforeRun() async {
        let rec = Recorder()
        let runner = fakeRunner(rec, existing: ["/opt/homebrew/bin/brew"], results: [
            "brew cleanup -n": CommandResult(status: 0, output: "==> This operation would free approximately 5MB of disk space."),
            "brew cleanup": CommandResult(status: 0, output: "Removing: x\n"),
        ])
        let model = ToolCommandModel(tool: .brew, home: home, runner: runner)
        XCTAssertFalse(model.isAvailable, "oluşturulurken dosya sistemine bakılmaz")
        XCTAssertFalse(model.canRun)
        await model.run()
        XCTAssertTrue(rec.calls.isEmpty, "önizleme olmadan çalıştırılmaz")
        await model.loadPreview()
        XCTAssertTrue(model.isAvailable)
        XCTAssertTrue(model.canRun)
        await model.run()
        XCTAssertEqual(model.phase, .done("Removing: x"))
        XCTAssertEqual(rec.calls.map { $0.dropFirst().joined(separator: " ") }, ["cleanup -n", "cleanup"])
    }

    @MainActor
    func testModelWithoutBinaryIsDisabled() async {
        let model = ToolCommandModel(tool: .docker, home: home, runner: fakeRunner(Recorder(), existing: [], results: [:]))
        model.locate()
        XCTAssertFalse(model.isAvailable)
        await model.loadPreview()
        await model.run()
        XCTAssertFalse(model.canRun)
        XCTAssertEqual(model.phase, .idle, "binary yoksa hiçbir şey başlamaz")
    }
}
