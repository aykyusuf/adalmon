import Network
import XCTest
@testable import Adalmon

final class AgentHTTPParserTests: XCTestCase {
    private let token = "tok-123"
    private let body = #"{"event":"Stop","session_id":"s1"}"#

    private func request(method: String = "POST", path: String = "/v1/event", token: String? = "tok-123", length: String? = nil,
                         extra: [String] = [], body: String? = nil) -> Data {
        let payload = body ?? self.body
        var lines = ["\(method) \(path) HTTP/1.1", "Host: 127.0.0.1"]
        if let token { lines.append("X-Adalmon-Token: \(token)") }
        if let length { lines.append("Content-Length: \(length)") } else if length == nil { lines.append("Content-Length: \(payload.utf8.count)") }
        lines += extra
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n" + payload).utf8)
    }

    func testValidRequestYieldsEventAnd204() {
        let outcome = AgentHTTPParser.parse(request(), token: token)
        guard case .event(let event) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(event.event, "Stop")
        let response = String(decoding: AgentHTTPParser.response(for: outcome), as: UTF8.self)
        XCTAssertTrue(response.hasPrefix("HTTP/1.1 204 No Content\r\n"))
        XCTAssertTrue(response.hasSuffix("Content-Length: 0\r\nConnection: close\r\n\r\n"), "gövde boş olmalı")
    }

    func testHeaderNamesAreCaseInsensitive() {
        var data = Data("POST /v1/event HTTP/1.1\r\nx-adalmon-token: tok-123\r\ncontent-length: \(body.utf8.count)\r\n\r\n".utf8)
        data.append(Data(body.utf8))
        XCTAssertEqual(AgentHTTPParser.parse(data, token: token), .event(AgentEvent(event: "Stop", sessionID: "s1")))
    }

    func testRejectsWrongMethodAndPath() {
        XCTAssertEqual(AgentHTTPParser.parse(request(method: "GET"), token: token), .reject(405))
        XCTAssertEqual(AgentHTTPParser.parse(request(method: "PUT"), token: token), .reject(405))
        XCTAssertEqual(AgentHTTPParser.parse(request(path: "/"), token: token), .reject(404))
        XCTAssertEqual(AgentHTTPParser.parse(request(path: "/v1/event?x=1"), token: token), .reject(404))
        XCTAssertEqual(AgentHTTPParser.parse(request(path: "/v1/events"), token: token), .reject(404))
    }

    func testTokenChecks() {
        XCTAssertEqual(AgentHTTPParser.parse(request(token: nil), token: token), .reject(401))
        XCTAssertEqual(AgentHTTPParser.parse(request(token: "wrong"), token: token), .reject(401))
        XCTAssertEqual(AgentHTTPParser.parse(request(token: "tok-12"), token: token), .reject(401), "önek yetmez")
        XCTAssertEqual(AgentHTTPParser.parse(request(token: ""), token: ""), .reject(401), "boş token asla kabul edilmez")
        XCTAssertTrue(AgentHTTPParser.constantTimeEqual("abc", "abc"))
        XCTAssertFalse(AgentHTTPParser.constantTimeEqual("abc", "abd"))
    }

    func testContentLengthRules() {
        let noLength = Data("POST /v1/event HTTP/1.1\r\nX-Adalmon-Token: tok-123\r\n\r\n\(body)".utf8)
        XCTAssertEqual(AgentHTTPParser.parse(noLength, token: token), .reject(411))
        XCTAssertEqual(AgentHTTPParser.parse(request(length: "abc"), token: token), .reject(400))
        XCTAssertEqual(AgentHTTPParser.parse(request(length: "-5"), token: token), .reject(400))
        XCTAssertEqual(AgentHTTPParser.parse(request(extra: ["Content-Length: 3"]), token: token), .reject(400), "çift Content-Length")
        XCTAssertEqual(AgentHTTPParser.parse(request(extra: ["Transfer-Encoding: chunked"]), token: token), .reject(400))
    }

    func testBodySizeLimitRejectsBeforeBodyArrives() {
        // Gövde hiç gelmeden bildirilen uzunluk yüzünden reddedilir.
        let head = request(length: "\(AgentHTTPParser.maxBody + 1)", body: "")
        XCTAssertEqual(AgentHTTPParser.parse(head, token: token), .reject(413))
        let padded = #"{"event":"Stop","session_id":"s1","pad":""# + String(repeating: "a", count: AgentHTTPParser.maxBody) + #""}"#
        XCTAssertEqual(AgentHTTPParser.parse(request(body: padded), token: token), .reject(413))
    }

    func testIncompleteRequestsNeedMore() {
        let whole = request()
        XCTAssertEqual(AgentHTTPParser.parse(whole.prefix(20), token: token), .needMore)
        XCTAssertEqual(AgentHTTPParser.parse(whole.dropLast(5), token: token), .needMore)
        XCTAssertEqual(AgentHTTPParser.parse(Data(), token: token), .needMore)
    }

    func testBadJSONAndOversizedHeaders() {
        XCTAssertEqual(AgentHTTPParser.parse(request(body: "not json"), token: token), .reject(400))
        XCTAssertEqual(AgentHTTPParser.parse(request(body: #"{"event":"Stop"}"#), token: token), .reject(400), "session_id şart")
        XCTAssertEqual(AgentHTTPParser.parse(request(body: "[]"), token: token), .reject(400))
        XCTAssertEqual(AgentHTTPParser.parse(Data(String(repeating: "A", count: AgentHTTPParser.maxHeader + 10).utf8), token: token), .reject(431))
        XCTAssertEqual(AgentHTTPParser.parse(Data("GARBAGE\r\n\r\n".utf8), token: token), .reject(400))
        XCTAssertEqual(AgentHTTPParser.parse(Data("POST /v1/event HTTP/1.1\r\nbroken header\r\n\r\n".utf8), token: token), .reject(400))
    }

    func testErrorResponsesHaveEmptyBody() {
        for code in [400, 401, 404, 405, 411, 413, 431] {
            let text = String(decoding: AgentHTTPParser.response(for: .reject(code)), as: UTF8.self)
            XCTAssertTrue(text.hasPrefix("HTTP/1.1 \(code) "), text)
            XCTAssertTrue(text.hasSuffix("\r\n\r\n"), text)
            XCTAssertTrue(text.contains("Content-Length: 0"))
        }
    }

    /// Gerçek 127.0.0.1 dinleyicisi: yetkili POST 204 ve olay; yanlış token 401 ve olay yok.
    func testLiveServerRoundTrip() async throws {
        let received = EventBox()
        let state = StateBox()
        let ready = expectation(description: "listener ready")
        ready.assertForOverFulfill = false
        let server = AgentEventServer(token: token, onEvent: { received.add($0) }, onState: { s in
            state.set(s)
            if case .running = s { ready.fulfill() }
        })
        server.start(preferredPort: nil)
        await fulfillment(of: [ready], timeout: 5)
        defer { server.stop() }
        guard case .running(let port) = state.value else { throw XCTSkip("dinleyici başlatılamadı: \(state.value)") }

        func post(token: String) async throws -> Int {
            var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/event")!)
            req.httpMethod = "POST"
            req.setValue(token, forHTTPHeaderField: "X-Adalmon-Token")
            req.httpBody = Data(body.utf8)
            req.timeoutInterval = 4
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: req)
            XCTAssertTrue(data.isEmpty)
            return (response as! HTTPURLResponse).statusCode
        }
        let bad = try await post(token: "nope")
        XCTAssertEqual(bad, 401)
        XCTAssertTrue(received.events.isEmpty)
        let good = try await post(token: token)
        XCTAssertEqual(good, 204)
        XCTAssertEqual(received.events.map(\.event), ["Stop"])
    }
}

private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AgentEvent] = []
    func add(_ e: AgentEvent) { lock.lock(); items.append(e); lock.unlock() }
    var events: [AgentEvent] { lock.lock(); defer { lock.unlock() }; return items }
}

private final class StateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var state = AgentEventServer.State.stopped
    func set(_ s: AgentEventServer.State) { lock.lock(); state = s; lock.unlock() }
    var value: AgentEventServer.State { lock.lock(); defer { lock.unlock() }; return state }
}
