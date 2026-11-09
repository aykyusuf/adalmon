import Foundation
import XCTest
@testable import Adalmon

// Gerçek Safari / Chrome / ağ çağrısı YOK: tüm kaynaklar sahte.

final class SafariTabsLogicTests: XCTestCase {
    private let rs = "\u{1E}", us = "\u{1F}"

    func testParseKeepsWindowsAndHandlesCommasNewlinesAndEmptyURL() {
        let out = "1\(us)1\(us)Haberler, son dakika\(us)https://a.com/x\(rs)"
            + "1\(us)2\(us)İki\nsatır\(us)\(rs)"
            + "2\(us)1\(us)\(us)https://b.org\(rs)"
        let tabs = SafariTabsScript.parse(out)
        XCTAssertEqual(tabs, [
            SafariTab(window: 1, index: 1, title: "Haberler, son dakika", url: "https://a.com/x"),
            SafariTab(window: 1, index: 2, title: "İki\nsatır", url: ""),
            SafariTab(window: 2, index: 1, title: "", url: "https://b.org"),
        ])
        XCTAssertEqual(Set(tabs.map(\.id)).count, 3)
    }

    func testParseSkipsMalformedRecordsAndNotRunningMarker() {
        XCTAssertEqual(SafariTabsScript.parse("x\(us)1\(us)t\(us)u\(rs)1\(us)t\(rs)\(rs)"), [])
        XCTAssertEqual(SafariTabsScript.parse(""), [])
        XCTAssertEqual(SafariTabsScript.parse(SafariTabsScript.notRunningMarker), [])
        XCTAssertTrue(SafariTabsScript.isNotRunning(SafariTabsScript.notRunningMarker))
        // URL içinde ayırıcı yoksa da başlıkta US olsa bile 4. alan kalanı alır.
        XCTAssertEqual(SafariTabsScript.parse("3\(us)4\(us)a\(us)b\(us)c").first?.url, "b\(us)c")
    }

    func testScriptNeverLaunchesSafariAndHasTimeout() {
        let s = SafariTabsScript.source
        XCTAssertTrue(s.hasPrefix("if application id \"com.apple.Safari\" is running then"))
        XCTAssertTrue(s.contains("with timeout of \(SafariTabsScript.timeoutSeconds) seconds"))
        XCTAssertTrue(s.contains("character id 30") && s.contains("character id 31"))
        XCTAssertTrue(s.contains(SafariTabsScript.notRunningMarker))
    }

    func testPermissionAndErrorMapping() {
        XCTAssertEqual(SafariAutomationPermission.from(status: 0), .granted)
        XCTAssertEqual(SafariAutomationPermission.from(status: -1744), .notDetermined)
        XCTAssertEqual(SafariAutomationPermission.from(status: -1743), .denied)
        XCTAssertEqual(SafariAutomationPermission.from(status: -600), .safariNotRunning)
        XCTAssertEqual(SafariAutomationPermission.from(status: -50), .unknown(-50))
        XCTAssertEqual(SafariTabsError.from(appleScriptError: -1743), .permissionDenied)
        XCTAssertEqual(SafariTabsError.from(appleScriptError: -1712), .timeout)
        XCTAssertEqual(SafariTabsError.from(appleScriptError: -600), .notRunning)
        XCTAssertEqual(SafariTabsError.from(appleScriptError: -2741), .scriptFailed(-2741))
        XCTAssertTrue(SafariTabsError.permissionDenied.message.contains("Otomasyon"))
    }

    func testMemorySummarySortsTotalsAndAveragesOverAllTabs() {
        let s = SafariMemorySummary(processes: [.init(pid: 5, footprint: 100), .init(pid: 3, footprint: 400), .init(pid: 4, footprint: 100)],
                                    tabCount: 3)
        XCTAssertEqual(s.processes.map(\.pid), [3, 4, 5])
        XCTAssertEqual(s.total, 600)
        XCTAssertEqual(s.averagePerTab, 200)
        XCTAssertNil(SafariMemorySummary(processes: [.init(pid: 1, footprint: 9)], tabCount: 0).averagePerTab)
    }

    func testWebContentFilterUsesResponsibleProcessNotName() {
        let paths: [Int32: String] = [
            10: "/Applications/Safari.app/Contents/MacOS/Safari",
            11: "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent",
            12: "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.Networking.xpc/Contents/MacOS/com.apple.WebKit.Networking",
            13: "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent",
            14: "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU",
            15: "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent",
        ]
        // 13 Mail'in (pid 20) WebContent'i; 15'in ayak izi okunamıyor.
        let owner: [Int32: Int32] = [10: 10, 11: 10, 12: 10, 13: 20, 14: 10, 15: 10]
        let foot: [Int32: UInt64] = [10: 1, 11: 500, 12: 50, 13: 900, 14: 70]
        let out = SafariWebContentFilter.select(pids: [10, 11, 12, 13, 14, 15], safariPIDs: [10], path: { paths[$0] },
                                                responsible: { owner[$0] }, footprint: { foot[$0] })
        XCTAssertEqual(out, [WebContentProcess(pid: 11, footprint: 500)])
        XCTAssertEqual(SafariWebContentFilter.select(pids: [11], safariPIDs: [], path: { paths[$0] }, responsible: { owner[$0] },
                                                     footprint: { foot[$0] }), [])
    }
}

final class ChromeDebugLogicTests: XCTestCase {
    func testOpenArgumentsUseSeparateProfileLoopbackAndNewInstance() {
        let dir = ChromeDebugConfig.userDataDirectory(applicationSupport: URL(fileURLWithPath: "/Users/x/Library/Application Support"))
        XCTAssertEqual(dir.path, "/Users/x/Library/Application Support/Adalmon/ChromeDebug")
        let args = ChromeDebugConfig.openArguments(appPath: "/Applications/Google Chrome.app", port: 51_234, userDataDir: dir.path)
        XCTAssertEqual(Array(args.prefix(4)), ["-n", "-a", "/Applications/Google Chrome.app", "--args"])
        XCTAssertTrue(args.contains("--remote-debugging-port=51234"))
        XCTAssertTrue(args.contains("--remote-debugging-address=127.0.0.1"))
        // Boşluklu yol tek argüman (kabuk yok, tırnak yok).
        XCTAssertTrue(args.contains("--user-data-dir=/Users/x/Library/Application Support/Adalmon/ChromeDebug"))
        XCTAssertFalse(args.contains { $0.contains("remote-allow-origins") })
    }

    func testPortPickerSkipsBusyAndOutOfRange() {
        var seq = [80, 50_000, 50_001, 50_002]
        let port = DebugPortPicker.pick(random: { _ in seq.removeFirst() }, isFree: { $0 == 50_001 })
        XCTAssertEqual(port, 50_001)
        XCTAssertNil(DebugPortPicker.pick(attempts: 5, random: { _ in 50_000 }, isFree: { _ in false }))
        let real = DebugPortPicker.pick(isFree: { _ in true })
        XCTAssertTrue(ChromeDebugConfig.portRange.contains(real ?? 0))
    }

    func testDevToolsActivePortParsing() {
        XCTAssertEqual(DevToolsActivePort.parse("53211\n/devtools/browser/abc\n"), 53_211)
        XCTAssertNil(DevToolsActivePort.parse(""))
        XCTAssertNil(DevToolsActivePort.parse("abc\n1"))
        XCTAssertNil(DevToolsActivePort.parse("70000"))
    }

    func testEndpointGuardAllowsOnlyLoopbackAndExpectedPort() {
        func ok(_ s: String, _ port: Int = 9_222) -> Bool { CDPEndpointGuard.isAllowed(URL(string: s)!, port: port) }
        XCTAssertTrue(ok("ws://127.0.0.1:9222/devtools/page/A"))
        XCTAssertTrue(ok("ws://localhost:9222/devtools/browser/B"))
        XCTAssertFalse(ok("ws://127.0.0.1:9223/devtools/page/A"))
        XCTAssertFalse(ok("ws://192.168.1.5:9222/devtools/page/A"))
        XCTAssertFalse(ok("ws://evil.example:9222/devtools/page/A"))
        XCTAssertFalse(ok("wss://127.0.0.1:9222/devtools/page/A"))
        XCTAssertFalse(ok("ws://127.0.0.1/devtools/page/A"))
        XCTAssertEqual(CDPEndpointGuard.httpURL(port: 9_222, path: "/json/list")?.absoluteString, "http://127.0.0.1:9222/json/list")
    }

    func testCodecParsesTargetsVersionRepliesMetricsAndProcesses() throws {
        let list = Data("""
        [{"id":"A","type":"page","title":"Bir, iki","url":"https://a.com","webSocketDebuggerUrl":"ws://127.0.0.1:9222/devtools/page/A"},
         {"id":"W","type":"service_worker","title":"sw","url":"https://a.com/sw.js"},
         {"id":"B","type":"page","title":"B","url":"chrome://newtab/"}]
        """.utf8)
        let targets = try CDPCodec.targets(from: list)
        XCTAssertEqual(targets.map(\.id), ["A", "B"])
        XCTAssertNil(targets[1].webSocketDebuggerUrl)

        let version = try CDPCodec.version(from: Data(#"{"Browser":"Chrome/142.0","webSocketDebuggerUrl":"ws://127.0.0.1:9222/devtools/browser/x"}"#.utf8))
        XCTAssertEqual(version.browser, "Chrome/142.0")

        XCTAssertNil(CDPCodec.reply(from: Data(#"{"method":"Performance.metrics","params":{}}"#.utf8)))
        XCTAssertEqual(CDPCodec.reply(from: Data(#"{"id":3,"error":{"code":-32601,"message":"'SystemInfo.getProcessInfo' wasn't found"}}"#.utf8))?.errorMessage,
                       "'SystemInfo.getProcessInfo' wasn't found")
        let reply = try XCTUnwrap(CDPCodec.reply(from: Data(#"{"id":7,"result":{"metrics":[{"name":"JSHeapUsedSize","value":1048576},{"name":"JSHeapTotalSize","value":2097152},{"name":"Nodes","value":1500},{"name":"Timestamp","value":12.5}]}}"#.utf8)))
        XCTAssertEqual(reply.id, 7)
        let metrics = try XCTUnwrap(CDPCodec.metrics(from: try XCTUnwrap(reply.result)))
        XCTAssertEqual(metrics, CDPTabMetrics(jsHeapUsed: 1_048_576, jsHeapTotal: 2_097_152, nodes: 1_500, documents: nil))

        let procs = CDPCodec.processes(from: Data(#"{"processInfo":[{"type":"browser","id":100,"cpuTime":3.5},{"type":"renderer","id":101,"cpuTime":1},{"type":"renderer","id":0,"cpuTime":0}]}"#.utf8))
        XCTAssertEqual(procs, [CDPProcess(type: "browser", id: 100, cpuTime: 3.5), CDPProcess(type: "renderer", id: 101, cpuTime: 1)])

        let request = try JSONSerialization.jsonObject(with: CDPCodec.request(id: 4, method: "Performance.getMetrics")) as? [String: Any]
        XCTAssertEqual(request?["id"] as? Int, 4)
        XCTAssertEqual(request?["method"] as? String, "Performance.getMetrics")
    }

    func testRendererMemoryCountsOnlyChromeRenderers() {
        let procs = [CDPProcess(type: "browser", id: 1, cpuTime: 0), CDPProcess(type: "renderer", id: 2, cpuTime: 0),
                     CDPProcess(type: "renderer", id: 3, cpuTime: 0), CDPProcess(type: "renderer", id: 4, cpuTime: 0)]
        let paths: [Int32: String] = [1: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                                      2: "/Applications/Google Chrome.app/Contents/Frameworks/x/Google Chrome Helper (Renderer)",
                                      3: "/usr/bin/other",  // pid yeniden kullanılmış: sayılmaz
                                      4: "/Applications/Google Chrome.app/Contents/Frameworks/x/Google Chrome Helper (Renderer)"]
        let m = ChromeRendererMemory.make(processes: procs, path: { paths[$0] }, footprint: { $0 == 4 ? nil : UInt64($0) * 100 })
        XCTAssertEqual(m, ChromeRendererMemory(count: 1, total: 200, perPID: [2: 200]), "yalnızca Chrome renderer'ı; pid başına ayak izi de tutulur")
    }
}

// MARK: Sahte CDP taşıması

private final class FakeSocket: CDPSocket, @unchecked Sendable {
    private let lock = NSLock()
    private let handler: @Sendable (String) -> String?
    private var stream: AsyncStream<Data>
    private var continuation: AsyncStream<Data>.Continuation
    private var iterator: AsyncStream<Data>.Iterator
    private(set) var methods: [String] = []
    private(set) var closed = false

    init(handler: @escaping @Sendable (String) -> String?) {
        self.handler = handler
        let (s, c) = AsyncStream<Data>.makeStream()
        stream = s
        continuation = c
        iterator = s.makeAsyncIterator()
    }

    func send(_ data: Data) async throws {
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let id = obj?["id"] as? Int ?? 0
        let method = obj?["method"] as? String ?? ""
        lock.withLock { methods.append(method) }
        // Önce ilgisiz bir olay: istemci bunu atlamalı.
        continuation.yield(Data(#"{"method":"Inspector.noise","params":{}}"#.utf8))
        if let result = handler(method) { continuation.yield(Data("{\"id\":\(id),\(result)}".utf8)) }
    }

    func receive() async throws -> Data {
        var it = lock.withLock { iterator }
        let next = await it.next()
        lock.withLock { iterator = it }
        guard let next else { throw CDPError.closed }
        return next
    }

    func close() {
        lock.withLock { closed = true }
        continuation.finish()
    }
}

private final class FakeTransport: CDPHTTPClient, CDPSocketFactory, @unchecked Sendable {
    private let lock = NSLock()
    var listJSON: String
    var versionJSON = #"{"Browser":"Chrome","webSocketDebuggerUrl":"ws://127.0.0.1:9222/devtools/browser/x"}"#
    var failList = false
    var handler: @Sendable (String) -> String? = { method in
        switch method {
        case "Performance.enable": return #""result":{}"#
        case "Performance.getMetrics": return #""result":{"metrics":[{"name":"JSHeapUsedSize","value":10},{"name":"Nodes","value":3}]}"#
        case "SystemInfo.getProcessInfo": return #""error":{"code":-32601,"message":"not found"}"#
        default: return nil
        }
    }
    /// Verilirse her soket kendi adresine göre davranır (sekme ↔ süreç eşleme testleri için).
    var handlerFactory: (@Sendable (URL) -> (@Sendable (String) -> String?))?
    private(set) var sockets: [(URL, FakeSocket)] = []

    init(listJSON: String) { self.listJSON = listJSON }

    func get(_ url: URL) async throws -> Data {
        if url.path == "/json/list" {
            if lock.withLock({ failList }) { throw CDPError.closed }
            return Data(lock.withLock { listJSON }.utf8)
        }
        return Data(versionJSON.utf8)
    }

    func connect(_ url: URL) -> any CDPSocket {
        let s = FakeSocket(handler: handlerFactory?(url) ?? handler)
        lock.withLock { sockets.append((url, s)) }
        return s
    }

    func socket(for path: String) -> FakeSocket? { lock.withLock { sockets.last { $0.0.path == path }?.1 } }
}

final class ChromeTabsPollerTests: XCTestCase {
    private static func list(_ ids: [String], host: String = "127.0.0.1") -> String {
        "[" + ids.map { #"{"id":"\#($0)","type":"page","title":"T\#($0)","url":"https://\#($0).com","webSocketDebuggerUrl":"ws://\#(host):9222/devtools/page/\#($0)"}"# }
            .joined(separator: ",") + "]"
    }

    func testPollCollectsMetricsEnablesOnceAndDropsVanishedTabs() async throws {
        let t = FakeTransport(listJSON: Self.list(["A", "B"]))
        let poller = ChromeTabsPoller(port: 9_222, http: t, sockets: t)
        let first = try await poller.poll()
        XCTAssertEqual(first.tabs.map(\.id), ["A", "B"])
        XCTAssertEqual(first.tabs.first?.metrics, CDPTabMetrics(jsHeapUsed: 10, jsHeapTotal: nil, nodes: 3, documents: nil))
        XCTAssertNil(first.processes, "SystemInfo hatası → nil")

        t.listJSON = Self.list(["A"])
        _ = try await poller.poll()
        let a = try XCTUnwrap(t.socket(for: "/devtools/page/A"))
        XCTAssertEqual(a.methods, ["Performance.enable", "Performance.getMetrics", "Performance.getMetrics"])
        XCTAssertTrue(try XCTUnwrap(t.socket(for: "/devtools/page/B")).closed, "kaybolan sekmenin soketi kapanır")
        // Deneysel alan desteklenmiyorsa yeniden denenmez.
        XCTAssertEqual(try XCTUnwrap(t.socket(for: "/devtools/browser/x")).methods, ["SystemInfo.getProcessInfo"])

        await poller.shutdown()
        XCTAssertTrue(a.closed)
        let open = await poller.openConnectionCount
        XCTAssertEqual(open, 0)
    }

    func testAllTabsListedButMetricsCappedAtMaxTabs() async throws {
        let ids = (0..<(ChromeTabsPoller.maxTabs + 5)).map { "T\($0)" }
        let t = FakeTransport(listJSON: Self.list(ids))
        let snap = try await ChromeTabsPoller(port: 9_222, http: t, sockets: t).poll()
        XCTAssertEqual(snap.tabs.count, ids.count)
        XCTAssertEqual(snap.tabs.filter { $0.metrics != nil }.count, ChromeTabsPoller.maxTabs)
        XCTAssertEqual(t.sockets.filter { $0.0.path.hasPrefix("/devtools/page/") }.count, ChromeTabsPoller.maxTabs)
    }

    func testNonLoopbackWebSocketURLIsNeverConnected() async throws {
        let t = FakeTransport(listJSON: Self.list(["A"], host: "10.0.0.2"))
        let snap = try await ChromeTabsPoller(port: 9_222, http: t, sockets: t).poll()
        XCTAssertEqual(snap.tabs.count, 1)
        XCTAssertNil(snap.tabs[0].metrics)
        XCTAssertFalse(t.sockets.contains { $0.0.host == "10.0.0.2" })
    }

    func testListFailureThrowsAndProcessInfoIsParsedWhenSupported() async throws {
        let t = FakeTransport(listJSON: Self.list(["A"]))
        t.handler = { method in
            switch method {
            case "SystemInfo.getProcessInfo": return #""result":{"processInfo":[{"type":"renderer","id":321,"cpuTime":2}]}"#
            case "Performance.enable": return #""result":{}"#
            default: return #""result":{"metrics":[]}"#
            }
        }
        let poller = ChromeTabsPoller(port: 9_222, http: t, sockets: t)
        let snap = try await poller.poll()
        XCTAssertEqual(snap.processes, [CDPProcess(type: "renderer", id: 321, cpuTime: 2)])
        XCTAssertEqual(snap.tabs.first?.metrics, CDPTabMetrics())
        t.failList = true
        do { _ = try await poller.poll(); XCTFail("hata beklenirdi") } catch {}
    }

    func testHangingTabTimesOutAndClosesConnection() async throws {
        let socket = FakeSocket { _ in nil }
        let connection = CDPConnection(socket: socket)
        let start = ContinuousClock.now
        do {
            _ = try await connection.call("Performance.getMetrics", timeout: .milliseconds(150))
            XCTFail("zaman aşımı beklenirdi")
        } catch {}
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(2))
        let closed = await connection.isClosed
        XCTAssertTrue(closed)
        XCTAssertTrue(socket.closed)
    }
}

// MARK: Model (Safari akışı, sahte kaynakla)

private final class FakeSafari: SafariTabsSource, @unchecked Sendable {
    private let lock = NSLock()
    var permissionValue: SafariAutomationPermission = .granted
    var tabs: [SafariTab] = [SafariTab(window: 1, index: 1, title: "A", url: "https://a"), SafariTab(window: 1, index: 2, title: "B", url: "https://b")]
    var error: SafariTabsError?
    private(set) var asks: [Bool] = []
    private(set) var fetches = 0
    var spinResult: SafariSpinResult = .ok
    /// Her `spin` çağrısında (pencere, sıra) ile çağrılır: testte ilgili sürecin CPU'sunu artırır.
    var onSpin: (@Sendable (Int, Int) -> Void)?

    func spin(window: Int, index: Int) async -> SafariSpinResult {
        onSpin?(window, index)
        return lock.withLock { spinResult }
    }

    func permission(ask: Bool) async -> SafariAutomationPermission {
        lock.withLock { asks.append(ask); return permissionValue }
    }

    func fetchTabs() async throws -> [SafariTab] {
        try lock.withLock {
            fetches += 1
            if let error { throw error }
            return tabs
        }
    }
}

@MainActor
final class BrowserTabsModelTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "BrowserTabsModelTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func make(_ safari: FakeSafari, defaults: UserDefaults) -> BrowserTabsModel {
        BrowserTabsModel(defaults: defaults, safari: safari, safariPIDs: { [10] },
                         webContentScan: { _ in [WebContentProcess(pid: 11, footprint: 300), WebContentProcess(pid: 12, footprint: 500)] },
                         useNetwork: false)
    }

    func testDisabledByDefaultMakesNoAppleEventCalls() async {
        let safari = FakeSafari()
        let model = make(safari, defaults: makeDefaults())
        XCTAssertFalse(model.safariEnabled)
        XCTAssertEqual(model.safariState, .off)
        await model.refreshSafari(ask: false)
        await model.requestSafariPermission()
        await model.runSafari { true }
        XCTAssertEqual(safari.asks, [])
        XCTAssertEqual(safari.fetches, 0)
        XCTAssertEqual(model.chromeState, .off)
    }

    func testNotDeterminedShowsPermissionStateWithoutPromptingOrFetching() async {
        let safari = FakeSafari()
        safari.permissionValue = .notDetermined
        let model = make(safari, defaults: makeDefaults())
        model.safariEnabled = true
        await model.refreshSafari(ask: false)
        XCTAssertEqual(model.safariState, .needsPermission)
        XCTAssertEqual(safari.asks, [false])
        XCTAssertEqual(safari.fetches, 0)
        await model.requestSafariPermission()
        XCTAssertEqual(safari.asks, [false, true], "izin penceresi yalnızca düğmeyle")
    }

    func testGrantedLoadsTabsAndHonestMemorySummaryThenDisableClears() async {
        let safari = FakeSafari()
        let defaults = makeDefaults()
        let model = make(safari, defaults: defaults)
        model.safariEnabled = true
        XCTAssertTrue(defaults.bool(forKey: BrowserTabsModel.safariEnabledKey))
        await model.refreshSafari(ask: false)
        XCTAssertEqual(model.safariState, .loaded)
        XCTAssertEqual(model.safariTabs.count, 2)
        XCTAssertEqual(model.safariMemory?.total, 800)
        XCTAssertEqual(model.safariMemory?.processes.map(\.pid), [12, 11])
        XCTAssertEqual(model.safariMemory?.averagePerTab, 400)

        model.safariEnabled = false
        XCTAssertEqual(model.safariState, .off)
        XCTAssertTrue(model.safariTabs.isEmpty)
        XCTAssertNil(model.safariMemory)
    }

    func testUnknownPermissionNeverRunsScriptAutomatically() async {
        let safari = FakeSafari()
        safari.permissionValue = .unknown(-1)
        let model = make(safari, defaults: makeDefaults())
        model.safariEnabled = true
        await model.refreshSafari(ask: false)
        XCTAssertEqual(safari.fetches, 0, "otomatik turda betik çalışırsa izin penceresi kendiliğinden açılır")
        XCTAssertEqual(model.safariState, .needsPermission)
        await model.requestSafariPermission()
        XCTAssertEqual(safari.fetches, 1, "düğme ile devam edilir")
        XCTAssertEqual(model.safariState, .loaded)
    }

    func testDeniedAndTimeoutStates() async {
        let safari = FakeSafari()
        let model = make(safari, defaults: makeDefaults())
        model.safariEnabled = true
        await model.refreshSafari(ask: false)
        XCTAssertEqual(model.safariState, .loaded)
        // Zaman aşımı son listeyi silmez.
        safari.error = .timeout
        await model.refreshSafari(ask: false)
        XCTAssertEqual(model.safariState, .loaded)
        XCTAssertEqual(model.safariTabs.count, 2)
        safari.error = .permissionDenied
        await model.refreshSafari(ask: false)
        XCTAssertEqual(model.safariState, .denied)
        XCTAssertTrue(model.safariTabs.isEmpty)
        safari.error = nil
        safari.permissionValue = .safariNotRunning
        await model.refreshSafari(ask: false)
        XCTAssertEqual(model.safariState, .notRunning)
    }
}


// MARK: Sekme ↔ süreç eşleme (ölçerek)

private final class CPUBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int32: Double]
    init(_ initial: [Int32: Double]) { values = initial }
    func add(_ pid: Int32, _ seconds: Double) { lock.withLock { values[pid, default: 0] += seconds } }
    func value(_ pid: Int32) -> Double? { lock.withLock { values[pid] } }
}

final class TabProcessProbeLogicTests: XCTestCase {
    func testAttributesTheProcessWhoseCPUJumped() {
        XCTAssertEqual(TabProcessProbe.attribute(before: [1: 10, 2: 20], after: [1: 10.01, 2: 20.16]), 2)
    }

    func testTooSmallOrAmbiguousDeltasAreNotAttributed() {
        XCTAssertNil(TabProcessProbe.attribute(before: [1: 0, 2: 0], after: [1: 0.02, 2: 0.03]), "döngü yarısından az")
        XCTAssertNil(TabProcessProbe.attribute(before: [1: 0, 2: 0], after: [1: 0.16, 2: 0.15]), "iki süreç birden yoğun: belirsiz")
        XCTAssertNil(TabProcessProbe.attribute(before: [:], after: [1: 5]), "önceki ölçüm yok")
        XCTAssertNil(TabProcessProbe.attribute(before: [1: 5], after: [1: 4]), "sayaç geri gitmez")
        XCTAssertEqual(TabProcessProbe.attribute(before: [1: 0, 2: 0], after: [1: 0.16, 2: 0.04]), 1, "ikinci çok küçükse net")
    }

    func testMapSharedCounts() {
        let map = TabProcessMap(pidByTab: ["a": 7, "b": 7, "c": 9], updatedAt: .now)
        XCTAssertEqual(map.sharedCount(for: 7), 2)
        XCTAssertEqual(map.tabKeys(for: 7), ["a", "b"])
        XCTAssertEqual(map.sharedCount(for: 1), 0)
    }

    @MainActor
    func testStoreLabelTruncatesAndCountsExtras() {
        let store = BrowserTabMapStore()
        store.set(source: "safari", titles: [5: ["YouTube", "X", "GitHub", "Çok uzun bir sekme başlığı burada devam ediyor"]])
        XCTAssertEqual(store.label(for: 5), "YouTube · X +2")
        store.set(source: "chrome", titles: [6: ["A"]])
        XCTAssertEqual(store.label(for: 6), "A")
        store.clear(source: "safari")
        XCTAssertNil(store.label(for: 5))
        XCTAssertEqual(store.label(for: 6), "A", "kaynaklar birbirini silmez")
    }
}

final class ChromeTabProbeTests: XCTestCase {
    private static let list = "[" + ["A", "B", "C", "D"].map {
        #"{"id":"\#($0)","type":"page","title":"T\#($0)","url":"https://\#($0).com","webSocketDebuggerUrl":"ws://127.0.0.1:9222/devtools/page/\#($0)"}"#
    }.joined(separator: ",") + "]"

    func testProbeMapsTabsToRenderersSharedAndAmbiguous() async throws {
        let box = CPUBox([101: 5, 102: 7])
        let t = FakeTransport(listJSON: Self.list)
        t.handlerFactory = { url in
            let tab = url.lastPathComponent
            return { method in
                switch method {
                case "SystemInfo.getProcessInfo":
                    return #""result":{"processInfo":[{"type":"renderer","id":101,"cpuTime":5},{"type":"renderer","id":102,"cpuTime":7},{"type":"gpu-process","id":9,"cpuTime":1}]}"#
                case "Runtime.evaluate":
                    switch tab {
                    case "A", "C": box.add(101, 0.16)          // A ve C aynı renderer'ı paylaşır
                    case "B": box.add(102, 0.16)
                    default: box.add(101, 0.16); box.add(102, 0.15)   // D: belirsiz
                    }
                    return #""result":{"result":{"type":"number","value":1}}"#
                default: return #""result":{}"#
                }
            }
        }
        let poller = ChromeTabsPoller(port: 9_222, http: t, sockets: t)
        let map = await poller.probeTabProcesses(cpu: { box.value($0) })
        XCTAssertEqual(map, ["A": 101, "B": 102, "C": 101])
        let evaluated = try XCTUnwrap(t.socket(for: "/devtools/page/A")).methods
        XCTAssertEqual(evaluated, ["Runtime.evaluate"])
        XCTAssertFalse(evaluated.contains("Page.navigate"), "sayfaya dokunulmaz: yalnızca boş döngü")
    }

    func testProbeReturnsEmptyWhenProcessInfoUnsupported() async {
        let t = FakeTransport(listJSON: Self.list)
        t.handlerFactory = { _ in { method in method == "SystemInfo.getProcessInfo" ? #""error":{"code":-32601,"message":"x"}"# : #""result":{}"# } }
        let map = await ChromeTabsPoller(port: 9_222, http: t, sockets: t).probeTabProcesses(cpu: { _ in 1 })
        XCTAssertTrue(map.isEmpty)
    }
}

@MainActor
final class SafariTabProbeModelTests: XCTestCase {
    private func make(_ safari: FakeSafari, box: CPUBox) -> BrowserTabsModel {
        let name = "SafariTabProbe-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(true, forKey: BrowserTabsModel.safariEnabledKey)
        return BrowserTabsModel(defaults: defaults, safari: safari, safariPIDs: { [10] },
                                webContentScan: { _ in [WebContentProcess(pid: 11, footprint: 300), WebContentProcess(pid: 12, footprint: 500)] },
                                useNetwork: false, cpuSeconds: { box.value($0) })
    }

    func testProbeMapsSafariTabsAndPublishesTitles() async {
        let box = CPUBox([11: 1, 12: 2])
        let safari = FakeSafari()
        safari.tabs = [SafariTab(window: 1, index: 1, title: "YouTube", url: "https://youtube.com"),
                       SafariTab(window: 1, index: 2, title: "GitHub", url: "https://github.com")]
        safari.onSpin = { _, index in box.add(index == 1 ? 12 : 11, 0.16) }
        let model = make(safari, box: box)
        await model.refreshSafari(ask: false)
        await model.probeSafari()
        XCTAssertEqual(model.safariProbe, .finished(mapped: 2, total: 2))
        XCTAssertEqual(model.safariMap.pidByTab[BrowserTabsModel.safariKey(for: model.safariTabs[0])], 12)
        XCTAssertEqual(model.safariMap.pidByTab[BrowserTabsModel.safariKey(for: model.safariTabs[1])], 11)
        XCTAssertEqual(BrowserTabMapStore.shared.label(for: 12), "YouTube")
        XCTAssertEqual(BrowserTabMapStore.shared.label(for: 11), "GitHub")
        BrowserTabMapStore.shared.clear(source: "safari")
    }

    func testJavascriptFromAppleEventsDisabledShowsGuidanceAndMapsNothing() async {
        let box = CPUBox([11: 1, 12: 2])
        let safari = FakeSafari()
        safari.spinResult = .javascriptDisabled
        let model = make(safari, box: box)
        await model.refreshSafari(ask: false)
        await model.probeSafari()
        XCTAssertEqual(model.safariProbe, .javascriptDisabled)
        XCTAssertTrue(model.safariMap.isEmpty)
    }

    func testUnmappedWhenNoProcessShowsClearCPUJump() async {
        let box = CPUBox([11: 1, 12: 2])
        let safari = FakeSafari()          // spin hiçbir CPU artırmaz
        let model = make(safari, box: box)
        await model.refreshSafari(ask: false)
        await model.probeSafari()
        XCTAssertEqual(model.safariProbe, .finished(mapped: 0, total: 2))
    }
}
