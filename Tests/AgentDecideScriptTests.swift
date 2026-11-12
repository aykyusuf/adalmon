import XCTest
@testable import Adalmon

/// OFFICE-CTRL-01: decide.py `--dry-run` testleri (ağ yok) + hook kaydı. Yapılandırma YALNIZCA geçici dizinden okunur.
final class AgentDecideScriptTests: XCTestCase {
    private var tmp: URL!
    private var generator: AgentPluginGenerator!

    override func setUpWithError() throws {
        try XCTSkipUnless(AgentPluginGenerator.pythonAvailable(), "python3 yok")
        tmp = FileManager.default.temporaryDirectory.appending(path: "decide-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        generator = AgentPluginGenerator(root: tmp.appending(path: "ClaudePlugin", directoryHint: .isDirectory), usesPython: true)
        try generator.write(port: 51999, token: "tok")
    }
    override func tearDownWithError() throws { if let tmp { try? FileManager.default.removeItem(at: tmp) } }

    private func enable(_ on: Bool = true) throws { try generator.setControlEnabled(on) }

    @discardableResult
    private func run(_ stdin: String, args: [String] = ["--dry-run"], config: URL? = nil) throws -> (output: String, status: Int32, seconds: TimeInterval) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/python3")
        process.arguments = ["-I", generator.decideScriptURL.path] + args
        process.environment = ProcessInfo.processInfo.environment.merging(["ADALMON_AGENTS_CONFIG": (config ?? generator.configURL).path]) { $1 }
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let started = Date()
        try process.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus, Date().timeIntervalSince(started))
    }

    private let permission = """
    {"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/Users/x/Proj","permission_mode":"default","tool_name":"Bash",
     "tool_input":{"command":"npm test"},"prompt_id":"p1","permission_suggestions":[
       {"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"npm test"}],"behavior":"allow","destination":"localSettings"},
       {"type":"setMode","mode":"bypassPermissions","destination":"session"},
       {"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"rm"}],"behavior":"deny","destination":"session"},
       {"type":"addDirectories","directories":["/tmp/x"],"destination":"session"}]}
    """

    private let question = """
    {"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/Users/x/Proj","tool_name":"AskUserQuestion",
     "tool_input":{"questions":[
       {"question":"Pick a color","header":"Color","multiSelect":false,"options":[{"label":"Blue","description":"b"},{"label":"Red","description":"r"}]},
       {"question":"Pick fruits","header":"Fruit","multiSelect":true,"options":[{"label":"Apple","description":"a"},{"label":"Banana","description":"b"},{"label":"Cherry","description":"c"}]}]}}
    """

    private func verdictArgs(_ json: String) -> [String] { ["--dry-run", "--verdict", json] }

    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], "JSON değil: \(text)")
    }

    private func decision(_ text: String) throws -> [String: Any] {
        let hook = try XCTUnwrap(try object(text)["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(hook["hookEventName"] as? String, "PermissionRequest")
        return try XCTUnwrap(hook["decision"] as? [String: Any])
    }

    // MARK: Kapı (fail open)

    func testDisabledOrMissingConfigPrintsNothingAndIsFast() throws {
        // Anahtar yok.
        var result = try run(permission, args: [])
        XCTAssertEqual(result.output, "")
        XCTAssertEqual(result.status, 0)
        // Açıkça kapalı: ağa bağlanmadan (port açık olmasa da) hızlıca çıkar.
        try enable(false)
        result = try run(permission, args: [])
        XCTAssertEqual(result.output, "")
        XCTAssertEqual(result.status, 0)
        XCTAssertLessThan(result.seconds, 1.0, "kapalıyken betik hızlı çıkmalı (ölçülen: \(result.seconds) sn)")
        // Config yok / bozuk.
        XCTAssertEqual(try run(permission, config: tmp.appending(path: "yok.json")).output, "")
        let broken = tmp.appending(path: "broken.json")
        try Data("{not json".utf8).write(to: broken)
        XCTAssertEqual(try run(permission, config: broken).output, "")
        // Kapalıyken --verdict bile çıktı üretmez.
        XCTAssertEqual(try run(permission, args: verdictArgs(#"{"verdict":"allow"}"#)).output, "")
    }

    func testEnabledWithBadPortOrTokenPrintsNothing() throws {
        for config in [#"{"controlEnabled":true}"#, #"{"controlEnabled":true,"port":0,"token":"t"}"#, #"{"controlEnabled":true,"port":5,"token":""}"#,
                       #"{"controlEnabled":"true","port":5,"token":"t"}"#, #"{"controlEnabled":1,"port":5,"token":"t"}"#] {
            let url = tmp.appending(path: "c-\(UUID().uuidString).json")
            try Data(config.utf8).write(to: url)
            XCTAssertEqual(try run(permission, config: url).output, "", config)
        }
    }

    func testUnreachableListenerFailsOpenWithoutOutput() throws {
        try enable()
        let started = Date()
        let result = try run(permission, args: []) // gerçek bağlantı denemesi: 51999 dinlenmiyor
        XCTAssertEqual(result.output, "")
        XCTAssertEqual(result.status, 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testBypassModeInInputIsIgnoredAndOtherEventsDoNothing() throws {
        try enable()
        XCTAssertEqual(try run(permission.replacingOccurrences(of: "\"default\"", with: "\"bypassPermissions\"")).output, "")
        XCTAssertEqual(try run(permission.replacingOccurrences(of: "PermissionRequest", with: "PreToolUse")).output, "")
        XCTAssertEqual(try run("garbage").output, "")
        XCTAssertEqual(try run("[1,2]").output, "")
    }

    // MARK: İstek gövdesi

    func testPermissionRequestBody() throws {
        try enable()
        let request = try object(try run(permission).output)
        XCTAssertEqual(request["kind"] as? String, "permission")
        XCTAssertEqual(request["session_id"] as? String, "s1")
        XCTAssertEqual(request["tool_name"] as? String, "Bash")
        XCTAssertEqual(request["project"] as? String, "Proj")
        XCTAssertEqual(request["preview"] as? String, "npm test")
        XCTAssertEqual(request["prompt_id"] as? String, "p1")
        XCTAssertEqual(request["hold"] as? Double, 590)
        XCTAssertEqual((request["input_hash"] as? String)?.count, 16)
        // Yalnızca "izin ver" kuralı ve dizin eklemeleri sunulur; setMode ve deny kuralı sunulmaz. Dizin özgün konumunu korur.
        let suggestions = try XCTUnwrap(request["suggestions"] as? [[String: Any]])
        XCTAssertEqual(suggestions.map { $0["index"] as? Int }, [0, 3])
        XCTAssertEqual(suggestions.map { $0["label"] as? String }, ["Bash(npm test)", "Dizin: /tmp/x"])
        XCTAssertNil(request["questions"])
        XCTAssertTrue(Set(request.keys).isSubset(of: DecisionRequest.allowedKeys.union(["ts"])), "\(request.keys)")
        XCTAssertNotNil(DecisionRequest(json: Data(try run(permission).output.utf8)), "Swift tarafı betiğin gövdesini okuyabilmeli")
    }

    func testQuestionRequestBodyAndSwiftCompatibility() throws {
        try enable()
        let text = try run(question).output
        let request = try object(text)
        XCTAssertEqual(request["kind"] as? String, "question")
        let parsed = try XCTUnwrap(DecisionRequest(json: Data(text.utf8)))
        XCTAssertEqual(parsed.questions.count, 2)
        XCTAssertEqual(parsed.questions[1].options.map(\.label), ["Apple", "Banana", "Cherry"])
        XCTAssertTrue(parsed.questions[1].multiSelect)
        XCTAssertNil(request["preview"])
    }

    func testPreviewIsTruncatedAndStripped() throws {
        try enable()
        let long = String(repeating: "a", count: 4000)
        let input = permission.replacingOccurrences(of: "npm test\"}", with: "x\\u0007\\ny\(long)\"}")
        let request = try object(try run(input).output)
        let preview = try XCTUnwrap(request["preview"] as? String)
        XCTAssertEqual(preview.count, DecisionLimits.maxPreview)
        XCTAssertTrue(preview.hasPrefix("x\nyaaa"), "kontrol karakteri atılır, satır sonu kalır")
    }

    func testRequestHashMatchesForwardScriptHash() throws {
        try enable()
        let tool = #"{"command":"npm test","description":"çalıştır","n":[1,2,{"b":1,"a":2}]}"#
        let perm = """
        {"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/x/P","tool_name":"Bash","tool_input":\(tool)}
        """
        let hash = try XCTUnwrap(try object(try run(perm).output)["input_hash"] as? String)
        let forward = Process()
        forward.executableURL = URL(filePath: "/usr/bin/python3")
        forward.arguments = ["-I", generator.pythonScriptURL.path, "--dry-run"]
        forward.environment = ProcessInfo.processInfo.environment.merging(["ADALMON_AGENTS_CONFIG": generator.configURL.path]) { $1 }
        let input = Pipe(), output = Pipe()
        forward.standardInput = input
        forward.standardOutput = output
        forward.standardError = FileHandle.nullDevice
        try forward.run()
        input.fileHandleForWriting.write(Data("""
        {"hook_event_name":"PostToolUse","session_id":"s1","cwd":"/x/P","tool_name":"Bash","tool_input":\(tool),"prompt_id":"pp1","tool_response":"SECRET-OUT"}
        """.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        forward.waitUntilExit()
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["input_hash"] as? String, hash, "forward.py ve decide.py aynı özeti üretmeli (eşleştirme için)")
        XCTAssertEqual(payload["prompt_id"] as? String, "pp1")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("SECRET"))
        XCTAssertTrue(Set(payload.keys).isSubset(of: AgentEvent.allowedKeys))
    }

    func testForwarderSendsHashAndPromptIdOnlyWhileControlIsEnabled() throws {
        func forward(_ event: String) throws -> [String: Any] {
            let p = Process()
            p.executableURL = URL(filePath: "/usr/bin/python3")
            p.arguments = ["-I", generator.pythonScriptURL.path, "--dry-run"]
            p.environment = ProcessInfo.processInfo.environment.merging(["ADALMON_AGENTS_CONFIG": generator.configURL.path]) { $1 }
            let input = Pipe(), output = Pipe()
            p.standardInput = input
            p.standardOutput = output
            p.standardError = FileHandle.nullDevice
            try p.run()
            input.fileHandleForWriting.write(Data(#"{"hook_event_name":"\#(event)","session_id":"s1","cwd":"/x/P","tool_name":"Bash","tool_input":{"command":"ls"},"prompt_id":"pp1"}"#.utf8))
            try input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        try enable(false)
        for event in ["PostToolUse", "PostToolUseFailure", "PermissionDenied", "PreToolUse", "Stop"] {
            let off = try forward(event)
            XCTAssertNil(off["input_hash"], "\(event): kontrol kapalıyken özet gönderilmez")
            XCTAssertNil(off["prompt_id"], "\(event): kontrol kapalıyken istem kimliği gönderilmez")
        }
        try enable(true)
        for event in ["PostToolUse", "PostToolUseFailure", "PermissionDenied"] {
            let on = try forward(event)
            XCTAssertEqual((on["input_hash"] as? String)?.count, 16, event)
            XCTAssertEqual(on["prompt_id"] as? String, "pp1", event)
        }
        XCTAssertNil(try forward("PreToolUse")["input_hash"], "yalnızca araç sonuç olaylarında")
    }

    // MARK: Karar → hook çıktısı

    func testAllowDenyShapes() throws {
        try enable()
        let allow = try decision(try run(permission, args: verdictArgs(#"{"verdict":"allow","scope":"session"}"#)).output)
        XCTAssertEqual(allow["behavior"] as? String, "allow")
        XCTAssertNil(allow["updatedPermissions"])
        let deny = try decision(try run(permission, args: verdictArgs(#"{"verdict":"deny"}"#)).output)
        XCTAssertEqual(deny["behavior"] as? String, "deny")
        XCTAssertNotNil(deny["message"] as? String)
    }

    func testAlwaysAllowDestinations() throws {
        try enable()
        let user = try decision(try run(permission, args: verdictArgs(#"{"verdict":"allow","suggestion":0,"scope":"user"}"#)).output)
        let userEntry = try XCTUnwrap((user["updatedPermissions"] as? [[String: Any]])?.first)
        XCTAssertEqual(userEntry["destination"] as? String, "userSettings")
        XCTAssertEqual(userEntry["type"] as? String, "addRules")
        XCTAssertEqual(userEntry["behavior"] as? String, "allow")
        XCTAssertEqual((userEntry["rules"] as? [[String: Any]])?.first?["ruleContent"] as? String, "npm test")
        let session = try decision(try run(permission, args: verdictArgs(#"{"verdict":"allow","suggestion":3,"scope":"session"}"#)).output)
        let sessionEntry = try XCTUnwrap((session["updatedPermissions"] as? [[String: Any]])?.first)
        XCTAssertEqual(sessionEntry["destination"] as? String, "session")
        XCTAssertEqual(sessionEntry["type"] as? String, "addDirectories")
    }

    func testSetModeOnlyWhitelistedAndNeverBypass() throws {
        try enable()
        for mode in ["acceptEdits", "plan", "default"] {
            let d = try decision(try run(permission, args: verdictArgs(#"{"verdict":"allow","mode":"\#(mode)"}"#)).output)
            let entry = try XCTUnwrap((d["updatedPermissions"] as? [[String: Any]])?.first)
            XCTAssertEqual(entry["type"] as? String, "setMode")
            XCTAssertEqual(entry["mode"] as? String, mode)
            XCTAssertEqual(entry["destination"] as? String, "session")
        }
        for mode in ["bypassPermissions", "auto", "dontAsk", "", "ACCEPTEDITS"] {
            XCTAssertEqual(try run(permission, args: verdictArgs(#"{"verdict":"allow","mode":"\#(mode)"}"#)).output, "", "mod \(mode) reddedilmeli")
        }
        let both = try decision(try run(permission, args: verdictArgs(#"{"verdict":"allow","suggestion":0,"scope":"user","mode":"plan"}"#)).output)
        XCTAssertEqual((both["updatedPermissions"] as? [[String: Any]])?.map { $0["type"] as? String }, ["addRules", "setMode"])
    }

    func testMalformedVerdictsPrintNothing() throws {
        try enable()
        let bad = [
            "not json", "[]", "null", #"{}"#, #"{"verdict":"approve"}"#, #"{"verdict":"ALLOW"}"#, #"{"verdict":"answer","answers":{}}"#,
            #"{"verdict":"allow","suggestion":99,"scope":"user"}"#, #"{"verdict":"allow","suggestion":-1,"scope":"user"}"#,
            #"{"verdict":"allow","suggestion":"0","scope":"user"}"#, #"{"verdict":"allow","suggestion":true,"scope":"user"}"#,
            #"{"verdict":"allow","suggestion":0}"#, #"{"verdict":"allow","suggestion":0,"scope":"project"}"#,
            #"{"verdict":"allow","suggestion":1,"scope":"user"}"#, // setMode önerisi sunulmaz, seçilemez
            #"{"verdict":"allow","suggestion":2,"scope":"user"}"#, // deny kuralı sunulmaz
        ]
        for json in bad {
            let r = try run(permission, args: verdictArgs(json))
            XCTAssertEqual(r.output, "", json)
            XCTAssertEqual(r.status, 0, json)
        }
        XCTAssertEqual(try run(permission, args: ["--dry-run", "--verdict"]).output, "")
    }

    // MARK: AskUserQuestion

    func testQuestionAnswerShapeWithMultiSelectJoinedByCommaSpace() throws {
        try enable()
        let json = #"{"verdict":"answer","answers":{"Pick a color":["Blue"],"Pick fruits":["Cherry","Apple"]}}"#
        let d = try decision(try run(question, args: verdictArgs(json)).output)
        XCTAssertEqual(d["behavior"] as? String, "allow")
        let updated = try XCTUnwrap(d["updatedInput"] as? [String: Any])
        XCTAssertEqual((updated["questions"] as? [[String: Any]])?.count, 2, "özgün sorular korunur")
        XCTAssertEqual(updated["answers"] as? [String: String], ["Pick a color": "Blue", "Pick fruits": "Apple, Cherry"])
        // Tek seçimli soruya düz dize de kabul edilir.
        let plain = try decision(try run(question, args: verdictArgs(#"{"verdict":"answer","answers":{"Pick a color":"Red","Pick fruits":["Banana"]}}"#)).output)
        XCTAssertEqual((plain["updatedInput"] as? [String: Any])?["answers"] as? [String: String], ["Pick a color": "Red", "Pick fruits": "Banana"])
    }

    func testNonexistentOrInconsistentAnswersPrintNothing() throws {
        try enable()
        let bad = [
            #"{"verdict":"answer","answers":{"Pick a color":["Green"],"Pick fruits":["Apple"]}}"#,            // olmayan etiket
            #"{"verdict":"answer","answers":{"Pick a color":["Blue","Red"],"Pick fruits":["Apple"]}}"#,      // tek seçimde iki etiket
            #"{"verdict":"answer","answers":{"Pick a color":["Blue"]}}"#,                                    // eksik soru
            #"{"verdict":"answer","answers":{"Pick a color":["Blue"],"Pick fruits":[]}}"#,                   // boş seçim
            #"{"verdict":"answer","answers":{"Pick a color":["Blue"],"Pick fruits":["Apple","Apple"]}}"#,    // yinelenen
            #"{"verdict":"answer","answers":{"Pick a color":["Blue"],"Pick fruits":["Apple, Cherry"]}}"#,    // birleşik dize etiket değil
            #"{"verdict":"answer","answers":{"Pick a color":["Blue"],"Pick fruits":["Apple"],"Ekstra":["x"]}}"#, // fazla soru
            #"{"verdict":"answer","answers":{"Başka soru":["Blue"],"Pick fruits":["Apple"]}}"#,              // bilinmeyen soru
            #"{"verdict":"answer","answers":{"Pick a color":[1],"Pick fruits":["Apple"]}}"#,
            #"{"verdict":"allow"}"#, #"{"verdict":"deny"}"#,                                                  // soru için izin/ret yok
        ]
        for json in bad {
            XCTAssertEqual(try run(question, args: verdictArgs(json)).output, "", json)
        }
        // Bozuk soru girdisi hiç tutulmaz (terminal yanıtlasın).
        let broken = question.replacingOccurrences(of: #""options":[{"label":"Blue","description":"b"},{"label":"Red","description":"r"}]"#, with: #""options":[]"#)
        XCTAssertEqual(try run(broken).output, "")
    }

    func testExitPlanModeAllowEchoesInputAndAcceptsMode() throws {
        try enable()
        let plan = """
        {"hook_event_name":"PermissionRequest","session_id":"s1","cwd":"/x/P","permission_mode":"plan","tool_name":"ExitPlanMode","tool_input":{"plan":"1. Do it"}}
        """
        let request = try object(try run(plan).output)
        XCTAssertEqual(request["preview"] as? String, "1. Do it")
        let d = try decision(try run(plan, args: verdictArgs(#"{"verdict":"allow","mode":"acceptEdits"}"#)).output)
        XCTAssertEqual((d["updatedInput"] as? [String: Any])?["plan"] as? String, "1. Do it")
        XCTAssertEqual((d["updatedPermissions"] as? [[String: Any]])?.first?["mode"] as? String, "acceptEdits")
    }

    // MARK: Hook kaydı

    func testDecideHookIsSynchronousAndOnlyOnPermissionRequest() throws {
        let hooks = try XCTUnwrap(generator.hooksJSON["hooks"] as? [String: Any])
        for (name, value) in hooks {
            let groups = try XCTUnwrap(value as? [[String: Any]])
            let commands = groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            let decide = commands.filter { ($0["command"] as? String)?.contains("decide.py") == true }
            if name == "PermissionRequest" {
                XCTAssertEqual(decide.count, 1)
                XCTAssertNil(decide[0]["async"], "decide senkron olmalı")
                XCTAssertEqual(decide[0]["timeout"] as? Int, 600)
                XCTAssertNil(decide[0]["onFailure"], "hata = engelleme DEĞİL")
            } else {
                XCTAssertTrue(decide.isEmpty, "\(name) decide çalıştırmamalı")
            }
        }
        XCTAssertNil(hooks["PreToolUse"].flatMap { ($0 as? [[String: Any]])?.count }.flatMap { $0 > 1 ? $0 : nil }, "PreToolUse'a ek hook yok (terminali bloklar)")
        // Python yoksa decide hiç kaydedilmez.
        let noPython = AgentPluginGenerator(root: tmp.appending(path: "np", directoryHint: .isDirectory), usesPython: false)
        let groups = try XCTUnwrap((noPython.hooksJSON["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }.allSatisfy { ($0["command"] as? String)?.contains("decide") == false })
    }

    func testControlConfigKeysAreWrittenWithoutDisturbingPortTokenOrTargets() throws {
        try generator.writeConfig(port: 51000, token: "tok", showTargets: true)
        XCTAssertFalse(generator.readControlEnabled(), "varsayılan kapalı")
        try generator.setControlEnabled(true)
        XCTAssertTrue(generator.readControlEnabled())
        XCTAssertTrue(generator.readShowTargets())
        XCTAssertEqual(generator.readConfig()?.port, 51000)
        try generator.writeConfig(port: 51001, token: "tok") // controlEnabled verilmezse korunur
        XCTAssertTrue(generator.readControlEnabled())
        let mode = try FileManager.default.attributesOfItem(atPath: generator.configURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        XCTAssertTrue(generator.auditLogURL.path.hasPrefix(tmp.path), "test denetim kaydı geçici dizinde")
    }

    // MARK: Sertleştirme (bağımsız inceleme)

    private func permissionInput(_ suggestions: [[String: Any]]) throws -> String {
        let object: [String: Any] = ["hook_event_name": "PermissionRequest", "session_id": "s1", "cwd": "/Users/x/Proj", "permission_mode": "default",
                                     "tool_name": "Bash", "tool_input": ["command": "npm test"], "permission_suggestions": suggestions]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func rules(_ count: Int, content: String = "npm test") -> [String: Any] {
        ["type": "addRules", "behavior": "allow", "destination": "localSettings",
         "rules": (0..<count).map { ["toolName": "Tool\($0)", "ruleContent": content] }]
    }

    private func offeredIndexes(_ suggestions: [[String: Any]]) throws -> [Int] {
        let request = try object(try run(permissionInput(suggestions)).output)
        return ((request["suggestions"] as? [[String: Any]]) ?? []).compactMap { $0["index"] as? Int }
    }

    func testTruncatedOrPartlyHiddenSuggestionsAreNeverOffered() throws {
        try enable()
        let sevenDirs: [String: Any] = ["type": "addDirectories", "directories": (0..<7).map { "/tmp/d\($0)" }, "destination": "session"]
        let sixDirs: [String: Any] = ["type": "addDirectories", "directories": (0..<6).map { "/tmp/d\($0)" }, "destination": "session"]
        let badRuleAmongGood: [String: Any] = ["type": "addRules", "behavior": "allow", "destination": "session",
                                               "rules": [["toolName": "Bash", "ruleContent": "ls"], ["toolName": "", "ruleContent": "whoami"]]]
        let newlineContent = rules(1, content: "echo a\nwhoami")
        let suggestions: [[String: Any]] = [
            rules(6),                                  // 0: 6 kural sığar
            rules(7),                                  // 1: 7 kural: etiket 6'yı gösterir, 7.si gizli kalırdı
            rules(1, content: String(repeating: "x", count: 150)), // 2: 200 sınırı altında
            rules(1, content: String(repeating: "x", count: 300)), // 3: 200 karaktere kesilirdi
            badRuleAmongGood,                          // 4: geçersiz kural atlanırdı (kalıcı izinde yine de olurdu)
            sevenDirs,                                 // 5
            sixDirs,                                   // 6
            newlineContent,                            // 7: süzme etiketi değiştirirdi
        ]
        let offered = try offeredIndexes(suggestions)
        XCTAssertEqual(offered, [0, 2, 6], "yalnızca etiketi tam gösterilebilenler sunulur")
        // Sunulmayan öneri, doğrudan verilen kararla da kalıcı izne dönüşmez (betik çıktısız çıkar).
        for index in [1, 3, 4, 5, 7] {
            let out = try run(permissionInput(suggestions), args: verdictArgs(#"{"verdict":"allow","suggestion":\#(index),"scope":"user"}"#)).output
            XCTAssertEqual(out, "", "öneri \(index) reddedilmeli")
        }
        let ok = try decision(try run(permissionInput(suggestions), args: verdictArgs(#"{"verdict":"allow","suggestion":2,"scope":"user"}"#)).output)
        XCTAssertEqual(ok["behavior"] as? String, "allow")
        XCTAssertNotNil(ok["updatedPermissions"])
    }

    private func questionInput(_ questions: [[String: Any]]) throws -> String {
        let object: [String: Any] = ["hook_event_name": "PermissionRequest", "session_id": "s1", "cwd": "/Users/x/Proj",
                                     "tool_name": "AskUserQuestion", "tool_input": ["questions": questions]]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    func testQuestionsWithDuplicateOptionLabelsOrQuestionsAreNotOffered() throws {
        try enable()
        func q(_ text: String, _ labels: [String]) -> [String: Any] {
            ["question": text, "header": "H", "multiSelect": false, "options": labels.map { ["label": $0] }]
        }
        XCTAssertNotEqual(try run(questionInput([q("Renk?", ["Mavi", "Kırmızı"])])).output, "", "geçerli soru sunulur")
        XCTAssertEqual(try run(questionInput([q("Renk?", ["Mavi", "Mavi"])])).output, "", "yinelenen etiket: terminal yanıtlasın")
        XCTAssertEqual(try run(questionInput([q("Renk?", ["Mavi", " Mavi "])])).output, "", "süzmeden sonra aynı etiket")
        XCTAssertEqual(try run(questionInput([q("Renk?", ["Mavi"]), q("Renk?", ["Kırmızı"])])).output, "", "aynı soru metni iki kez")
        // Yinelenen etiketli soru cevap olarak da kabul edilmez.
        let dup = try questionInput([q("Renk?", ["Mavi", "Mavi"])])
        XCTAssertEqual(try run(dup, args: verdictArgs(#"{"verdict":"answer","answers":{"Renk?":["Mavi"]}}"#)).output, "")
    }

    /// Komut satırı argümanı yerel ayara bağlı çözülür (gerçek hook gövdeyi stdin/HTTP'den okur): ASCII dışını \\uXXXX yap.
    private func asciiJSON(_ json: String) -> String {
        json.utf16.map { $0 < 128 ? String(UnicodeScalar(UInt8($0))) : String(format: "\\u%04x", $0) }.joined()
    }

    func testQuestionKeysMatchSwiftCleanForUnicodeEdgeCases() throws {
        try enable()
        let family = String(repeating: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}", count: 100) // 700 kod noktası, 100 Character
        let combining = String(repeating: "e\u{301}", count: 400)                                                      // 800 kod noktası, 400 Character
        let texts = ["  \u{2028}Merhaba dünya\u{2029} ", family, combining, "a\u{00A0}b\u{3000}", "\u{200B}x\u{85}y", "\u{1C}z\u{1F}", "plain?"]
        for text in texts {
            let key = try XCTUnwrap(DecisionRequest.clean(text, max: DecisionLimits.maxQuestion), "boş kalmamalı: \(text.unicodeScalars.count)")
            let input = try questionInput([["question": text, "header": "H", "multiSelect": false, "options": [["label": "A"], ["label": "B"]]]])
            let body = try run(input).output
            let sent = try XCTUnwrap(DecisionRequest(json: Data(body.utf8)), "istek sunulmalı")
            XCTAssertEqual(sent.questions.first?.question.unicodeScalars.map(\.value), key.unicodeScalars.map(\.value), "Python ve Swift aynı kırpmayı yapmalı")
            // Swift'in gönderdiği cevap anahtarı betikte eşleşir ve özgün soru metniyle geri verilir.
            let answers = asciiJSON(try String(decoding: JSONSerialization.data(withJSONObject: ["verdict": "answer", "answers": [key: ["A"]]]), as: UTF8.self))
            let raw = try run(input, args: verdictArgs(answers)).output
            guard !raw.isEmpty else { XCTFail("cevap anahtarı eşleşmedi: \(text.unicodeScalars.count) kod noktası, anahtar \(key.unicodeScalars.count)"); continue }
            let out = try decision(raw)
            XCTAssertEqual(out["behavior"] as? String, "allow")
            let updated = try XCTUnwrap(out["updatedInput"] as? [String: Any])
            XCTAssertEqual((updated["answers"] as? [String: String])?[text], "A")
        }
    }

    func testClearControlEnabledOnlyWritesWhenTrueAndNeverCreatesFile() throws {
        let absent = AgentPluginGenerator(root: tmp.appending(path: "none", directoryHint: .isDirectory), usesPython: true)
        absent.clearControlEnabled()
        XCTAssertFalse(FileManager.default.fileExists(atPath: absent.configURL.path), "dosya yoksa oluşturulmaz")
        try generator.writeConfig(port: 51000, token: "tok", showTargets: true, controlEnabled: true)
        generator.clearControlEnabled()
        XCTAssertFalse(generator.readControlEnabled())
        XCTAssertTrue(generator.readShowTargets())
        XCTAssertEqual(generator.readConfig()?.port, 51000, "port/token korunur")
        XCTAssertEqual(generator.readConfig()?.token, "tok")
        XCTAssertEqual(try run(permission).output, "", "kapalıyken betik çıktısız çıkar")
    }
}
