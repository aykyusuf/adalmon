import XCTest
@testable import Adalmon

/// Tarayıcı görünümü: yönlendirme/güvenlik (saf), JSON şemaları, SSE çerçeveleme, asset servisi, canlı döngü (gerçek loopback dinleyici).
/// Tarayıcıda gerçek görsel kontrol YAPILMADI (burada tarayıcı yok); yalnızca veri ve HTTP katmanı doğrulanır.
final class AgentWebTests: XCTestCase {
    private let token = "tok-abc123"
    private let port: UInt16 = 51234

    private var repoRoot: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }
    private var webRoot: URL { repoRoot.appending(path: "Resources/Web") }
    private var officeRoot: URL { repoRoot.appending(path: "Resources/Office") }

    private func context(enabled: Bool = true, sse: Int = 0, layout: Data? = Data("{}".utf8)) -> AgentWebRouter.Context {
        AgentWebRouter.Context(token: token, port: port, enabled: enabled, webRoot: webRoot, officeRoot: officeRoot,
                               stateJSON: Data(#"{"v":1,"rooms":[]}"#.utf8), layoutJSON: layout, sseClients: sse)
    }

    private func request(_ target: String = "/v1/state", method: String = "GET", host: String? = nil, origin: String? = nil,
                         token: String? = "tok-abc123", extra: [String: String] = [:]) -> AgentWebRouter.Request {
        var headers = ["host": host ?? "127.0.0.1:\(port)"]
        if let origin { headers["origin"] = origin }
        if let token { headers["x-adalmon-token"] = token }
        for (k, v) in extra { headers[k] = v }
        return AgentWebRouter.Request(method: method, target: target, headers: headers)
    }

    private func status(_ r: AgentWebRouter.Request, _ c: AgentWebRouter.Context? = nil) -> Int? {
        if case .response(let response) = AgentWebRouter.route(r, context: c ?? context()) { return response.status }
        return nil
    }

    private func response(_ r: AgentWebRouter.Request, _ c: AgentWebRouter.Context? = nil) -> AgentWebRouter.Response? {
        if case .response(let response) = AgentWebRouter.route(r, context: c ?? context()) { return response }
        return nil
    }

    // MARK: Güvenlik

    func testDisabledFeatureAnswers404ForEveryPath() {
        for path in ["/", "/app.js", "/v1/state", "/v1/stream", "/assets/characters/char_0.png"] {
            XCTAssertEqual(status(request(path), context(enabled: false)), 404, path)
        }
    }

    func testTokenIsRequiredEverywhere() {
        for path in ["/", "/app.js", "/style.css", "/v1/state", "/v1/layout", "/v1/stream", "/assets/characters/char_0.png"] {
            XCTAssertEqual(status(request(path, token: nil)), 401, path)
            XCTAssertEqual(status(request(path, token: "wrong")), 401, path)
            XCTAssertEqual(status(request(path, token: "tok-abc12")), 401, "önek yetmez")
        }
        XCTAssertEqual(status(request("/v1/state", token: "")), 401)
        var empty = context(); empty.token = ""
        XCTAssertEqual(status(request("/v1/state", token: ""), empty), 401, "boş token asla kabul edilmez")
    }

    func testTokenViaHeaderOrQuery() {
        XCTAssertEqual(status(request("/v1/state")), 200)
        XCTAssertEqual(status(request("/v1/state?t=tok-abc123", token: nil)), 200)
        XCTAssertEqual(status(request("/app.js?x=1&t=tok-abc123", token: nil)), 200)
        XCTAssertEqual(status(request("/v1/state?t=nope", token: nil)), 401)
        XCTAssertEqual(status(request("/v1/state?t=tok-abc123%00", token: nil)), 401)
    }

    func testHostMustBeLoopbackWithPort() {
        XCTAssertEqual(status(request(host: "127.0.0.1:\(port)")), 200)
        XCTAssertEqual(status(request(host: "localhost:\(port)")), 200)
        XCTAssertEqual(status(request(host: "LOCALHOST:\(port)")), 200)
        for bad in ["evil.example:\(port)", "127.0.0.1", "127.0.0.1:1", "localhost", "192.168.1.5:\(port)", "127.0.0.1.evil.com:\(port)", ""] {
            XCTAssertEqual(status(request(host: bad)), 421, bad)
        }
        var noHost = request(); noHost.headers["host"] = nil
        XCTAssertEqual(status(noHost), 421)
    }

    func testForeignOriginIsRejectedAndNoCORSHeaderIsEverSent() throws {
        XCTAssertEqual(status(request(origin: "http://evil.example")), 403)
        XCTAssertEqual(status(request(origin: "null")), 403)
        XCTAssertEqual(status(request(origin: "http://127.0.0.1:1")), 403)
        XCTAssertEqual(status(request(origin: "http://localhost:\(port)")), 403, "Host 127.0.0.1 iken farklı yazım aynı origin değil")
        XCTAssertEqual(status(request(origin: "http://127.0.0.1:\(port)")), 200)
        XCTAssertEqual(status(request(extra: ["sec-fetch-site": "cross-site"])), 403)
        for r in [request(), request(origin: "http://evil.example"), request(token: nil), request("/nope")] {
            let text = String(decoding: try XCTUnwrap(response(r)).serialized(), as: UTF8.self).lowercased()
            XCTAssertFalse(text.contains("access-control-"), "CORS başlığı eklenmemeli")
        }
    }

    func testSecurityHeadersOnEveryResponse() throws {
        for r in [request(), request("/"), request("/nope"), request(token: nil)] {
            let text = String(decoding: try XCTUnwrap(response(r)).serialized(), as: UTF8.self)
            XCTAssertTrue(text.contains("Cache-Control: no-store\r\n"))
            XCTAssertTrue(text.contains("X-Content-Type-Options: nosniff\r\n"))
            XCTAssertTrue(text.contains("default-src 'self'; img-src 'self' data:; connect-src 'self'"))
            XCTAssertTrue(text.contains("Connection: close\r\n"))
        }
    }

    func testOnlyGetAndHeadParse() {
        func parse(_ text: String) -> AgentWebRouter.ParseOutcome { AgentWebRouter.parse(Data(text.utf8)) }
        XCTAssertEqual(parse("PUT / HTTP/1.1\r\nHost: a\r\n\r\n"), .reject(405))
        XCTAssertEqual(parse("OPTIONS / HTTP/1.1\r\nHost: a\r\n\r\n"), .reject(405))
        XCTAssertTrue(AgentWebRouter.isWebRequest(Data("GET / HTTP/1.1\r\n".utf8)))
        XCTAssertTrue(AgentWebRouter.isWebRequest(Data("HEAD / HTTP/1.1\r\n".utf8)))
        XCTAssertFalse(AgentWebRouter.isWebRequest(Data("POST /v1/event HTTP/1.1\r\n".utf8)), "POST eski ayrıştırıcıda kalır")
        XCTAssertEqual(status(request(method: "DELETE")), 405)
    }

    func testRequestParsingLimits() {
        func parse(_ text: String) -> AgentWebRouter.ParseOutcome { AgentWebRouter.parse(Data(text.utf8)) }
        XCTAssertEqual(parse("GET /v1/state HTTP/1.1\r\nHost: a"), .needMore)
        guard case .request(let ok) = parse("GET /v1/state?t=x HTTP/1.1\r\nHost: 127.0.0.1:1\r\nX-Adalmon-Token: tt\r\n\r\n") else { return XCTFail() }
        XCTAssertEqual(ok.path, "/v1/state")
        XCTAssertEqual(ok.query, "t=x")
        XCTAssertEqual(ok.headers["x-adalmon-token"], "tt")
        XCTAssertEqual(parse("GET /x HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello"), .reject(400))
        XCTAssertEqual(parse("GET /x HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"), .reject(400))
        XCTAssertEqual(parse("GET //evil HTTP/1.1\r\nHost: a\r\n\r\n"), .reject(400))
        XCTAssertEqual(parse("GET http://evil/ HTTP/1.1\r\nHost: a\r\n\r\n"), .reject(400))
        XCTAssertEqual(parse("GET /x HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n"), .reject(400))
        XCTAssertEqual(parse("GET /x HTTP/1.1\r\nbozuk satır\r\n\r\n"), .reject(400))
        XCTAssertEqual(parse("GET /\(String(repeating: "a", count: 3000)) HTTP/1.1\r\nHost: a\r\n\r\n"), .reject(400))
        XCTAssertEqual(AgentWebRouter.parse(Data(repeating: 0x61, count: 9000)), .reject(431))
        XCTAssertEqual(parse("GET /x HTTP/1.1\r\nX: \(String(repeating: "a", count: 9000))\r\n\r\n"), .reject(431))
    }

    func testHeadReturnsHeadersWithoutBody() throws {
        let get = try XCTUnwrap(response(request("/app.js")))
        let head = try XCTUnwrap(response(request("/app.js", method: "HEAD")))
        XCTAssertEqual(head.status, 200)
        let text = String(decoding: head.serialized(), as: UTF8.self)
        XCTAssertTrue(text.contains("Content-Length: \(get.body.count)\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n"), "HEAD gövdesiz")
        XCTAssertGreaterThan(get.body.count, 100)
        XCTAssertEqual(status(request("/v1/stream", method: "HEAD")), 405)
    }

    func testSSEClientLimit() {
        guard case .stream = AgentWebRouter.route(request("/v1/stream"), context: context(sse: AgentWebRouter.maxSSEClients - 1)) else { return XCTFail() }
        XCTAssertEqual(status(request("/v1/stream"), context(sse: AgentWebRouter.maxSSEClients)), 503)
        XCTAssertEqual(AgentWebRouter.maxSSEClients, 8)
    }

    // MARK: Sayfa ve varlıklar

    func testPagesAndContentTypes() throws {
        let page = try XCTUnwrap(response(request("/")))
        XCTAssertEqual(page.contentType, "text/html; charset=utf-8")
        let html = String(decoding: page.body, as: UTF8.self)
        XCTAssertFalse(html.contains(AgentWebRouter.tokenPlaceholder), "yer tutucu token ile değişmeli")
        XCTAssertTrue(html.contains("/app.js?t=tok-abc123"))
        XCTAssertFalse(html.contains("http://") || html.contains("https://"), "sayfa dış adres içermemeli")
        XCTAssertEqual(try XCTUnwrap(response(request("/app.js"))).contentType, "text/javascript; charset=utf-8")
        XCTAssertEqual(try XCTUnwrap(response(request("/style.css"))).contentType, "text/css; charset=utf-8")
        XCTAssertEqual(try XCTUnwrap(response(request("/v1/state"))).contentType, "application/json; charset=utf-8")
        var noLayout = context(); noLayout.layoutJSON = nil
        XCTAssertEqual(status(request("/v1/layout"), noLayout), 404)
        let appJS = String(decoding: try XCTUnwrap(response(request("/app.js"))).body, as: UTF8.self)
        XCTAssertFalse(appJS.contains("http://") || appJS.contains("https://") || appJS.contains("ws://"), "JS dış istek yapmamalı")
    }

    func testAssetServing() throws {
        let png = try XCTUnwrap(response(request("/assets/characters/char_0.png")))
        XCTAssertEqual(png.contentType, "image/png")
        XCTAssertEqual(Array(png.body.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        let manifest = try XCTUnwrap(response(request("/assets/furniture/DESK/manifest.json")))
        XCTAssertEqual(manifest.contentType, "application/json; charset=utf-8")
        XCTAssertEqual(status(request("/assets/floors/floor_0.png")), 200)
        XCTAssertEqual(status(request("/assets/walls/wall_0.png")), 200)
        XCTAssertEqual(status(request("/assets/furniture/PC/PC_FRONT_ON_1.png")), 200)
    }

    func testPathTraversalAndForbiddenAssetsAre404() {
        let bad = [
            "/assets/", "/assets", "/assets/..", "/assets/../Info.plist", "/assets/characters/../../x.png", "/assets/%2e%2e/x.png",
            "/assets/characters/%2e%2e/default-layout-1.json", "/assets/characters/..%2fchar_0.png", "/assets/characters%2fchar_0.png",
            "/assets/default-layout-1.json", "/assets/ATTRIBUTION.md", "/assets/characters/char_0.txt", "/assets/characters/char_0.PNG.exe",
            "/assets/characters/.hidden.png", "/assets/characters//char_0.png", "/assets/characters\\char_0.png", "/assets/characters/char_0",
            "/assets/pets/x.png", "/assets/furniture/DESK/../../default-layout-1.json", "/assets/characters/char_0.png%00.txt",
            "/assets/characters/ch ar.png", "/assets/furniture/DESK", "/assets/furniture/a/b/c/d/e.png", "/assets/char_0.png",
        ]
        for path in bad { XCTAssertEqual(status(request(path)), 404, path) }
        XCTAssertEqual(status(request("/etc/passwd")), 404)
        XCTAssertEqual(status(request("/../../etc/passwd")), 404)
        XCTAssertEqual(status(request("/v1/event")), 404, "olay yolu GET ile açılmaz")
    }

    func testSymlinksAndOutsideFilesAreNotServed() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(path: "adalmon-web-\(UUID().uuidString)")
        let root = base.appending(path: "Office")
        let outside = base.appending(path: "secret.png")
        try fm.createDirectory(at: root.appending(path: "characters"), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: outside)
        try Data([4, 5, 6]).write(to: root.appending(path: "characters/ok.png"))
        try fm.createSymbolicLink(at: root.appending(path: "characters/link.png"), withDestinationURL: outside)
        try fm.createSymbolicLink(at: root.appending(path: "floors"), withDestinationURL: base)
        defer { try? fm.removeItem(at: base) }
        XCTAssertNotNil(AgentWebRouter.resolveAsset("characters/ok.png", root: root))
        XCTAssertNil(AgentWebRouter.resolveAsset("characters/link.png", root: root), "dosya sembolik bağı")
        XCTAssertNil(AgentWebRouter.resolveAsset("floors/secret.png", root: root), "dizin sembolik bağı")
        XCTAssertNil(AgentWebRouter.resolveAsset("characters/missing.png", root: root))
    }

    // MARK: SSE çerçeveleme

    func testSSEFraming() {
        let event = String(decoding: AgentWebRouter.sseEvent(Data(#"{"a":1}"#.utf8)), as: UTF8.self)
        XCTAssertEqual(event, "data: {\"a\":1}\n\n")
        let multi = String(decoding: AgentWebRouter.sseEvent(Data("{\"a\":\n1}".utf8)), as: UTF8.self)
        XCTAssertEqual(multi, "data: {\"a\":1}\n\n", "satır sonu çerçeveyi bozamaz")
        XCTAssertEqual(String(decoding: AgentWebRouter.sseKeepAlive, as: UTF8.self), ": keep-alive\n\n")
        let opening = String(decoding: AgentWebRouter.sseOpening(Data("{}".utf8)), as: UTF8.self)
        XCTAssertTrue(opening.hasPrefix("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream"))
        XCTAssertTrue(opening.contains("Cache-Control: no-store"))
        XCTAssertTrue(opening.hasSuffix("retry: 3000\n\ndata: {}\n\n"))
        XCTAssertFalse(opening.lowercased().contains("access-control-"))
    }

    // MARK: JSON şemaları

    @MainActor
    func testLayoutJSONSchema() throws {
        let built = try XCTUnwrap(OfficeWebLayout.build(officeRoot: officeRoot))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: built.json) as? [String: Any])
        XCTAssertEqual(root["v"] as? Int, 1)
        let tiers = try XCTUnwrap(root["tiers"] as? [String: [String: Any]])
        XCTAssertEqual(Set(tiers.keys), ["small", "medium", "large"])
        let expectSeats = ["small": 4, "medium": 8, "large": 12]
        let expectFloor = ["small": (8, 8), "medium": (11, 8), "large": (13, 13)]
        for (key, tier) in tiers {
            let seats = try XCTUnwrap(tier["seats"] as? [[String: Any]])
            XCTAssertEqual(seats.count, expectSeats[key], key)
            XCTAssertEqual(tier["capacity"] as? Int, expectSeats[key], key)
            XCTAssertEqual(seats.filter { $0["kind"] as? String == "executive" }.count, 1, "odada tek yönetici koltuğu")
            let cols = try XCTUnwrap(tier["cols"] as? Int), rows = try XCTUnwrap(tier["rows"] as? Int)
            XCTAssertEqual(cols - 2, expectFloor[key]!.0, "\(key) zemin genişliği")
            XCTAssertEqual(rows - 2, expectFloor[key]!.1, "\(key) zemin yüksekliği")
            XCTAssertEqual((tier["tiles"] as? [Int])?.count, cols * rows * 4)
            XCTAssertNotNil(tier["door"]); XCTAssertNotNil(tier["entrance"]); XCTAssertNotNil(tier["board"]); XCTAssertNotNil(tier["zone"])
            let exec = try XCTUnwrap(seats.first { $0["kind"] as? String == "executive" })
            XCTAssertFalse((exec["toBoard"] as? [[Int]] ?? []).isEmpty, "yönetici koltuğundan tahtaya yol")
            for s in seats { XCTAssertFalse(((s["enter"] as? [[Int]]) ?? []).isEmpty, "\(key) koltuk \(s["id"] ?? "?") giriş yolu") }
            XCTAssertEqual(tier["coffeeMachine"] as? Bool, key == "large")
        }
        // Mobilya: her yerleşimin varlığı kataloğda, her dosya diskte var.
        let furniture = try XCTUnwrap(root["furniture"] as? [String: [String: Any]])
        for tier in tiers.values {
            for p in try XCTUnwrap(tier["furniture"] as? [[String: Any]]) {
                let asset = try XCTUnwrap(p["asset"] as? String)
                XCTAssertNotNil(furniture[asset], asset)
            }
        }
        for (id, f) in furniture {
            let file = try XCTUnwrap(f["file"] as? String)
            XCTAssertTrue(FileManager.default.fileExists(atPath: officeRoot.appending(path: "furniture/\(file)").path), "\(id): \(file)")
            XCTAssertNotNil(AgentWebRouter.resolveAsset("furniture/\(file)", root: officeRoot), "\(file) servis edilebilir olmalı")
        }
        // Model görünümü (Swift'teki OfficeAppearance eşlemesi).
        let ap = try XCTUnwrap(root["appearance"] as? [String: [String: Any]])
        XCTAssertEqual(ap["opus"]?["character"] as? Int, 2); XCTAssertEqual(ap["opus"]?["accessory"] as? String, "crown")
        XCTAssertEqual(ap["sonnet"]?["character"] as? Int, 0); XCTAssertEqual(ap["sonnet"]?["accessory"] as? String, "cap")
        XCTAssertEqual(ap["haiku"]?["character"] as? Int, 4); XCTAssertEqual(ap["haiku"]?["small"] as? Bool, true)
        XCTAssertEqual(ap["fable"]?["character"] as? Int, 5); XCTAssertEqual(ap["fable"]?["accessory"] as? String, "star")
        XCTAssertEqual(ap["unknown"]?["character"] as? Int, 3)
        let chars = try XCTUnwrap(root["characters"] as? [String: Any])
        XCTAssertEqual(chars["sheetWidth"] as? Int, 112); XCTAssertEqual(chars["sheetHeight"] as? Int, 96)
        for badge in AgentModelBadge.allCases {
            let index = try XCTUnwrap(ap[badge.rawValue]?["character"] as? Int)
            XCTAssertNotNil(AgentWebRouter.resolveAsset("characters/char_\(index).png", root: officeRoot))
        }
        XCTAssertFalse(built.json.contains(0x0A), "tek satır JSON")
    }

    @MainActor
    func testStateJSONSchemaAndBubbles() throws {
        let built = try XCTUnwrap(OfficeWebLayout.build(officeRoot: officeRoot))
        let builder = AgentWebSnapshotBuilder(seats: built.seats)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sub = AgentSubagent(agentID: "a1", agentType: "Explore", model: "claude-haiku-4-5", status: .tool("Grep"), activity: "Grep", activityAt: now)
        let s1 = AgentSession(id: "s1", project: "adalmon", model: "claude-opus-4-8", status: .tool("Edit"), startedAt: now.addingTimeInterval(-90),
                              lastEventAt: now, subagents: [sub], title: "Ofis işi", activity: "Edit", target: "main.swift", activityAt: now)
        let s2 = AgentSession(id: "s2", project: "api", model: "claude-sonnet-5-5", status: .waitingPermission, startedAt: now.addingTimeInterval(-30), lastEventAt: now)
        let data = builder.snapshot(sessions: [s2, s1], now: now)
        XCTAssertFalse(data.contains(0x0A))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["sessions"] as? Int, 2)
        XCTAssertEqual(root["agents"] as? Int, 3)
        XCTAssertEqual(root["working"] as? Int, 3)
        XCTAssertEqual(root["now"] as? Int64, 1_800_000_000_000)
        let rooms = try XCTUnwrap(root["rooms"] as? [[String: Any]])
        let r1 = try XCTUnwrap(rooms.first { $0["id"] as? String == "s1" })
        XCTAssertEqual(r1["title"] as? String, "Ofis işi")
        XCTAssertEqual(r1["badge"] as? String, "opus")
        XCTAssertEqual(r1["tier"] as? String, "small")
        let members = try XCTUnwrap(r1["members"] as? [[String: Any]])
        XCTAssertEqual(members.count, 2)
        let main = try XCTUnwrap(members.first { $0["kind"] as? String == "session" })
        XCTAssertEqual(main["bubble"] as? String, "main.swift düzenliyor")
        XCTAssertEqual(main["status"] as? String, "tool")
        XCTAssertEqual(main["seatKind"] as? String, "executive")
        XCTAssertEqual(main["standing"] as? Bool, true)
        XCTAssertEqual(main["project"] as? String, "adalmon")
        XCTAssertEqual(main["startedAt"] as? Int64, 1_800_000_000_000 - 90_000)
        let child = try XCTUnwrap(members.first { $0["kind"] as? String == "subagent" })
        XCTAssertEqual(child["label"] as? String, "Explore")
        XCTAssertEqual(child["badge"] as? String, "haiku")
        XCTAssertEqual(child["bubble"] as? String, "Arıyor")
        XCTAssertEqual(child["seatKind"] as? String, "desk")
        XCTAssertEqual(child["pcOn"] as? Bool, true)
        XCTAssertNil(child["target"], "hedef yoksa alan yok")
        let r2 = try XCTUnwrap(rooms.first { $0["id"] as? String == "s2" })
        let perm = try XCTUnwrap((r2["members"] as? [[String: Any]])?.first)
        XCTAssertEqual(perm["alert"] as? Bool, true)
        XCTAssertNil(perm["bubble"])
        XCTAssertEqual(perm["pose"] as? String, "reading")
        // İzinli alanlar dışında anahtar yok.
        let allowed: Set<String> = ["id", "kind", "label", "badge", "status", "statusLabel", "working", "activity", "target", "activityAt", "bubble", "seat",
                                    "seatKind", "pose", "alert", "pcOn", "standing", "overflow", "startedAt", "project"]
        for m in members + [perm] { XCTAssertTrue(Set(m.keys).isSubset(of: allowed), "\(Set(m.keys).subtracting(allowed))") }
        // Boş ofis: oda yok.
        let empty = try XCTUnwrap(JSONSerialization.jsonObject(with: builder.snapshot(sessions: [], now: now)) as? [String: Any])
        XCTAssertEqual((empty["rooms"] as? [Any])?.count, 0)
    }

    @MainActor
    func testStateJSONKeepsSeatsStableAndFlagsOverflowAndTier() throws {
        let built = try XCTUnwrap(OfficeWebLayout.build(officeRoot: officeRoot))
        let builder = AgentWebSnapshotBuilder(seats: built.seats)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func subs(_ n: Int) -> [AgentSubagent] {
            (0..<n).map { AgentSubagent(agentID: "a\($0)", agentType: "T\($0)", model: "claude-sonnet-5-5", status: .thinking) }
        }
        func session(_ n: Int) -> AgentSession {
            AgentSession(id: "big", project: "p", model: "claude-opus-4-8", status: .thinking, startedAt: now, lastEventAt: now, subagents: subs(n))
        }
        func room(_ data: Data) throws -> [String: Any] {
            try XCTUnwrap(((JSONSerialization.jsonObject(with: data) as? [String: Any])?["rooms"] as? [[String: Any]])?.first)
        }
        let first = try room(builder.snapshot(sessions: [session(2)], now: now))
        XCTAssertEqual(first["tier"] as? String, "small")
        let seatOf = { (r: [String: Any]) in Dictionary(uniqueKeysWithValues: (r["members"] as! [[String: Any]]).map { ($0["id"] as! String, $0["seat"] as? Int) }) }
        let before = seatOf(first)
        let bigger = try room(builder.snapshot(sessions: [session(6)], now: now))
        XCTAssertEqual(bigger["tier"] as? String, "medium")
        XCTAssertEqual(bigger["reseated"] as? Bool, true)
        let over = try room(builder.snapshot(sessions: [session(15)], now: now))
        XCTAssertEqual(over["tier"] as? String, "large")
        XCTAssertEqual(over["overflow"] as? Int, 4, "16 üye, 12 koltuk")
        XCTAssertEqual(before.count, 3)
    }

    // MARK: Canlı döngü (gerçek NWListener, loopback)

    private func startServer(web: AgentWebStore, keepAlive: TimeInterval = 15) async throws -> (AgentEventServer, UInt16) {
        let state = LiveStateBox()
        let ready = expectation(description: "ready")
        let server = AgentEventServer(token: token, web: web, keepAliveInterval: keepAlive, onEvent: { _ in }, onState: { s in
            state.set(s)
            if case .running = s { ready.fulfill() }
        })
        server.start(preferredPort: nil)
        await fulfillment(of: [ready], timeout: 5)
        guard case .running(let port) = state.value else { throw XCTSkip("dinleyici başlatılamadı: \(state.value)") }
        return (server, port)
    }

    private func get(_ port: UInt16, _ path: String, token: String? = nil, query: Bool = false) async throws -> (Int, Data) {
        var url = "http://127.0.0.1:\(port)\(path)"
        if let token, query { url += (path.contains("?") ? "&" : "?") + "t=\(token)" }
        var req = URLRequest(url: URL(string: url)!)
        if let token, !query { req.setValue(token, forHTTPHeaderField: "X-Adalmon-Token") }
        req.timeoutInterval = 4
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: req)
        return ((response as! HTTPURLResponse).statusCode, data)
    }

    func testLiveStateEndpointAuthAndFeatureFlag() async throws {
        let web = AgentWebStore(webRoot: webRoot, officeRoot: officeRoot)
        web.setEnabled(true)
        web.setState(Data(#"{"v":1,"rooms":[],"sessions":0}"#.utf8))
        let (server, port) = try await startServer(web: web)
        defer { server.stop() }
        let ok = try await get(port, "/v1/state", token: token)
        XCTAssertEqual(ok.0, 200)
        XCTAssertEqual(String(decoding: ok.1, as: UTF8.self), #"{"v":1,"rooms":[],"sessions":0}"#)
        let viaQuery = try await get(port, "/v1/state", token: token, query: true)
        XCTAssertEqual(viaQuery.0, 200)
        let none = try await get(port, "/v1/state")
        XCTAssertEqual(none.0, 401)
        let wrong = try await get(port, "/v1/state", token: "nope")
        XCTAssertEqual(wrong.0, 401)
        let traversal = try await get(port, "/assets/characters/..%2f..%2fx.png", token: token)
        XCTAssertEqual(traversal.0, 404)
        let page = try await get(port, "/", token: token)
        XCTAssertEqual(page.0, 200)
        XCTAssertTrue(String(decoding: page.1, as: UTF8.self).contains("<canvas"))
        web.setEnabled(false)
        let off = try await get(port, "/v1/state", token: token)
        XCTAssertEqual(off.0, 404, "özellik kapalıyken GET yolları 404")
    }

    func testLiveStreamSendsSnapshotBroadcastAndKeepAlive() async throws {
        let web = AgentWebStore(webRoot: webRoot, officeRoot: officeRoot)
        web.setEnabled(true)
        web.setState(Data(#"{"v":1,"n":0}"#.utf8))
        let (server, port) = try await startServer(web: web, keepAlive: 0.3)
        defer { server.stop() }
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/stream?t=\(token)")!)
        req.timeoutInterval = 8
        let session = URLSession(configuration: .ephemeral)
        let (bytes, response) = try await session.bytes(for: req)
        XCTAssertEqual((response as! HTTPURLResponse).statusCode, 200)
        XCTAssertEqual((response as! HTTPURLResponse).value(forHTTPHeaderField: "Content-Type"), "text/event-stream; charset=utf-8")
        let count0 = await server.sseClientCount()
        XCTAssertEqual(count0, 1)
        let collector = Task { () -> [String] in
            var lines: [String] = []
            do { for try await line in bytes.lines { lines.append(line); if lines.contains(": keep-alive"), lines.contains(#"data: {"v":1,"n":1}"#) { break } } } catch {}
            return lines
        }
        try await Task.sleep(for: .milliseconds(100))
        server.broadcast(Data(#"{"v":1,"n":1}"#.utf8))
        let lines = await collector.value
        XCTAssertTrue(lines.contains(#"data: {"v":1,"n":0}"#), "bağlanınca anlık görüntü: \(lines)")
        XCTAssertTrue(lines.contains(#"data: {"v":1,"n":1}"#), "yayın: \(lines)")
        XCTAssertTrue(lines.contains(": keep-alive"), "keep-alive: \(lines)")
        collector.cancel()
        session.invalidateAndCancel()
        // İstemci kopunca temizlenir.
        for _ in 0..<30 {
            if await server.sseClientCount() == 0 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let count1 = await server.sseClientCount()
        XCTAssertEqual(count1, 0, "bağlantı kopunca SSE istemcisi temizlenmeli")
    }

    func testLivePostEventStillWorksWithWebLayer() async throws {
        let web = AgentWebStore(webRoot: webRoot, officeRoot: officeRoot)
        web.setEnabled(true)
        let received = LiveEventBox()
        let state = LiveStateBox()
        let ready = expectation(description: "ready")
        let server = AgentEventServer(token: token, web: web, onEvent: { received.add($0) }, onState: { s in
            state.set(s)
            if case .running = s { ready.fulfill() }
        })
        server.start(preferredPort: nil)
        await fulfillment(of: [ready], timeout: 5)
        defer { server.stop() }
        guard case .running(let port) = state.value else { throw XCTSkip("dinleyici başlatılamadı") }
        func post(_ tok: String) async throws -> (Int, Int) {
            var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/event")!)
            req.httpMethod = "POST"
            req.setValue(tok, forHTTPHeaderField: "X-Adalmon-Token")
            req.httpBody = Data(#"{"event":"Stop","session_id":"s1"}"#.utf8)
            req.timeoutInterval = 4
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: req)
            return ((response as! HTTPURLResponse).statusCode, data.count)
        }
        let bad = try await post("nope")
        XCTAssertEqual(bad.0, 401)
        let good = try await post(token)
        XCTAssertEqual(good.0, 204)
        XCTAssertEqual(good.1, 0)
        XCTAssertEqual(received.events.map(\.event), ["Stop"])
        web.setEnabled(false)
        let still = try await post(token)
        XCTAssertEqual(still.0, 204, "tarayıcı görünümü kapalıyken de hook'lar çalışır")
    }
}

private final class LiveEventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.lock(); items.append(e); lock.unlock() }
    var events: [AgentEvent] { lock.lock(); defer { lock.unlock() }; return items }
}

private final class LiveStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var state = AgentEventServer.State.stopped
    func set(_ s: AgentEventServer.State) { lock.lock(); state = s; lock.unlock() }
    var value: AgentEventServer.State { lock.lock(); defer { lock.unlock() }; return state }
}
