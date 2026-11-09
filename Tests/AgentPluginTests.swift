import XCTest
@testable import Adalmon

/// Plugin üretimi YALNIZCA geçici dizine; gerçek `claude` komutu ve ~/.claude ASLA kullanılmaz (sahte `CommandRunning`).
final class AgentPluginTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appending(path: "agent-plugin-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func generator(python: Bool = true) -> AgentPluginGenerator {
        AgentPluginGenerator(root: tmp.appending(path: "ClaudePlugin", directoryHint: .isDirectory), usesPython: python)
    }

    private func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    // MARK: Üretici

    func testGeneratedFilesAndJSONValidity() throws {
        let g = generator()
        try g.write(port: 51234, token: "abc")
        let manifest = try json(g.manifestURL)
        XCTAssertEqual(manifest["name"] as? String, "adalmon-agents")
        let market = try json(g.marketplaceURL)
        XCTAssertEqual(market["name"] as? String, "adalmon-local")
        let plugins = try XCTUnwrap(market["plugins"] as? [[String: Any]])
        XCTAssertEqual(plugins.first?["name"] as? String, "adalmon-agents")
        XCTAssertEqual(plugins.first?["source"] as? String, "./plugins/adalmon-agents")

        let hooks = try XCTUnwrap(try json(g.hooksURL)["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), Set(["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                                             "PermissionRequest", "Notification", "Stop", "SubagentStart", "SubagentStop", "PostModelSwitch"]))
        for (_, value) in hooks {
            let entry = try XCTUnwrap((value as? [[String: Any]])?.first)
            let command = try XCTUnwrap((entry["hooks"] as? [[String: Any]])?.first)
            XCTAssertEqual(command["type"] as? String, "command")
            XCTAssertEqual(command["async"] as? Bool, true)
            XCTAssertEqual(command["timeout"] as? Int, 5)
            XCTAssertEqual(command["command"] as? String, "/usr/bin/python3 \"${CLAUDE_PLUGIN_ROOT}/scripts/forward.py\"")
        }
        for url in [g.pythonScriptURL, g.shellScriptURL] {
            let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
            XCTAssertEqual(mode, 0o755)
        }
    }

    func testShellFallbackCommandAndConfigPermissions() throws {
        let g = generator(python: false)
        XCTAssertTrue(g.hookCommand.hasPrefix("/bin/sh "))
        try g.write(port: 50000, token: "t0k")
        let mode = try FileManager.default.attributesOfItem(atPath: g.configURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        XCTAssertEqual(g.readConfig()?.port, 50000)
        XCTAssertEqual(g.readConfig()?.token, "t0k")
        XCTAssertFalse(FileManager.default.fileExists(atPath: g.pluginDirectory.appending(path: "config.json").path), "config plugin dizininde değil")
        try g.writeConfig(port: 50001, token: "t0k")
        XCTAssertEqual(g.readConfig()?.port, 50001)
    }

    func testTokenIs32RandomBytesHex() {
        let a = AgentPluginGenerator.makeToken(), b = AgentPluginGenerator.makeToken()
        XCTAssertEqual(a.count, 64)
        XCTAssertNotEqual(a, b)
        XCTAssertNotNil(a.range(of: "^[0-9a-f]{64}$", options: .regularExpression))
    }

    // MARK: Forward betiği süzmesi

    private let sample = """
    {"hook_event_name":"PostToolUse","session_id":"sess-1","transcript_path":"/Users/x/.claude/SECRET-TRANSCRIPT.jsonl",
     "cwd":"/Users/x/projects/MyApp/","permission_mode":"default","tool_name":"Agent","agent_id":"a1","agent_type":"Explore",
     "prompt":"SECRET-PROMPT","tool_input":{"prompt":"SECRET-INPUT","command":"SECRET-CMD"},
     "tool_response":{"agentId":"a1","resolvedModel":"claude-haiku-4-5","content":"SECRET-OUTPUT"},
     "last_assistant_message":"SECRET-ASSISTANT","compact_summary":"SECRET-SUMMARY","model":"claude-opus-4-8",
     "session_title":"Düzelt: giriş ekranı"}
    """

    /// `viaShell`: betik `sh -c '...; exit 0'` ara kabuğu (fork'lanan) altında çalışır; Claude'un hook'u kabukla çalıştırmasını taklit eder.
    private func runScript(_ interpreter: String, _ script: URL, stdin: String, viaShell: Bool = false) throws -> [String: Any] {
        let process = Process()
        // Betik yapılandırmayı (showTargets) bu yoldan okur; gerçek kullanıcı yapılandırması ASLA okunmaz.
        process.environment = ProcessInfo.processInfo.environment.merging(["ADALMON_AGENTS_CONFIG": tmp.appending(path: "ClaudePlugin/config.json").path]) { $1 }
        let arguments = (interpreter.hasSuffix("python3") ? ["-I"] : []) + [script.path, "--dry-run"]
        if viaShell {
            process.executableURL = URL(filePath: "/bin/sh")
            process.arguments = ["-c", "\"$0\" \"$@\"; exit 0", interpreter] + arguments
        } else {
            process.executableURL = URL(filePath: interpreter)
            process.arguments = arguments
        }
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("SECRET"), "içerik alanı sızdı: \(text)")
        XCTAssertFalse(text.contains("transcript"))
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func assertFiltered(_ payload: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(Set(payload.keys).isSubset(of: AgentEvent.allowedKeys), "izinsiz anahtar: \(payload.keys)", file: file, line: line)
        XCTAssertEqual(payload["event"] as? String, "PostToolUse", file: file, line: line)
        XCTAssertEqual(payload["session_id"] as? String, "sess-1", file: file, line: line)
        XCTAssertEqual(payload["project"] as? String, "MyApp", "yalnızca son klasör adı", file: file, line: line)
        XCTAssertEqual(payload["resolved_model"] as? String, "claude-haiku-4-5", file: file, line: line)
        XCTAssertEqual(payload["resolved_agent_id"] as? String, "a1", file: file, line: line)
        XCTAssertEqual(payload["model"] as? String, "claude-opus-4-8", file: file, line: line)
        XCTAssertEqual(payload["session_title"] as? String, "Düzelt: giriş ekranı", "oturum adı geçer (prompt geçmez)", file: file, line: line)
        XCTAssertNotNil(payload["ts"], file: file, line: line)
    }

    func testPythonForwardScriptFiltersContent() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3"), AgentPluginGenerator.pythonAvailable() else {
            throw XCTSkip("/usr/bin/python3 yok")
        }
        let g = generator()
        try g.write(port: 1, token: "x")
        let payload = try runScript("/usr/bin/python3", g.pythonScriptURL, stdin: sample)
        assertFiltered(payload)
        // Agent aracı değilse çözümlenmiş model alınmaz; bozuk girdi sessiz kalır.
        let other = try runScript("/usr/bin/python3", g.pythonScriptURL, stdin: sample.replacingOccurrences(of: "\"tool_name\":\"Agent\"", with: "\"tool_name\":\"Bash\""))
        XCTAssertNil(other["resolved_model"])
        XCTAssertTrue(try runScript("/usr/bin/python3", g.pythonScriptURL, stdin: "garbage SECRET").isEmpty)
    }

    func testPythonSessionTitleSanitizing() throws {
        guard AgentPluginGenerator.pythonAvailable() else { throw XCTSkip("/usr/bin/python3 yok") }
        let g = generator()
        try g.write(port: 1, token: "x")
        func title(_ raw: String) throws -> String? {
            let json = #"{"hook_event_name":"SessionStart","session_id":"s","session_title":"\#(raw)","prompt":"SECRET"}"#
            return try runScript("/usr/bin/python3", g.pythonScriptURL, stdin: json)["session_title"] as? String
        }
        XCTAssertEqual(try title(#"a\u0001b\nc\t\u007fd"#), "a b c d", "kontrol karakterleri temizlenir")
        XCTAssertEqual(try title(String(repeating: "x", count: 300))?.count, 200)
        XCTAssertNil(try title(#"  \n "#), "boş ad iletilmez")
    }

    func testShellSessionTitleSanitizing() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/plutil") else { throw XCTSkip("plutil yok") }
        let g = generator(python: false)
        try g.write(port: 1, token: "x")
        func title(_ raw: String) throws -> String? {
            let json = #"{"hook_event_name":"SessionStart","session_id":"s","session_title":"\#(raw)","prompt":"SECRET"}"#
            return try runScript("/bin/sh", g.shellScriptURL, stdin: json)["session_title"] as? String
        }
        XCTAssertEqual(try title(#"a\u0001b\"q\\r"#), "abqr", "kontrol, tırnak ve ters eğik çizgi atılır")
        XCTAssertEqual(try title(String(repeating: "ş", count: 300))?.count, 200)
        XCTAssertNil(try title(#"\n"#))
    }

    /// Hook komutunun üst süreci (burada test süreci) `pid` olarak geçer; ara kabuk (sh -c) atlanır; prompt yine geçmez.
    func testPythonForwardsParentPIDSkippingShells() throws {
        guard AgentPluginGenerator.pythonAvailable() else { throw XCTSkip("/usr/bin/python3 yok") }
        let g = generator()
        try g.write(port: 1, token: "x")
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(try runScript("/usr/bin/python3", g.pythonScriptURL, stdin: sample)["pid"] as? Int, me)
        XCTAssertEqual(try runScript("/usr/bin/python3", g.pythonScriptURL, stdin: sample, viaShell: true)["pid"] as? Int, me,
                       "ara kabuk atlanıp Claude (burada test) süreci seçilir")
        XCTAssertTrue(AgentEvent.allowedKeys.contains("pid"))
    }

    func testShellForwardsParentPIDSkippingShells() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/plutil") else { throw XCTSkip("plutil yok") }
        let g = generator(python: false)
        try g.write(port: 1, token: "x")
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(try runScript("/bin/sh", g.shellScriptURL, stdin: sample)["pid"] as? Int, me)
        XCTAssertEqual(try runScript("/bin/sh", g.shellScriptURL, stdin: sample, viaShell: true)["pid"] as? Int, me)
    }

    func testPythonScriptExitsZeroWhenNoListener() throws {
        guard AgentPluginGenerator.pythonAvailable() else { throw XCTSkip("/usr/bin/python3 yok") }
        let g = generator()
        try g.write(port: 1, token: "x")   // port 1: bağlantı reddedilir
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/python3")
        process.arguments = ["-I", g.pythonScriptURL.path]
        process.environment = ["ADALMON_AGENTS_CONFIG": g.configURL.path]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data(sample.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testShellFallbackScriptFiltersContent() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/plutil") else { throw XCTSkip("plutil yok") }
        let g = generator(python: false)
        try g.write(port: 1, token: "x")
        let payload = try runScript("/bin/sh", g.shellScriptURL, stdin: sample)
        assertFiltered(payload)
    }

    // MARK: Hedef (dosya adı / komut adı) süzmesi

    private func preToolUse(_ tool: String, input: String, event: String = "PreToolUse") -> String {
        #"{"hook_event_name":"\#(event)","session_id":"sess-1","cwd":"/x/p","tool_name":"\#(tool)","tool_input":\#(input),"prompt":"SECRET-PROMPT"}"#
    }

    /// Dizeyi JSON dize değişmezine çevirir (tırnaklı).
    private func jsonString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value])) ?? Data()
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }

    /// Gerçek betik çalıştırması: showTargets açıkken yalnızca dosya adı / komut adı; içerik, argüman, yol asla.
    private func assertTargetFiltering(_ interpreter: String, usesPython: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let g = generator(python: usesPython)
        try g.write(port: 1, token: "x")
        let script = usesPython ? g.pythonScriptURL : g.shellScriptURL
        func target(_ tool: String, _ input: String, event: String = "PreToolUse") throws -> String? {
            let payload = try runScript(interpreter, script, stdin: preToolUse(tool, input: input, event: event))
            XCTAssertTrue(Set(payload.keys).isSubset(of: AgentEvent.allowedKeys), "izinsiz anahtar: \(payload.keys)", file: file, line: line)
            return payload["target"] as? String
        }
        func bash(_ command: String) throws -> String? { try target("Bash", #"{"command":\#(jsonString(command)),"description":"SECRET-DESC"}"#) }

        // Anahtar kapalı (varsayılan): hiçbir hedef.
        XCTAssertFalse(g.readShowTargets())
        XCTAssertNil(try target("Edit", #"{"file_path":"/a/b/main.swift","new_string":"SECRET-BODY"}"#), "showTargets=false: hedef yok", file: file, line: line)
        XCTAssertNil(try bash("swift build"), "showTargets=false: hedef yok", file: file, line: line)

        try g.setShowTargets(true)
        XCTAssertTrue(g.readShowTargets())
        for tool in ["Edit", "Write", "MultiEdit", "Read"] {
            XCTAssertEqual(try target(tool, #"{"file_path":"/a/b/main.swift","content":"SECRET-BODY","old_string":"SECRET-OLD"}"#), "main.swift", tool, file: file, line: line)
        }
        XCTAssertEqual(try target("NotebookEdit", #"{"notebook_path":"/n/deep/analiz.ipynb","new_source":"SECRET-SRC"}"#), "analiz.ipynb", file: file, line: line)
        XCTAssertEqual(try target("Edit", #"{"file_path":"/a/ma\u0001in.swift"}"#), "main.swift", "kontrol karakteri atılır", file: file, line: line)
        XCTAssertEqual(try target("Edit", #"{"file_path":"/a/\#(String(repeating: "u", count: 80)).swift"}"#)?.count, 40, "en çok 40 karakter", file: file, line: line)
        XCTAssertNil(try target("Edit", #"{"file_path":"/"}"#), file: file, line: line)
        XCTAssertNil(try target("Edit", #"{"new_string":"SECRET"}"#), "dosya yolu yoksa hedef yok", file: file, line: line)

        XCTAssertEqual(try bash("FOO=bar swift build --x"), "swift", file: file, line: line)
        XCTAssertEqual(try bash("sudo " + "r" + "m -f x"), "rm", file: file, line: line)
        XCTAssertEqual(try bash("env A=1 B=2 nohup node server.js --port SECRET"), "node", file: file, line: line)
        XCTAssertEqual(try bash("git commit -m SECRET-MSG"), "git", "yalnızca ilk kelime", file: file, line: line)
        XCTAssertNil(try bash("sudo -u root ls x"), "bayraklı önekten sonra emin olunamaz", file: file, line: line)
        XCTAssertNil(try bash("/usr/bin/swift build"), "yol gönderilmez", file: file, line: line)
        XCTAssertNil(try bash("./run.sh SECRET"), "yol gönderilmez", file: file, line: line)
        XCTAssertNil(try bash(#"FOO="a b SECRET" swift build"#), "tırnaklı atama: emin olunamaz", file: file, line: line)
        XCTAssertNil(try bash("ls; echo SECRET"), "özel karakter", file: file, line: line)
        XCTAssertNil(try bash("$(whoami) x"), file: file, line: line)
        XCTAssertNil(try bash(String(repeating: "a", count: 30) + " x"), "24 karakterden uzun komut adı", file: file, line: line)
        XCTAssertNil(try bash("   "), file: file, line: line)

        for (tool, input) in [("Grep", #"{"pattern":"SECRET-PAT","path":"/a/b.swift"}"#), ("Glob", #"{"pattern":"**/SECRET.swift"}"#),
                              ("WebSearch", #"{"query":"SECRET-Q"}"#), ("WebFetch", #"{"url":"https://x.test/SECRET"}"#),
                              ("Task", #"{"prompt":"SECRET-TASK","file_path":"/a/b.swift"}"#), ("TodoWrite", #"{"file_path":"/a/b.swift"}"#)] {
            XCTAssertNil(try target(tool, input), "\(tool): hedef gönderilmez", file: file, line: line)
        }
        XCTAssertNil(try target("Edit", #"{"file_path":"/a/b/main.swift"}"#, event: "PostToolUse"), "yalnızca PreToolUse", file: file, line: line)

        try g.setShowTargets(false)
        XCTAssertNil(try target("Edit", #"{"file_path":"/a/b/main.swift"}"#), file: file, line: line)
    }

    func testPythonTargetFiltering() throws {
        guard AgentPluginGenerator.pythonAvailable() else { throw XCTSkip("/usr/bin/python3 yok") }
        try assertTargetFiltering("/usr/bin/python3", usesPython: true)
    }

    func testShellTargetFiltering() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/plutil") else { throw XCTSkip("plutil yok") }
        try assertTargetFiltering("/bin/sh", usesPython: false)
    }

    func testShowTargetsConfigKeepsPortTokenAndMode() throws {
        let g = generator()
        XCTAssertFalse(g.readShowTargets(), "yapılandırma yokken kapalı")
        try g.setShowTargets(true)   // plugin kurulmadan da yazılabilir (port/token henüz yok)
        XCTAssertNil(g.readConfig())
        try g.writeConfig(port: 51000, token: "tok")
        XCTAssertTrue(g.readShowTargets(), "port/token yazımı anahtarı bozmaz")
        XCTAssertEqual(g.readConfig()?.port, 51000)
        try g.write(port: 51001, token: "tok")   // plugin (yeniden) kurulumu da korur
        XCTAssertTrue(g.readShowTargets())
        try g.setShowTargets(false)
        XCTAssertEqual(g.readConfig()?.port, 51001)
        XCTAssertEqual(g.readConfig()?.token, "tok")
        XCTAssertFalse(g.readShowTargets())
        try g.writeConfig(port: 51002, token: "tok", showTargets: true)
        XCTAssertTrue(g.readShowTargets())
        let mode = try FileManager.default.attributesOfItem(atPath: g.configURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    // MARK: Sürüm kilidi

    /// Betikler değişince özet değişir ve bu test kırılır: `AgentPluginGenerator.version` artırılıp buradaki eşleme güncellenmeli
    /// (aksi halde kullanıcıdaki Claude önbelleği eski betiği çalıştırmaya devam eder).
    func testScriptDigestPinsVersion() {
        let pinned = ["1.3.0": "d6042c9f478a14e4"]
        XCTAssertEqual(pinned[AgentPluginGenerator.version], AgentPluginGenerator.scriptsDigest,
                       "betik değişti: version'ı artır ve özeti güncelle (\(AgentPluginGenerator.scriptsDigest))")
        let g = generator()
        XCTAssertEqual(g.manifestJSON["version"] as? String, AgentPluginGenerator.version)
        XCTAssertEqual((g.marketplaceJSON["plugins"] as? [[String: Any]])?.first?["version"] as? String, AgentPluginGenerator.version)
    }

    func testInstalledVersionParsingFromListJSON() {
        let list = """
        [{"id":"other@x","version":"9.9.9"},{"id":"adalmon-agents@adalmon-local","version":"1.0.0","enabled":true}]
        """
        XCTAssertEqual(AgentPluginInstaller.installedVersion(listJSON: list), "1.0.0")
        XCTAssertNil(AgentPluginInstaller.installedVersion(listJSON: #"[{"id":"other@x","version":"1"}]"#))
        XCTAssertNil(AgentPluginInstaller.installedVersion(listJSON: "not json"))
        XCTAssertNil(AgentPluginInstaller.installedVersion(listJSON: ""))
    }

    func testUpdateCommandSequenceWritesFilesFirst() async throws {
        let runner = FakeRunner()
        let sut = installer(runner: runner)
        try await sut.update(port: 50124, token: "tok")
        XCTAssertEqual(runner.calls, [
            ["/fake/claude", "plugin", "marketplace", "update", "adalmon-local"],
            ["/fake/claude", "plugin", "update", "adalmon-agents@adalmon-local"],
        ])
        XCTAssertEqual(sut.generator.readConfig()?.port, 50124)
        let script = try String(contentsOf: sut.generator.pythonScriptURL, encoding: .utf8)
        XCTAssertTrue(script.contains("session_title"), "güncel betik komutlardan önce diske yazılır")
        XCTAssertEqual(sut.manualUpdateCommands.count, 2)
    }

    func testUpdateFailureAndMissingCLI() async throws {
        let failing = installer(runner: FakeRunner(results: ["update": CommandResult(status: 1, output: "nope")]))
        do {
            try await failing.update(port: 1, token: "t")
            XCTFail("hata beklenirdi")
        } catch let error as AgentPluginInstaller.InstallError {
            XCTAssertEqual(error, .commandFailed(step: "Plugin güncelleme", output: "nope\nnope"))
        }
        let runner = FakeRunner()
        do {
            try await installer(runner: runner, cli: nil).update(port: 1, token: "t")
            XCTFail("hata beklenirdi")
        } catch let error as AgentPluginInstaller.InstallError {
            XCTAssertEqual(error, .cliNotFound)
        }
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testInstalledVersionUsesListJSON() async {
        let runner = FakeRunner(results: ["list": CommandResult(status: 0, output: #"[{"id":"adalmon-agents@adalmon-local","version":"1.0.0"}]"#)])
        let version = await installer(runner: runner).installedVersion()
        XCTAssertEqual(version, "1.0.0")
        XCTAssertEqual(runner.calls, [["/fake/claude", "plugin", "list", "--json"]])
    }

    // MARK: Kurulum (sahte çalıştırıcı)

    private func installer(runner: FakeRunner, cli: String? = "/fake/claude") -> AgentPluginInstaller {
        AgentPluginInstaller(generator: generator(), runner: runner, cliPath: { cli })
    }

    func testInstallCommandSequence() async throws {
        let runner = FakeRunner()
        let sut = installer(runner: runner)
        try await sut.install(port: 50123, token: "tok")
        XCTAssertEqual(runner.calls, [
            ["/fake/claude", "plugin", "marketplace", "add", sut.generator.root.path],
            ["/fake/claude", "plugin", "install", "adalmon-agents@adalmon-local"],
        ])
        XCTAssertEqual(sut.generator.readConfig()?.port, 50123, "dosyalar komutlardan önce yazılır")
    }

    func testInstallFailureSurfacesOutput() async throws {
        let runner = FakeRunner(results: ["install": CommandResult(status: 1, output: "boom")])
        let sut = installer(runner: runner)
        do {
            try await sut.install(port: 50123, token: "tok")
            XCTFail("hata beklenirdi")
        } catch let error as AgentPluginInstaller.InstallError {
            XCTAssertEqual(error, .commandFailed(step: "Plugin kurulumu", output: "boom"))
        }
    }

    func testMissingCLIWritesFilesButRunsNothing() async throws {
        let runner = FakeRunner()
        let sut = installer(runner: runner, cli: nil)
        do {
            try await sut.install(port: 50123, token: "tok")
            XCTFail("hata beklenirdi")
        } catch let error as AgentPluginInstaller.InstallError {
            XCTAssertEqual(error, .cliNotFound)
        }
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sut.generator.marketplaceURL.path))
        XCTAssertEqual(sut.manualInstallCommands.count, 2)
        XCTAssertTrue(sut.manualInstallCommands[1].hasSuffix("adalmon-agents@adalmon-local"))
        let missing = await sut.status()
        XCTAssertEqual(missing, .unknown)
    }

    func testTimeoutIsReported() async throws {
        let runner = FakeRunner(results: ["add": CommandResult(status: -2, output: "")])
        let sut = installer(runner: runner)
        do {
            try await sut.install(port: 1, token: "t")
            XCTFail("hata beklenirdi")
        } catch let error as AgentPluginInstaller.InstallError {
            XCTAssertEqual(error, .timedOut(step: "Marketplace ekleme"))
        }
    }

    func testUninstallSequenceAndStatus() async throws {
        let runner = FakeRunner(results: ["list": CommandResult(status: 0, output: "Installed plugins:\n  other@x\n")])
        let sut = installer(runner: runner)
        try sut.generator.write(port: 1, token: "t")
        try await sut.uninstall()
        XCTAssertEqual(runner.calls, [
            ["/fake/claude", "plugin", "uninstall", "adalmon-agents@adalmon-local"],
            ["/fake/claude", "plugin", "marketplace", "remove", "adalmon-local"],
            ["/fake/claude", "plugin", "list"],
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: sut.generator.root.path), "yerel dosyalar silinir")

        let listed = FakeRunner(results: ["list": CommandResult(status: 0, output: "  adalmon-agents@adalmon-local  1.0.0  enabled\n")])
        let status = await installer(runner: listed).status()
        XCTAssertEqual(status, .installed)
        XCTAssertEqual(listed.calls, [["/fake/claude", "plugin", "list"]])
        XCTAssertFalse(AgentPluginInstaller.isInstalled(listOutput: "adalmon-agents@other"))
    }
}

/// Komutları kaydeder; `results` anahtarı = argümanlarda geçen bir sözcük.
private final class FakeRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    private let results: [String: CommandResult]

    init(results: [String: CommandResult] = [:]) { self.results = results }

    private func record(_ call: [String]) { lock.lock(); recorded.append(call); lock.unlock() }

    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return recorded }

    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async -> CommandResult {
        record([executable] + arguments)
        for (key, result) in results where arguments.contains(key) { return result }
        return CommandResult(status: 0, output: "")
    }
}

/// Hook betiklerinin okuduğu config.json başka bir işlem tarafından ezilirse uygulama kendini onarır; test host'u gerçek config'e dokunmaz.
@MainActor
final class AgentConfigGuardTests: XCTestCase {
    func testServiceRepairsOverwrittenConfigAndDoesNotTouchTheRealOne() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "cfg-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let realConfig = AgentPluginGenerator().configURL
        let realBefore = try? Data(contentsOf: realConfig)

        let suite = "AgentConfigGuard-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults)
        prefs.agentsEnabled = true
        let generator = AgentPluginGenerator(root: tmp, usesPython: false)
        let service = AgentService(prefs: prefs, installer: AgentPluginInstaller(generator: generator))
        service.apply()
        defer { service.setEnabled(false) }
        var port: UInt16?
        for _ in 0..<50 { if let p = service.port { port = p; break }; try await Task.sleep(for: .milliseconds(100)) }
        let running = try XCTUnwrap(port, "dinleyici başlamalı")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(generator.readConfig()?.port, running)
        XCTAssertFalse(service.repairConfigIfNeeded(), "dosya güncelken yeniden yazılmaz")

        // Başka bir işlem dosyayı ezdi (ör. ikinci örnek farklı port + token yazdı).
        try generator.writeConfig(port: running &+ 1, token: "baska-token")
        XCTAssertTrue(service.repairConfigIfNeeded(), "ezilmiş config geri yazılmalı")
        XCTAssertEqual(generator.readConfig()?.port, running)
        XCTAssertNotEqual(generator.readConfig()?.token, "baska-token")

        // Gerçek (kullanıcının) config.json'u bu testle değişmemeli.
        XCTAssertEqual(try? Data(contentsOf: realConfig), realBefore, "test gerçek config.json'a dokunmamalı")
    }
}
