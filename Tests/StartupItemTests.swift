import XCTest
@testable import Adalmon

/// Başlangıç öğeleri: plist ayrıştırma, devre dışı listesi ayrıştırma, yetki denetimi ve eylem sırası.
/// Gerçek ajanlara ASLA dokunulmaz: `launchctl` ve Çöp Kutusu sahte.
final class StartupItemTests: XCTestCase {
    // MARK: plist

    private func plist(_ dict: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    func testParseReadsLabelProgramAndFlags() throws {
        let data = try plist(["Label": "com.example.sync", "ProgramArguments": ["/Applications/Sync.app/Contents/MacOS/sync", "--bg"], "RunAtLoad": true])
        let item = try XCTUnwrap(StartupItemScanner.parse(data: data, path: "/Users/u/Library/LaunchAgents/x.plist", scope: .user))
        XCTAssertEqual(item.label, "com.example.sync")
        XCTAssertEqual(item.program, "/Applications/Sync.app/Contents/MacOS/sync")
        XCTAssertEqual(item.name, "Sync")
        XCTAssertTrue(item.runsAtLoad)
        XCTAssertEqual(item.status, .enabled)
    }

    func testParseHonoursDisabledKeyAndProgramKey() throws {
        let data = try plist(["Label": "com.example.tool", "Program": "/usr/local/bin/tool", "Disabled": true])
        let item = try XCTUnwrap(StartupItemScanner.parse(data: data, path: "/Library/LaunchDaemons/t.plist", scope: .daemon))
        XCTAssertEqual(item.status, .disabled)
        XCTAssertEqual(item.program, "/usr/local/bin/tool")
        XCTAssertEqual(item.name, "tool")
        XCTAssertEqual(item.scope, .daemon)
    }

    func testParseFallsBackToFileNameForBrokenPlist() throws {
        let item = try XCTUnwrap(StartupItemScanner.parse(data: Data("not a plist".utf8), path: "/x/org.foo.bar.plist", scope: .allUsers))
        XCTAssertEqual(item.label, "org.foo.bar")
        XCTAssertEqual(item.status, .unknown)
        let missing = try XCTUnwrap(StartupItemScanner.parse(data: nil, path: "/x/org.foo.baz.plist", scope: .user))
        XCTAssertEqual(missing.label, "org.foo.baz")
    }

    func testOverridesBeatPlistDisabledKey() throws {
        let data = try plist(["Label": "com.example.a", "Disabled": true])
        let item = try XCTUnwrap(StartupItemScanner.parse(data: data, path: "/a.plist", scope: .user))
        XCTAssertEqual(StartupItemScanner.applying(overrides: ["com.example.a": false], to: item).status, .enabled)
        XCTAssertEqual(StartupItemScanner.applying(overrides: ["other": true], to: item).status, .disabled)
        let enabled = try XCTUnwrap(StartupItemScanner.parse(data: plist(["Label": "com.example.b"]), path: "/b.plist", scope: .user))
        XCTAssertEqual(StartupItemScanner.applying(overrides: ["com.example.b": true], to: enabled).status, .disabled)
    }

    func testStatusTitlesAreOpenClosed() {
        XCTAssertEqual(StartupItem.Status.enabled.title, "Açık")
        XCTAssertEqual(StartupItem.Status.disabled.title, "Kapalı")
    }

    // MARK: print-disabled

    func testDisabledParserHandlesBothSyntaxes() {
        let output = """
        disabled services = {
        \t"com.docker.helper" => enabled
        \t"berqnet-connect-service" => disabled
        \t"old.style" => true
        \t"old.enabled" => false
        \t"weird" => maybe
        }
        """
        let parsed = LaunchctlDisabledParser.parse(output)
        XCTAssertEqual(parsed, ["com.docker.helper": false, "berqnet-connect-service": true, "old.style": true, "old.enabled": false])
    }

    func testDisabledParserIgnoresGarbageAndEmpty() {
        XCTAssertEqual(LaunchctlDisabledParser.parse(""), [:])
        XCTAssertEqual(LaunchctlDisabledParser.parse("Could not find domain\n\"=> disabled\n"), [:])
    }

    // MARK: komutlar

    func testCommandArguments() {
        let gui = LaunchctlDomain.gui(uid: 501)
        XCTAssertEqual(LaunchctlCommand.bootout(gui, label: "a.b").arguments, ["bootout", "gui/501/a.b"])
        XCTAssertEqual(LaunchctlCommand.disable(gui, label: "a.b").arguments, ["disable", "gui/501/a.b"])
        XCTAssertEqual(LaunchctlCommand.enable(gui, label: "a.b").arguments, ["enable", "gui/501/a.b"])
        XCTAssertEqual(LaunchctlCommand.bootstrap(gui, plistPath: "/p/a.plist").arguments, ["bootstrap", "gui/501", "/p/a.plist"])
        XCTAssertEqual(LaunchctlCommand.printDisabled(.system).arguments, ["print-disabled", "system"])
    }

    func testLabelValidation() {
        XCTAssertTrue(LaunchctlCommand.isValidLabel("homebrew.mxcl.postgresql@17"))
        XCTAssertFalse(LaunchctlCommand.isValidLabel(""))
        XCTAssertFalse(LaunchctlCommand.isValidLabel("a/b"))
        XCTAssertFalse(LaunchctlCommand.isValidLabel("a b"))
        XCTAssertFalse(LaunchctlCommand.isValidLabel("a\nb"))
    }

    // MARK: bozuk ajan

    private func parsed(_ dict: [String: Any], missing: Set<String> = [], scope: StartupItem.Scope = .user) throws -> StartupItem {
        try XCTUnwrap(StartupItemScanner.parse(data: plist(dict), path: "/Users/u/Library/LaunchAgents/x.plist", scope: scope,
                                               isMissing: { missing.contains($0) }))
    }

    func testBrokenWhenProgramPathIsMissing() throws {
        let item = try parsed(["Label": "com.example.gone", "ProgramArguments": ["/Applications/Gone.app/Contents/MacOS/gone"]],
                              missing: ["/Applications/Gone.app/Contents/MacOS/gone"])
        XCTAssertTrue(item.isBroken)
        XCTAssertEqual(item.problem, .programMissing("/Applications/Gone.app/Contents/MacOS/gone"))
        let direct = try parsed(["Label": "com.example.gone2", "Program": "/opt/x/bin/x"], missing: ["/opt/x/bin/x"])
        XCTAssertEqual(direct.problem, .programMissing("/opt/x/bin/x"))
    }

    func testBrokenWhenNoProgramKeys() throws {
        XCTAssertEqual(try parsed(["Label": "com.example.empty"]).problem, .noProgram)
        XCTAssertEqual(try parsed(["Label": "com.example.empty2", "ProgramArguments": [String]()]).problem, .noProgram)
    }

    func testNotBrokenWhenProgramExistsOrUnverifiable() throws {
        XCTAssertFalse(try parsed(["Label": "com.example.ok", "Program": "/bin/ls"]).isBroken)
        XCTAssertFalse(try parsed(["Label": "com.example.rel", "ProgramArguments": ["sh", "-c", "true"]], missing: ["sh"]).isBroken)
        XCTAssertFalse(try parsed(["Label": "com.example.vol", "Program": "/Volumes/Ext/tool"], missing: ["/Volumes/Ext/tool"]).isBroken)
        XCTAssertFalse(try parsed(["Label": "com.example.bundle", "BundleProgram": "Contents/MacOS/x"]).isBroken)
        XCTAssertFalse(try parsed(["Label": "com.apple.thing", "Program": "/nope"], missing: ["/nope"]).isBroken)
        XCTAssertFalse(try XCTUnwrap(StartupItemScanner.parse(data: Data("not a plist".utf8), path: "/x/org.foo.plist", scope: .user)).isBroken)
    }

    func testDefaultMissingCheckUsesRealFilesOnlyInFixture() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "startup-broken-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let present = dir.appending(path: "tool")
        try Data("#!/bin/sh\n".utf8).write(to: present)
        let absent = dir.appending(path: "gone").path

        XCTAssertFalse(StartupItemScanner.isDefinitelyMissing(present.path))
        XCTAssertTrue(StartupItemScanner.isDefinitelyMissing(absent))
        XCTAssertTrue(StartupItemScanner.isDefinitelyMissing(present.path + "/child")) // ENOTDIR

        let agents = dir.appending(path: "LaunchAgents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        for (name, program) in [("com.ok", present.path), ("com.bad", absent)] {
            let data = try plist(["Label": name, "ProgramArguments": [program]])
            try data.write(to: agents.appending(path: "\(name).plist"))
        }
        let items = StartupItemScanner.readPlists(in: [(agents, .user)])
        XCTAssertEqual(items.filter(\.isBroken).map(\.label), ["com.bad"])
    }

    // MARK: yönetici komutu (yalnızca metin)

    func testAdminCommandForGlobalItemsOnly() throws {
        let daemon = try parsed(["Label": "com.example.daemon", "Program": "/bin/ls"], scope: .daemon)
        XCTAssertEqual(StartupItemCommands.adminCommand(for: daemon, uid: 501),
                       "sudo launchctl bootout system/com.example.daemon; sudo launchctl disable system/com.example.daemon")
        let agent = try parsed(["Label": "com.example.agent", "Program": "/bin/ls"], scope: .allUsers)
        XCTAssertEqual(StartupItemCommands.adminCommand(for: agent, uid: 501),
                       "sudo launchctl bootout gui/501/com.example.agent; sudo launchctl disable gui/501/com.example.agent")
        XCTAssertNil(StartupItemCommands.adminCommand(for: try parsed(["Label": "com.example.user", "Program": "/bin/ls"]), uid: 501))
        XCTAssertNil(StartupItemCommands.adminCommand(for: try parsed(["Label": "com.apple.x", "Program": "/bin/ls"], scope: .daemon), uid: 501))
    }

    func testAdminCommandQuotesUnsafeLabels() throws {
        let item = try parsed(["Label": "com.ex ample;rm", "Program": "/bin/ls"], scope: .daemon)
        XCTAssertNil(StartupItemCommands.adminCommand(for: item), "boşluklu etiket geçersiz sayılır")
        XCTAssertEqual(StartupItemCommands.shellQuoted("a;b"), "'a;b'")
        XCTAssertEqual(StartupItemCommands.shellQuoted("it's"), "'it'\\''s'")
        XCTAssertEqual(StartupItemCommands.shellQuoted("gui/501/com.x-y_z"), "gui/501/com.x-y_z")
    }

    // MARK: yetki

    func testPermissionGating() {
        let user = StartupItemPermissions.evaluate(label: "com.example.sync", scope: .user)
        XCTAssertTrue(user.canModify)
        XCTAssertNil(user.reason)

        for scope in [StartupItem.Scope.allUsers, .daemon] {
            let root = StartupItemPermissions.evaluate(label: "com.example.sync", scope: scope)
            XCTAssertFalse(root.canModify)
            XCTAssertEqual(root.reason, "Yönetici izni gerekir")
            XCTAssertTrue(root.needsAdmin)
        }
        for scope in [StartupItem.Scope.user, .allUsers, .daemon] {
            let apple = StartupItemPermissions.evaluate(label: "com.apple.something", scope: scope)
            XCTAssertFalse(apple.canModify)
            XCTAssertFalse(apple.needsAdmin)
        }
        XCTAssertFalse(StartupItemPermissions.evaluate(label: AdalmonIdentity.appBundleID + ".helper", scope: .user).canModify)
        XCTAssertFalse(StartupItemPermissions.evaluate(label: "bad/label", scope: .user).canModify)
    }

    func testRemovalPathMustBeDirectChildOfUserLaunchAgents() {
        let home = URL(filePath: "/Users/u", directoryHint: .isDirectory)
        XCTAssertTrue(StartupItemActions.isInUserLaunchAgents(path: "/Users/u/Library/LaunchAgents/a.plist", home: home))
        XCTAssertFalse(StartupItemActions.isInUserLaunchAgents(path: "/Library/LaunchAgents/a.plist", home: home))
        XCTAssertFalse(StartupItemActions.isInUserLaunchAgents(path: "/Users/u/Library/LaunchAgents/../Documents/a.plist", home: home))
        XCTAssertFalse(StartupItemActions.isInUserLaunchAgents(path: "/Users/u/Library/LaunchAgents/sub/a.plist", home: home))
        XCTAssertFalse(StartupItemActions.isInUserLaunchAgents(path: "/Users/u/Library/LaunchAgents/a.txt", home: home))
    }

    // MARK: eylemler (sahte launchctl / Çöp Kutusu)

    private let home = URL(filePath: "/Users/u", directoryHint: .isDirectory)

    private func item(_ label: String, scope: StartupItem.Scope = .user, dir: String = "/Users/u/Library/LaunchAgents") -> StartupItem {
        StartupItem(label: label, name: label, plistPath: "\(dir)/\(label).plist", program: nil, scope: scope, status: .enabled, runsAtLoad: true)
    }

    private func actions(_ runner: FakeLaunchctl, _ trasher: FakeTrasher) -> StartupItemActions {
        StartupItemActions(launchctl: runner, trasher: trasher, uid: 501, home: home)
    }

    func testDisableBootsOutThenDisables() async {
        let runner = FakeLaunchctl(), trasher = FakeTrasher()
        let outcome = await actions(runner, trasher).disable(item("com.example.sync"))
        XCTAssertEqual(outcome, .success)
        XCTAssertEqual(runner.calls, [.bootout(.gui(uid: 501), label: "com.example.sync"), .disable(.gui(uid: 501), label: "com.example.sync")])
        XCTAssertTrue(trasher.urls.isEmpty)
    }

    func testDisableReportsFailureOfDisableStep() async {
        let runner = FakeLaunchctl(failing: [.disable(.gui(uid: 501), label: "x.y")])
        let outcome = await actions(runner, FakeTrasher()).disable(item("x.y"))
        guard case .failed = outcome else { return XCTFail("beklenen .failed, gelen \(outcome)") }
    }

    func testBootoutFailureIsIgnored() async {
        let runner = FakeLaunchctl(failing: [.bootout(.gui(uid: 501), label: "x.y")])
        let outcome = await actions(runner, FakeTrasher()).disable(item("x.y"))
        XCTAssertEqual(outcome, .success)
    }

    func testEnableEnablesThenBootstraps() async {
        let runner = FakeLaunchctl()
        let target = item("com.example.sync")
        let outcome = await actions(runner, FakeTrasher()).enable(target)
        XCTAssertEqual(outcome, .success)
        XCTAssertEqual(runner.calls, [.enable(.gui(uid: 501), label: "com.example.sync"), .bootstrap(.gui(uid: 501), plistPath: target.plistPath)])
    }

    func testRemoveBootsOutAndTrashesPlist() async {
        let runner = FakeLaunchctl(), trasher = FakeTrasher()
        let target = item("com.example.sync")
        let outcome = await actions(runner, trasher).remove(target)
        XCTAssertEqual(outcome, .success)
        XCTAssertEqual(runner.calls, [.bootout(.gui(uid: 501), label: "com.example.sync")])
        XCTAssertEqual(trasher.urls.map(\.path), [target.plistPath])
    }

    func testRemoveFailureWhenTrashingFails() async {
        let trasher = FakeTrasher(shouldFail: true)
        let outcome = await actions(FakeLaunchctl(), trasher).remove(item("a.b.c"))
        guard case .failed = outcome else { return XCTFail("beklenen .failed, gelen \(outcome)") }
    }

    func testRootOwnedAndAppleItemsAreNeverTouched() async {
        let runner = FakeLaunchctl(), trasher = FakeTrasher()
        let a = actions(runner, trasher)
        let targets = [item("com.example.root", scope: .allUsers, dir: "/Library/LaunchAgents"),
                       item("com.example.daemon", scope: .daemon, dir: "/Library/LaunchDaemons"),
                       item("com.apple.thing")]
        for target in targets {
            for outcome in [await a.disable(target), await a.enable(target), await a.remove(target)] {
                guard case .denied = outcome else { return XCTFail("\(target.label): beklenen .denied, gelen \(outcome)") }
            }
        }
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertTrue(trasher.urls.isEmpty)
    }

    func testRemoveRefusesPlistOutsideUserLaunchAgents() async {
        let runner = FakeLaunchctl(), trasher = FakeTrasher()
        let outcome = await actions(runner, trasher).remove(item("com.example.sync", scope: .user, dir: "/Users/u/Documents"))
        guard case .denied = outcome else { return XCTFail("beklenen .denied, gelen \(outcome)") }
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertTrue(trasher.urls.isEmpty)
    }

    // MARK: tarama (sahte launchctl, geçici klasör)

    func testScanAppliesOverridesPerDomain() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "startup-\(UUID().uuidString)", directoryHint: .isDirectory)
        let userDir = tmp.appending(path: "user", directoryHint: .isDirectory)
        let daemonDir = tmp.appending(path: "daemon", directoryHint: .isDirectory)
        for dir in [userDir, daemonDir] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: tmp) }
        try plist(["Label": "com.example.u"]).write(to: userDir.appending(path: "com.example.u.plist"))
        try plist(["Label": "com.example.d"]).write(to: daemonDir.appending(path: "com.example.d.plist"))
        let runner = FakeLaunchctl(outputs: [.printDisabled(.gui(uid: 501)): "\t\"com.example.u\" => disabled",
                                             .printDisabled(.system): "\t\"com.example.d\" => enabled\n\t\"com.example.u\" => disabled"])
        let items = await StartupItemScanner.scan(launchctl: runner, uid: 501, directories: [(userDir, .user), (daemonDir, .daemon)])
        XCTAssertEqual(items.first { $0.label == "com.example.u" }?.status, .disabled)
        XCTAssertEqual(items.first { $0.label == "com.example.d" }?.status, .enabled)
    }
}

/// Çağrıları kaydeden sahte `launchctl`; gerçek bir şey çalıştırmaz.
final class FakeLaunchctl: LaunchctlRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [LaunchctlCommand] = []
    private let failing: Set<LaunchctlCommand>
    private let outputs: [LaunchctlCommand: String]

    init(failing: Set<LaunchctlCommand> = [], outputs: [LaunchctlCommand: String] = [:]) {
        self.failing = failing
        self.outputs = outputs
    }

    var calls: [LaunchctlCommand] { lock.withLock { recorded } }

    func run(_ command: LaunchctlCommand) async -> CommandResult {
        lock.withLock { recorded.append(command) }
        return CommandResult(status: failing.contains(command) ? 1 : 0, output: outputs[command] ?? "")
    }
}

final class FakeTrasher: FileTrashing, @unchecked Sendable {
    struct Failure: Error {}
    private let lock = NSLock()
    private var trashed: [URL] = []
    private let shouldFail: Bool

    init(shouldFail: Bool = false) { self.shouldFail = shouldFail }

    var urls: [URL] { lock.withLock { trashed } }

    func trash(_ url: URL) async throws {
        if shouldFail { throw Failure() }
        lock.withLock { trashed.append(url) }
    }
}
