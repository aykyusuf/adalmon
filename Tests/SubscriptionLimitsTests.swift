import XCTest
@testable import Adalmon

/// USAGE-01: settings.json dönüşümü, sarmalayıcı betik, /v1/limits dinleyici yolu, Codex kuyruk ayrıştırıcısı, eşik takibi.
/// Hepsi geçici dizin kullanır; gerçek ~/.claude/settings.json ve ClaudePlugin/config.json'a dokunulmaz.
final class SubscriptionLimitsTests: XCTestCase {
    private var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appending(path: "adalmon-limits-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temp)
    }

    private let wrapperCommand = "/bin/sh '/x/Application Support/Adalmon/ClaudeStatusLine/statusline-wrapper.sh'"

    // MARK: settings.json dönüşümü

    private let settings = """
    {
      "model": "opus",
      "statusLine": {
        "type": "command",
        "command": "echo \\"hi\\" | tr a-z A-Z",
        "refreshInterval": 15
      },
      "permissions": { "allow": ["Bash(ls:*)"], "url": "https://example.com/a" },
      "z": [1, 2.50, {"q": "}]"}]
    }

    """

    func testConnectReplacesOnlyStatusLineAndKeepsOtherBytes() throws {
        let result = try ClaudeStatusLineTransform.connect(settings, wrapperCommand: wrapperCommand)
        XCTAssertFalse(result.alreadyConnected)
        let object = try ClaudeStatusLineTransform.parseObject(result.text)
        let statusLine = try XCTUnwrap(object["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["command"] as? String, wrapperCommand)
        XCTAssertEqual(statusLine["type"] as? String, "command")
        XCTAssertEqual(statusLine["refreshInterval"] as? Int, 15, "diğer statusLine alanları korunur")
        XCTAssertTrue(result.text.hasPrefix("{\n  \"model\": \"opus\",\n  \"statusLine\": "))
        XCTAssertTrue(result.text.hasSuffix(",\n  \"permissions\": { \"allow\": [\"Bash(ls:*)\"], \"url\": \"https://example.com/a\" },\n  \"z\": [1, 2.50, {\"q\": \"}]\"}]\n}\n"),
                      "diğer anahtarların baytları değişmez")
        XCTAssertEqual(result.originalRaw, "{\n    \"type\": \"command\",\n    \"command\": \"echo \\\"hi\\\" | tr a-z A-Z\",\n    \"refreshInterval\": 15\n  }")
        let restored = try XCTUnwrap(ClaudeStatusLineTransform.disconnect(result.text, originalRaw: result.originalRaw))
        XCTAssertEqual(restored, settings, "bağla → kaldır birebir aynı metin")
    }

    func testConnectIsIdempotent() throws {
        let first = try ClaudeStatusLineTransform.connect(settings, wrapperCommand: wrapperCommand)
        let second = try ClaudeStatusLineTransform.connect(first.text, wrapperCommand: wrapperCommand)
        XCTAssertTrue(second.alreadyConnected)
        XCTAssertNil(second.originalRaw)
        XCTAssertEqual(second.text, first.text)
    }

    func testInsertAndRemoveWhenNoStatusLine() throws {
        for original in ["{\n  \"a\": 1,\n  \"b\": {\"c\": [true, null]}\n}\n", "{}", "{\"only\":\"x\"}", "{\n\t\"tab\": 1\n}"] {
            let result = try ClaudeStatusLineTransform.connect(original, wrapperCommand: wrapperCommand)
            XCTAssertNil(result.originalRaw)
            let object = try ClaudeStatusLineTransform.parseObject(result.text)
            XCTAssertTrue(ClaudeStatusLineTransform.isWrapper(object["statusLine"]), original)
            XCTAssertEqual(try ClaudeStatusLineTransform.disconnect(result.text, originalRaw: nil), original, original)
        }
        let created = try ClaudeStatusLineTransform.connect(nil, wrapperCommand: wrapperCommand)
        XCTAssertTrue(ClaudeStatusLineTransform.isWrapper(try ClaudeStatusLineTransform.parseObject(created.text)["statusLine"]))
    }

    func testDisconnectLeavesForeignStatusLineAlone() throws {
        XCTAssertNil(try ClaudeStatusLineTransform.disconnect(settings, originalRaw: "{}"))
        XCTAssertThrowsError(try ClaudeStatusLineTransform.connect("{ not json", wrapperCommand: wrapperCommand))
        XCTAssertThrowsError(try ClaudeStatusLineTransform.connect("[1,2]", wrapperCommand: wrapperCommand))
    }

    func testDisconnectAfterOtherKeyEditedRestoresOnlyStatusLine() throws {
        let connected = try ClaudeStatusLineTransform.connect(settings, wrapperCommand: wrapperCommand)
        let edited = connected.text.replacingOccurrences(of: "\"model\": \"opus\"", with: "\"model\": \"sonnet\"")
        let restored = try XCTUnwrap(ClaudeStatusLineTransform.disconnect(edited, originalRaw: connected.originalRaw))
        XCTAssertEqual(restored, settings.replacingOccurrences(of: "\"model\": \"opus\"", with: "\"model\": \"sonnet\""))
    }

    // MARK: Bağlayıcı (geçici dosyalar)

    private func makeBinder() -> ClaudeStatusLineBinder {
        ClaudeStatusLineBinder(settingsURL: temp.appending(path: "claude/settings.json"),
                               supportDirectory: temp.appending(path: "support", directoryHint: .isDirectory),
                               configURL: temp.appending(path: "config.json"))
    }

    func testBinderBacksUpConnectsAndRestoresExactly() throws {
        let binder = makeBinder()
        try FileManager.default.createDirectory(at: binder.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(settings.utf8).write(to: binder.settingsURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: binder.settingsURL.path)

        guard case .connected(let backup?) = try binder.connect() else { return XCTFail("bağlanmadı") }
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), settings)
        XCTAssertTrue(binder.isConnected)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binder.wrapperURL.path))
        let mode = try FileManager.default.attributesOfItem(atPath: binder.settingsURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o640, "izinler korunur")
        let script = try String(contentsOf: binder.wrapperURL, encoding: .utf8)
        XCTAssertTrue(script.contains("echo \"hi\" | tr a-z A-Z"), "özgün komut sarmalayıcıda")
        let originalState = binder.readState()

        XCTAssertEqual(try binder.connect(), .alreadyConnected)
        XCTAssertEqual(binder.readState(), originalState, "ikinci bağlama özgün değeri ezmez")

        try FileManager.default.removeItem(at: binder.wrapperURL)
        binder.repairWrapperIfNeeded()
        XCTAssertTrue(FileManager.default.fileExists(atPath: binder.wrapperURL.path), "eksik sarmalayıcı yeniden üretilir")

        XCTAssertEqual(try binder.disconnect(), .disconnected)
        XCTAssertEqual(try String(contentsOf: binder.settingsURL, encoding: .utf8), settings)
        XCTAssertFalse(binder.isConnected)
        XCTAssertNil(binder.readState())
        XCTAssertEqual(try binder.disconnect(), .notConnected)
    }

    func testBinderDisconnectWhenUserReplacedStatusLine() throws {
        let binder = makeBinder()
        try FileManager.default.createDirectory(at: binder.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(settings.utf8).write(to: binder.settingsURL)
        _ = try binder.connect()
        let foreign = "{\"statusLine\": {\"type\": \"command\", \"command\": \"echo mine\"}}"
        try Data(foreign.utf8).write(to: binder.settingsURL)
        XCTAssertEqual(try binder.disconnect(), .notOurs)
        XCTAssertEqual(try String(contentsOf: binder.settingsURL, encoding: .utf8), foreign)
    }

    private func writeSettingsFile(_ binder: ClaudeStatusLineBinder, _ data: Data) throws {
        try FileManager.default.createDirectory(at: binder.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: binder.settingsURL)
    }

    func testReadSettingsMissingIsNilButUnreadableThrowsAndFileIsUntouched() throws {
        let binder = makeBinder()
        XCTAssertNil(try binder.readSettings(), "dosya yok → boş")

        let invalidUTF8 = Data([0x7B, 0xFF, 0xFE, 0x7D])
        try writeSettingsFile(binder, invalidUTF8)
        XCTAssertThrowsError(try binder.readSettings())
        XCTAssertThrowsError(try binder.connect())
        XCTAssertEqual(try Data(contentsOf: binder.settingsURL), invalidUTF8, "bağla dosyaya dokunmaz")
        XCTAssertFalse(FileManager.default.fileExists(atPath: binder.backupDirectory.path))

        // Okunamayan dosya (dizin) de "yok" sayılmaz.
        try FileManager.default.removeItem(at: binder.settingsURL)
        try FileManager.default.createDirectory(at: binder.settingsURL, withIntermediateDirectories: true)
        XCTAssertThrowsError(try binder.readSettings())
        XCTAssertThrowsError(try binder.connect())
    }

    func testDisconnectKeepsStateWhenSettingsUnreadable() throws {
        let binder = makeBinder()
        try writeSettingsFile(binder, Data(settings.utf8))
        _ = try binder.connect()
        let state = binder.readState()
        XCTAssertNotNil(state)
        let bad = Data([0xFF, 0xFE, 0x00])
        try bad.write(to: binder.settingsURL)
        XCTAssertThrowsError(try binder.disconnect())
        XCTAssertEqual(binder.readState(), state, "okunamayınca durum dosyası silinmez")
        XCTAssertEqual(try Data(contentsOf: binder.settingsURL), bad)
        // Dosya gerçekten yoksa durum temizlenir.
        try FileManager.default.removeItem(at: binder.settingsURL)
        XCTAssertEqual(try binder.disconnect(), .notConnected)
        XCTAssertNil(binder.readState())
    }

    func testAlreadyWrappedWithoutStateRegeneratesPassThroughWrapperAndCanDisconnect() throws {
        let binder = makeBinder()
        try writeSettingsFile(binder, Data(settings.utf8))
        _ = try binder.connect()
        let connectedText = try String(contentsOf: binder.settingsURL, encoding: .utf8)
        try FileManager.default.removeItem(at: binder.directory)
        XCTAssertEqual(try binder.connect(), .alreadyConnected)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binder.wrapperURL.path), "sarmalayıcı yeniden yazıldı")
        XCTAssertNotNil(binder.readState())
        XCTAssertTrue(binder.isConnected)
        XCTAssertEqual(try String(contentsOf: binder.settingsURL, encoding: .utf8), connectedText, "settings.json değişmedi")
        XCTAssertEqual(try binder.disconnect(), .disconnected)
        XCTAssertFalse(binder.isConnected)
        let after = try ClaudeStatusLineTransform.parseObject(String(contentsOf: binder.settingsURL, encoding: .utf8))
        XCTAssertNil(after["statusLine"], "özgün bilinmediği için anahtar kalkar, sarmalayıcıya bakan statusLine kalmaz")
        XCTAssertEqual(after["model"] as? String, "opus")
    }

    func testWriteSettingsAbortsWhenFileChangedSinceRead() throws {
        let binder = makeBinder()
        try writeSettingsFile(binder, Data("{\"a\": 1}".utf8))
        let readEarlier = try binder.readSettings()
        let concurrent = "{\"a\": 2}"
        try Data(concurrent.utf8).write(to: binder.settingsURL)
        XCTAssertThrowsError(try binder.writeSettings("{\"b\": 1}", replacing: readEarlier)) {
            XCTAssertEqual($0 as? ClaudeStatusLineBinder.BinderError, .settingsChanged)
        }
        XCTAssertEqual(try String(contentsOf: binder.settingsURL, encoding: .utf8), concurrent)
        // Dosya yokken okunup sonra oluşturulduysa da yazılmaz.
        XCTAssertThrowsError(try binder.writeSettings("{}", replacing: nil))
        XCTAssertEqual(try String(contentsOf: binder.settingsURL, encoding: .utf8), concurrent)
        try binder.writeSettings("{\"ok\": true}", replacing: concurrent)
        XCTAssertEqual(try String(contentsOf: binder.settingsURL, encoding: .utf8), "{\"ok\": true}")
    }

    func testBackupIsPrivateFromCreationAndOnlyNewestTenKept() throws {
        let binder = makeBinder()
        try FileManager.default.createDirectory(at: binder.backupDirectory, withIntermediateDirectories: true)
        for i in 0..<12 {
            let url = binder.backupDirectory.appending(path: String(format: "claude-settings-20200101-0000%02d-000.json", i))
            try Data("{}".utf8).write(to: url)
        }
        try writeSettingsFile(binder, Data(settings.utf8))
        guard case .connected(let backup?) = try binder.connect() else { return XCTFail("bağlanmadı") }
        let mode = try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        let names = try FileManager.default.contentsOfDirectory(atPath: binder.backupDirectory.path).sorted()
        XCTAssertEqual(names.count, 10)
        XCTAssertTrue(names.contains(backup.lastPathComponent), "yeni yedek korunur")
        XCTAssertFalse(names.contains("claude-settings-20200101-000000-000.json"), "en eskiler silinir")
    }

    // MARK: Sarmalayıcı betiği (gerçekten çalıştırılır)

    private let sampleInput = #"{"session_id":"s","model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1794438488},"seven_day":{"used_percentage":7,"resets_at":1794858786}}}"# + "\n\n"

    /// Tek tırnak, çift tırnak, $, ters tırnak, ters eğik çizgi, %, ! ve satır sonları içeren sahte özgün komut.
    private let fakeOriginal = """
    input=$(cat; printf x); input=${input%x}
    printf '%s\\n' "it's \\"quoted\\" \\$HOME `echo tick` 100% done!"
    printf 'bytes=%s\\n' "${#input}"
    printf 'back\\\\slash'
    echo "to stderr" >&2
    exit 3
    """

    private func run(_ executable: String, _ arguments: [String], input: String, environment: [String: String]) throws -> (out: Data, err: Data, status: Int32, seconds: Double) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let start = Date()
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (out, err, process.terminationStatus, Date().timeIntervalSince(start))
    }

    private func writeScript(original: String?, config: URL) throws -> URL {
        let url = temp.appending(path: "statusline-wrapper.sh")
        try Data(ClaudeStatusLineWrapper.script(originalCommand: original, configPath: "/nonexistent/config.json").utf8).write(to: url)
        return url
    }

    func testWrapperOutputIsByteIdenticalToOriginal() throws {
        // Ölü port: iletim sessizce başarısız olmalı, durum satırını geciktirmemeli.
        let config = temp.appending(path: "config.json")
        try Data(#"{"port":1,"token":"abc123"}"#.utf8).write(to: config)
        let env = ["PATH": "/usr/bin:/bin", "HOME": temp.path, "ADALMON_AGENTS_CONFIG": config.path]
        let script = try writeScript(original: fakeOriginal, config: config)
        let wrapped = try run("/bin/sh", [script.path], input: sampleInput, environment: env)
        let direct = try run("/bin/sh", ["-c", fakeOriginal], input: sampleInput, environment: env)
        XCTAssertEqual(wrapped.out, direct.out, "stdout birebir aynı")
        XCTAssertEqual(String(decoding: wrapped.out, as: UTF8.self),
                       "it's \"quoted\" $HOME tick 100% done!\nbytes=\(sampleInput.utf8.count)\nback\\slash")
        XCTAssertEqual(wrapped.err, direct.err)
        XCTAssertEqual(wrapped.status, 3, "çıkış kodu geçer")
        XCTAssertLessThan(wrapped.seconds, 1.5, "arka plan iletimi stdout'u tutmaz")
    }

    func testWrapperWithoutOriginalPrintsNothing() throws {
        let script = try writeScript(original: nil, config: temp.appending(path: "none.json"))
        let result = try run("/bin/sh", [script.path], input: sampleInput, environment: ["PATH": "/usr/bin:/bin"])
        XCTAssertTrue(result.out.isEmpty)
        XCTAssertEqual(result.status, 0)
    }

    func testWrapperRecursionGuard() throws {
        let script = try writeScript(original: "echo should-not-run", config: temp.appending(path: "none.json"))
        let result = try run("/bin/sh", [script.path], input: "{}", environment: ["PATH": "/usr/bin:/bin", "ADALMON_SL_WRAPPED": "1"])
        XCTAssertTrue(result.out.isEmpty)
    }

    func testShellQuoteRoundTrip() throws {
        let text = "a'b\"c$d`e\\f\ng"
        let result = try run("/bin/sh", ["-c", "printf '%s' \(ClaudeStatusLineWrapper.shellQuote(text))"], input: "", environment: [:])
        XCTAssertEqual(String(decoding: result.out, as: UTF8.self), text)
    }

    /// Uçtan uca: gerçek dinleyici (geçici token, rastgele port) + gerçek sarmalayıcı → yalnızca dört sayı gelir.
    func testWrapperForwardsLimitsToListener() throws {
        let token = AgentPluginGenerator.makeToken()
        let ready = expectation(description: "dinleyici hazır")
        let received = expectation(description: "limit geldi")
        final class Box: @unchecked Sendable {
            var port: UInt16 = 0
            var got: ProviderLimits?
        }
        let box = Box()
        let server = AgentEventServer(token: token, onEvent: { _ in }, onState: { state in
            if case .running(let p) = state { box.port = p; ready.fulfill() }
        }, onLimits: { limits in box.got = limits; received.fulfill() })
        server.start(preferredPort: nil)
        defer { server.stop() }
        wait(for: [ready], timeout: 5)
        let config = temp.appending(path: "config.json")
        try Data(#"{"port":\#(box.port),"token":"\#(token)"}"#.utf8).write(to: config)
        let script = try writeScript(original: "cat >/dev/null; printf ok", config: config)
        let result = try run("/bin/sh", [script.path], input: sampleInput, environment: ["PATH": "/usr/bin:/bin", "ADALMON_AGENTS_CONFIG": config.path])
        XCTAssertEqual(String(decoding: result.out, as: UTF8.self), "ok")
        wait(for: [received], timeout: 5)
        let got = box.got
        XCTAssertEqual(got?.source, .claude)
        XCTAssertEqual(got?.fiveHour?.usedPercent, 42.5)
        XCTAssertEqual(got?.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_794_438_488))
        XCTAssertEqual(got?.weekly?.usedPercent, 7)
        XCTAssertEqual(got?.weekly?.resetsAt, Date(timeIntervalSince1970: 1_794_858_786))
    }

    // MARK: Sarmalayıcı: süreç sayısı

    /// Sahte `curl` (günlüğe satır ekler) ve başarısız olması gereken sahte plutil/sed/awk/grep/jq/cat içeren PATH dizini.
    private func fakeBin() throws -> (path: String, curlLog: URL, forbiddenLog: URL) {
        let bin = temp.appending(path: "fakebin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let curlLog = temp.appending(path: "curl.log"), forbiddenLog = temp.appending(path: "forbidden.log")
        let curl = "#!/bin/sh\ncat >> '\(temp.path)/curl-stdin.log'\necho curl >> '\(curlLog.path)'\n"
        try Data(curl.utf8).write(to: bin.appending(path: "curl"))
        for name in ["plutil", "sed", "awk", "grep", "jq", "python3"] {
            try Data("#!/bin/sh\necho \(name) >> '\(forbiddenLog.path)'\n".utf8).write(to: bin.appending(path: name))
        }
        for item in try FileManager.default.contentsOfDirectory(atPath: bin.path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.appending(path: item).path)
        }
        return (bin.path + ":/usr/bin:/bin", curlLog, forbiddenLog)
    }

    private func lines(_ url: URL) -> [String] {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    func testWrapperSpawnsNoProcessWhenRateLimitsUnchanged() throws {
        // Betik /usr/bin/curl'ü mutlak yolla çağırır; sahte curl'ü yakalamak için betikteki yol testte değiştirilir.
        let config = temp.appending(path: "config.json")
        try Data("{\n  \"port\" : 4321,\n  \"token\" : \"abc123XYZ\"\n}".utf8).write(to: config)
        let bin = try fakeBin()
        let script = temp.appending(path: "statusline-wrapper.sh")
        let text = ClaudeStatusLineWrapper.script(originalCommand: fakeOriginal, configPath: config.path)
            .replacingOccurrences(of: "/usr/bin/curl", with: temp.path + "/fakebin/curl")
        try Data(text.utf8).write(to: script)
        let env = ["PATH": bin.path, "HOME": temp.path]

        var expectedCurls = 1
        func runOnce(_ input: String) throws -> Data {
            let r = try run("/bin/sh", [script.path], input: input, environment: env)
            XCTAssertEqual(r.status, 3)
            // Arka plan curl'ü bitsin.
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline, lines(bin.curlLog).count < expectedCurls { Thread.sleep(forTimeInterval: 0.02) }
            return r.out
        }
        let first = try runOnce(sampleInput)
        XCTAssertEqual(lines(bin.curlLog).count, 1, "ilk gönderim")
        let firstConfig = try String(contentsOf: temp.appending(path: "curl-stdin.log"), encoding: .utf8)
        XCTAssertTrue(firstConfig.contains(#"url = "http://127.0.0.1:4321/v1/limits""#))
        XCTAssertTrue(firstConfig.contains("X-Adalmon-Token: abc123XYZ"))
        XCTAssertTrue(firstConfig.contains(#"data-binary = "@\#(temp.path)/last-sent""#))
        let sent = try String(contentsOf: temp.appending(path: "last-sent"), encoding: .utf8)
        XCTAssertEqual(sent, #"{"five_hour":{"used_percentage":42.5,"resets_at":1794438488},"seven_day":{"used_percentage":7,"resets_at":1794858786}}"#)

        let second = try runOnce(sampleInput)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(lines(bin.curlLog).count, 1, "aynı girdi: curl çalışmaz")
        XCTAssertEqual(first, second)

        expectedCurls = 2
        _ = try runOnce(sampleInput.replacingOccurrences(of: "42.5", with: "43.5"))
        XCTAssertEqual(lines(bin.curlLog).count, 2, "değişen girdi: tek curl")

        // rate_limits yoksa hiçbir şey gönderilmez.
        _ = try runOnce(#"{"session_id":"s"}"#)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(lines(bin.curlLog).count, 2)
        XCTAssertTrue(lines(bin.forbiddenLog).isEmpty, "plutil/sed/awk/grep/jq çağrılmadı: \(lines(bin.forbiddenLog))")
    }

    func testWrapperExtractsNestedRateLimitsFromPrettyPrintedInput() throws {
        let config = temp.appending(path: "config.json")
        try Data(#"{"port":1,"token":"tok"}"#.utf8).write(to: config)
        let script = temp.appending(path: "statusline-wrapper.sh")
        try Data(ClaudeStatusLineWrapper.script(originalCommand: nil, configPath: config.path)
            .replacingOccurrences(of: "/usr/bin/curl", with: "/usr/bin/true").utf8).write(to: script)
        let pretty = "{\n  \"a\": {\"b\": 1},\n  \"rate_limits\" :\n {\n \"five_hour\": {\"used_percentage\": 1},\n \"seven_day\": {\"used_percentage\": 2}\n },\n  \"z\": {}\n}\n"
        _ = try run("/bin/sh", [script.path], input: pretty, environment: ["PATH": "/usr/bin:/bin"])
        let sent = try String(contentsOf: temp.appending(path: "last-sent"), encoding: .utf8)
        XCTAssertEqual(sent, "{\n \"five_hour\": {\"used_percentage\": 1},\n \"seven_day\": {\"used_percentage\": 2}\n }")
        try FileManager.default.removeItem(at: temp.appending(path: "last-sent"))
        // Kapanmamış nesne: temiz değil, hiçbir şey yazılmaz.
        _ = try run("/bin/sh", [script.path], input: #"{"rate_limits":{"five_hour":{"used_percentage":1}"#, environment: ["PATH": "/usr/bin:/bin"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.appending(path: "last-sent").path))
    }

    func testRepairRegeneratesOutdatedWrapperButNotSettings() throws {
        let binder = makeBinder()
        try writeSettingsFile(binder, Data(settings.utf8))
        _ = try binder.connect()
        try Data("#!/bin/sh\n# old\n".utf8).write(to: binder.wrapperURL)
        let settingsBefore = try Data(contentsOf: binder.settingsURL)
        binder.repairWrapperIfNeeded()
        XCTAssertEqual(try String(contentsOf: binder.wrapperURL, encoding: .utf8).contains("last-sent"), true)
        XCTAssertEqual(try Data(contentsOf: binder.settingsURL), settingsBefore)
    }

    // MARK: /v1/limits ayrıştırıcı (kimlik doğrulama)

    private func limitsRequest(token: String? = "tok", host: String? = "127.0.0.1:5000", origin: String? = nil,
                               body: String = #"{"five_hour":{"used_percentage":81,"resets_at":1794438488}}"#) -> Data {
        var lines = ["POST /v1/limits HTTP/1.1"]
        if let host { lines.append("Host: \(host)") }
        if let origin { lines.append("Origin: \(origin)") }
        if let token { lines.append("X-Adalmon-Token: \(token)") }
        lines.append("Content-Length: \(body.utf8.count)")
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n" + body).utf8)
    }

    func testLimitsEndpointAuth() {
        let now = Date(timeIntervalSince1970: 1_794_400_000)
        let ok = AgentHTTPParser.parse(limitsRequest(), token: "tok", port: 5000, now: now)
        XCTAssertEqual(ok, .limits(ProviderLimits(source: .claude, fiveHour: LimitWindow(usedPercent: 81, resetsAt: Date(timeIntervalSince1970: 1_794_438_488)),
                                                  weekly: nil, observedAt: now)))
        XCTAssertEqual(AgentHTTPParser.parse(limitsRequest(host: "localhost:5000"), token: "tok", port: 5000, now: now).isLimits, true)
        XCTAssertEqual(AgentHTTPParser.parse(limitsRequest(token: nil), token: "tok", port: 5000), .reject(401))
        XCTAssertEqual(AgentHTTPParser.parse(limitsRequest(token: "bad"), token: "tok", port: 5000), .reject(401))
        XCTAssertEqual(AgentHTTPParser.parse(limitsRequest(origin: "http://127.0.0.1:5000"), token: "tok", port: 5000), .reject(403))
        XCTAssertEqual(AgentHTTPParser.parse(limitsRequest(host: "evil.example:5000"), token: "tok", port: 5000), .reject(421))
        XCTAssertEqual(AgentHTTPParser.parse(limitsRequest(host: nil), token: "tok", port: 5000), .reject(421))
        XCTAssertEqual(AgentHTTPParser.parse(limitsRequest(body: #"{"other":1}"#), token: "tok", port: 5000), .reject(400))
        XCTAssertEqual(AgentHTTPParser.parse(limitsRequest(body: #"{"five_hour":{"used_percentage":"81"}}"#), token: "tok", port: 5000), .reject(400))
        XCTAssertEqual(AgentHTTPParser.parse(limitsRequest(body: #"{"five_hour":{"used_percentage":true}}"#), token: "tok", port: 5000), .reject(400))
        XCTAssertEqual(AgentHTTPParser.parse(limitsRequest(body: #"{"five_hour":{"used_percentage":5000}}"#), token: "tok", port: 5000), .reject(400))
        XCTAssertEqual(AgentHTTPParser.parse(limitsRequest(body: "garbage"), token: "tok", port: 5000), .reject(400))
        XCTAssertEqual(AgentHTTPParser.parse(limitsRequest(body: "[1,2]"), token: "tok", port: 5000), .reject(400))
        let big = #"{"five_hour":{"used_percentage":1},"pad":""# + String(repeating: "a", count: 5000) + #""}"#
        XCTAssertEqual(AgentHTTPParser.parse(limitsRequest(body: big), token: "tok", port: 5000), .reject(413))
        // Fazladan alanlar yok sayılır; yalnızca dört sayı saklanır.
        let extra = #"{"five_hour":{"used_percentage":10,"resets_at":1794438488,"x":"y"},"seven_day":{"used_percentage":20},"plan":"max"}"#
        let parsed = AgentHTTPParser.parse(limitsRequest(body: extra), token: "tok", port: 5000, now: now)
        XCTAssertEqual(parsed, .limits(ProviderLimits(source: .claude, fiveHour: LimitWindow(usedPercent: 10, resetsAt: Date(timeIntervalSince1970: 1_794_438_488)),
                                                      weekly: LimitWindow(usedPercent: 20, resetsAt: nil), observedAt: now)))
        let response = String(decoding: AgentHTTPParser.response(for: ok), as: UTF8.self)
        XCTAssertTrue(response.hasPrefix("HTTP/1.1 204 No Content\r\n"))
    }

    // MARK: Codex

    private func tokenCountLine(primary: String?, secondary: String? = nil, credits: String = #"{"has_credits":false,"unlimited":false,"balance":""}"#,
                                timestamp: String = "2026-11-11T18:00:00.123Z") -> String {
        let rateLimits = primary.map { #"{"limit_id":"SECRET-ID","primary":\#($0),"secondary":\#(secondary ?? "null"),"credits":\#(credits),"plan_type":"SECRET-PLAN"}"# } ?? "null"
        return #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":5}},"rate_limits":\#(rateLimits)}}"#
    }

    func testCodexParsesLatestTokenCount() throws {
        let fallback = Date(timeIntervalSince1970: 0)
        let older = tokenCountLine(primary: #"{"used_percent":10.0,"window_minutes":300,"resets_at":1794438000}"#)
        let newer = tokenCountLine(primary: #"{"used_percent":49.0,"window_minutes":300,"resets_at":1794438488}"#,
                                   secondary: #"{"used_percent":79.0,"window_minutes":10080,"resets_at":1794858786}"#,
                                   credits: #"{"has_credits":true,"unlimited":false,"balance":"12.5"}"#)
        let nullLimits = tokenCountLine(primary: nil)
        let other = #"{"type":"response_item","payload":{"type":"message","content":"token_count rate_limits"}}"#
        let tail = Data([older, newer, nullLimits, other, "{\"partial"].joined(separator: "\n").utf8)
        let result = try XCTUnwrap(CodexRolloutParser.latest(tail: tail, truncated: false, fallbackDate: fallback))
        XCTAssertEqual(result.source, .codex)
        XCTAssertEqual(result.fiveHour, LimitWindow(usedPercent: 49, resetsAt: Date(timeIntervalSince1970: 1_794_438_488)))
        XCTAssertEqual(result.weekly, LimitWindow(usedPercent: 79, resetsAt: Date(timeIntervalSince1970: 1_794_858_786)))
        XCTAssertEqual(result.creditsBalance, 12.5)
        XCTAssertEqual(result.observedAt, CodexRolloutParser.parseTimestamp("2026-11-11T18:00:00.123Z"))
        let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        XCTAssertFalse(encoded.contains("SECRET"), "hesap/plan kimliği tutulmaz")
    }

    func testCodexEdgeCases() {
        let now = Date(timeIntervalSince1970: 1_794_400_000)
        // Yalnızca haftalık pencere birincil olarak geldi (5 saat kaldırılmışsa).
        let weeklyOnly = tokenCountLine(primary: #"{"used_percent":5,"window_minutes":10080,"resets_at":1794858786}"#)
        let result = CodexRolloutParser.latest(tail: Data(weeklyOnly.utf8), truncated: false, fallbackDate: now)
        XCTAssertNil(result?.fiveHour)
        XCTAssertEqual(result?.weekly?.usedPercent, 5)
        XCTAssertNil(result?.creditsBalance)
        // Eski biçim: resets_in_seconds, zaman damgasına göre.
        let relative = tokenCountLine(primary: #"{"used_percent":20,"resets_in_seconds":600}"#, timestamp: "2026-11-11T18:00:00Z")
        let relativeResult = CodexRolloutParser.latest(tail: Data(relative.utf8), truncated: false, fallbackDate: now)
        XCTAssertEqual(relativeResult?.fiveHour?.resetsAt, CodexRolloutParser.parseTimestamp("2026-11-11T18:00:00Z")?.addingTimeInterval(600))
        // Kesik ilk satır atlanır; çöp ya da boş → nil.
        let line = tokenCountLine(primary: #"{"used_percent":1,"window_minutes":300,"resets_at":1794438488}"#)
        XCTAssertNil(CodexRolloutParser.latest(tail: Data(line.utf8), truncated: true, fallbackDate: now))
        XCTAssertNil(CodexRolloutParser.latest(tail: Data("garbage\n{}\n".utf8), truncated: false, fallbackDate: now))
        XCTAssertNil(CodexRolloutParser.latest(tail: Data(), truncated: false, fallbackDate: now))
        XCTAssertNil(CodexRolloutParser.latest(tail: Data(tokenCountLine(primary: #"{"used_percent":"x"}"#).utf8), truncated: false, fallbackDate: now))
    }

    func testCodexReaderPicksNewestByModificationAcrossDays() throws {
        let root = temp.appending(path: "sessions", directoryHint: .isDirectory)
        let yesterday = root.appending(path: "2026/11/10", directoryHint: .isDirectory)
        let today = root.appending(path: "2026/11/11", directoryHint: .isDirectory)
        let old = root.appending(path: "2025/01/01", directoryHint: .isDirectory)
        for dir in [yesterday, today, old] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        let line = { (p: Int) in self.tokenCountLine(primary: #"{"used_percent":\#(p),"window_minutes":300,"resets_at":1794438488}"#) + "\n" }
        let running = yesterday.appending(path: "rollout-a.jsonl"), fresh = today.appending(path: "rollout-b.jsonl")
        try Data(line(30).utf8).write(to: running)
        try Data(line(20).utf8).write(to: fresh)
        try Data(line(99).utf8).write(to: old.appending(path: "rollout-c.jsonl"))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -600)], ofItemAtPath: fresh.path)
        let reader = CodexRolloutReader(root: root)
        XCTAssertEqual(reader.newestRollouts().map(\.url.lastPathComponent), ["rollout-a.jsonl", "rollout-b.jsonl"])
        XCTAssertEqual(reader.latest()?.fiveHour?.usedPercent, 30, "dünden süren oturum (daha yeni değişiklik) seçilir")
        // Kuyruk okuma: büyük dosyada yalnızca son baytlar.
        let big = today.appending(path: "rollout-big.jsonl")
        try Data((String(repeating: "x", count: 300_000) + "\n" + line(55)).utf8).write(to: big)
        let tail = try XCTUnwrap(CodexRolloutReader.readTail(big))
        XCTAssertTrue(tail.truncated)
        XCTAssertEqual(tail.data.count, CodexRolloutReader.tailBytes)
        XCTAssertEqual(CodexRolloutParser.latest(tail: tail.data, truncated: true, fallbackDate: .now)?.fiveHour?.usedPercent, 55)
        XCTAssertNil(CodexRolloutReader(root: temp.appending(path: "missing")).latest())
    }

    // MARK: Eşik takibi

    private func limits(_ source: LimitSource = .claude, five: Double?, week: Double? = nil, fiveReset: Double = 10_000, now: Date) -> ProviderLimits {
        ProviderLimits(source: source,
                       fiveHour: five.map { LimitWindow(usedPercent: $0, resetsAt: Date(timeIntervalSince1970: fiveReset)) },
                       weekly: week.map { LimitWindow(usedPercent: $0, resetsAt: Date(timeIntervalSince1970: 500_000)) },
                       observedAt: now)
    }

    func testThresholdCrossingNotifiesOncePerLevelPerWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        var tracker = LimitAlertTracker()
        let thresholds = LimitAlertThresholds()
        XCTAssertTrue(tracker.evaluate(limits(five: 50, now: now), thresholds: thresholds, now: now).isEmpty)
        let warn = tracker.evaluate(limits(five: 81, now: now), thresholds: thresholds, now: now)
        XCTAssertEqual(warn.map(\.level), [.warning])
        XCTAssertEqual(warn.first?.title(), "Claude 5 saatlik limit: %81 kullanıldı")
        XCTAssertTrue(tracker.evaluate(limits(five: 85, now: now), thresholds: thresholds, now: now).isEmpty, "tekrar yok")
        XCTAssertTrue(tracker.evaluate(limits(five: 85, fiveReset: 10_120, now: now), thresholds: thresholds, now: now).isEmpty, "küçük oynama aynı pencere")
        let critical = tracker.evaluate(limits(five: 96, now: now), thresholds: thresholds, now: now)
        XCTAssertEqual(critical.map(\.level), [.critical])
        XCTAssertEqual(critical.first?.title(), "Claude 5 saatlik limit neredeyse doldu: %96")
        XCTAssertTrue(tracker.evaluate(limits(five: 99, now: now), thresholds: thresholds, now: now).isEmpty)
        // Yeni pencere: yeniden uyarılır. Codex ayrı izlenir.
        XCTAssertEqual(tracker.evaluate(limits(five: 82, fiveReset: 28_000, now: now), thresholds: thresholds, now: now).map(\.level), [.warning])
        XCTAssertEqual(tracker.evaluate(limits(.codex, five: 82, now: now), thresholds: thresholds, now: now).count, 1)
    }

    func testCriticalFirstSuppressesWarnAndSeparateWeeklyThresholds() {
        let now = Date(timeIntervalSince1970: 1_000)
        var tracker = LimitAlertTracker()
        var thresholds = LimitAlertThresholds()
        thresholds.weeklyWarn = 50
        thresholds.weeklyCritical = 70
        let first = tracker.evaluate(limits(five: 97, week: 55, now: now), thresholds: thresholds, now: now)
        XCTAssertEqual(first.map(\.level), [.critical, .warning])
        XCTAssertEqual(first.map(\.kind), [.fiveHour, .weekly])
        XCTAssertTrue(tracker.evaluate(limits(five: 85, week: 60, now: now), thresholds: thresholds, now: now).isEmpty, "kritikten sonra uyarı yok")
        XCTAssertEqual(tracker.evaluate(limits(five: 85, week: 71, now: now), thresholds: thresholds, now: now).map(\.level), [.critical])
    }

    func testNoAlertsWhenStaleResetOrDisabled() {
        let now = Date(timeIntervalSince1970: 20_000)
        var tracker = LimitAlertTracker()
        var thresholds = LimitAlertThresholds()
        let stale = limits(five: 99, fiveReset: 30_000, now: now.addingTimeInterval(-3_600))
        XCTAssertTrue(tracker.evaluate(stale, thresholds: thresholds, now: now).isEmpty, "eski veri bildirim üretmez")
        XCTAssertTrue(tracker.evaluate(limits(five: 99, fiveReset: 19_000, now: now), thresholds: thresholds, now: now).isEmpty, "yenilenmiş pencere")
        thresholds.notificationsEnabled = false
        XCTAssertTrue(tracker.evaluate(limits(five: 99, fiveReset: 30_000, now: now), thresholds: thresholds, now: now).isEmpty)
    }

    func testFormatting() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(LimitFormat.resetText(now.addingTimeInterval(2 * 3600 + 10 * 60), now: now), "2 sa 10 dk sonra yenilenir")
        XCTAssertEqual(LimitFormat.resetText(now.addingTimeInterval(3 * 86_400 + 4 * 3600), now: now), "3 gün 4 sa sonra yenilenir")
        XCTAssertEqual(LimitFormat.resetText(now.addingTimeInterval(30), now: now), "1 dk içinde yenilenir")
        XCTAssertEqual(LimitFormat.resetText(now.addingTimeInterval(-1), now: now), "Yenilendi")
        XCTAssertEqual(LimitFormat.ageText(now.addingTimeInterval(-300), now: now), "5 dk önce")
        XCTAssertEqual(LimitFormat.ageText(now.addingTimeInterval(-7_200), now: now), "2 sa önce")
    }

    func testNilResetWindowRearmsAfterUsageDrops() {
        let now = Date(timeIntervalSince1970: 1_000)
        var tracker = LimitAlertTracker()
        let thresholds = LimitAlertThresholds()
        func nilReset(_ used: Double) -> ProviderLimits {
            ProviderLimits(source: .claude, fiveHour: LimitWindow(usedPercent: used, resetsAt: nil), observedAt: now)
        }
        XCTAssertEqual(tracker.evaluate(nilReset(85), thresholds: thresholds, now: now).count, 1)
        XCTAssertTrue(tracker.evaluate(nilReset(86), thresholds: thresholds, now: now).isEmpty, "aynı pencerede tekrar yok")
        XCTAssertTrue(tracker.evaluate(nilReset(10), thresholds: thresholds, now: now).isEmpty)
        XCTAssertTrue(tracker.entries.isEmpty, "eşiğin altına inince kayıt silinir")
        XCTAssertEqual(tracker.evaluate(nilReset(85), thresholds: thresholds, now: now).count, 1, "yeniden silahlandı")
    }

    @MainActor
    func testUnchangedClaudeValuesDoNotReassignOrRewrite() throws {
        let suite = "adalmon.limits.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SubscriptionLimitsModel(defaults: defaults, binder: makeBinder(), codexReader: CodexRolloutReader(root: temp), live: false)
        let now = Date()
        let window = LimitWindow(usedPercent: 40, resetsAt: now.addingTimeInterval(3_600))
        model.ingestClaude(ProviderLimits(source: .claude, fiveHour: window, observedAt: now), now: now)
        defaults.removeObject(forKey: "subscriptionLimits.claude")
        let later = now.addingTimeInterval(10)
        model.ingestClaude(ProviderLimits(source: .claude, fiveHour: window, observedAt: later), now: later)
        XCTAssertNil(defaults.data(forKey: "subscriptionLimits.claude"), "değişmeyen değer yeniden yazılmaz")
        XCTAssertEqual(model.claude?.observedAt, now)
        let muchLater = now.addingTimeInterval(120)
        model.ingestClaude(ProviderLimits(source: .claude, fiveHour: window, observedAt: muchLater), now: muchLater)
        XCTAssertEqual(model.claude?.observedAt, muchLater, "zaman damgası dakikada bir tazelenir")
        let changed = LimitWindow(usedPercent: 41, resetsAt: window.resetsAt)
        model.ingestClaude(ProviderLimits(source: .claude, fiveHour: changed, observedAt: muchLater), now: muchLater)
        XCTAssertEqual(model.claude?.fiveHour?.usedPercent, 41)
    }

    @MainActor
    func testModelPersistsClaudeSnapshotAndNotifies() throws {
        let suite = "adalmon.limits.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let binder = makeBinder()
        let model = SubscriptionLimitsModel(defaults: defaults, binder: binder, codexReader: CodexRolloutReader(root: temp), live: false)
        var sent: [String] = []
        model.notify = { title, _ in sent.append(title) }
        let now = Date()
        model.ingestClaude(ProviderLimits(source: .claude, fiveHour: LimitWindow(usedPercent: 90, resetsAt: now.addingTimeInterval(3_600)), observedAt: now), now: now)
        XCTAssertEqual(sent, ["Claude 5 saatlik limit: %90 kullanıldı"])
        let reloaded = SubscriptionLimitsModel(defaults: defaults, binder: binder, codexReader: CodexRolloutReader(root: temp), live: false)
        XCTAssertEqual(reloaded.claude?.fiveHour?.usedPercent, 90, "son değer yeniden başlatmadan sonra görünür")
        var again: [String] = []
        reloaded.notify = { title, _ in again.append(title) }
        reloaded.ingestClaude(ProviderLimits(source: .claude, fiveHour: LimitWindow(usedPercent: 91, resetsAt: now.addingTimeInterval(3_600)), observedAt: now), now: now)
        XCTAssertTrue(again.isEmpty, "takip kalıcı: yeniden başlatınca aynı pencere için tekrar bildirim yok")
    }
}

private extension AgentHTTPParser.Outcome {
    var isLimits: Bool { if case .limits = self { true } else { false } }
}
