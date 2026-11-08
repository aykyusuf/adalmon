import XCTest
@testable import Adalmon

/// Konuşma balonu metni (saf mantık): araç → Türkçe fiil, hedef var/yok, bilinmeyen araç, kısaltma, süre.
final class OfficeBubbleTextTests: XCTestCase {
    private func text(_ tool: String, target: String? = nil) -> String? {
        OfficeBubbleText.text(status: .tool(tool), activity: tool, target: target)
    }

    func testToolToVerbMappingWithoutTarget() {
        XCTAssertEqual(text("Bash"), "Komut çalıştırıyor")
        for tool in ["Edit", "Write", "MultiEdit", "NotebookEdit"] { XCTAssertEqual(text(tool), "Dosya düzenliyor", tool) }
        XCTAssertEqual(text("Read"), "Dosya okuyor")
        XCTAssertEqual(text("Grep"), "Arıyor")
        XCTAssertEqual(text("Glob"), "Arıyor")
        XCTAssertEqual(text("WebSearch"), "Web'de geziniyor")
        XCTAssertEqual(text("WebFetch"), "Web'de geziniyor")
        XCTAssertEqual(text("Task"), "Ajan çağırıyor")
        XCTAssertEqual(text("Agent"), "Ajan çağırıyor")
        XCTAssertEqual(OfficeBubbleText.text(status: .thinking, activity: nil, target: nil), "Düşünüyor…")
    }

    func testNoBubbleWhenNotWorking() {
        for status in [AgentStatus.idle, .done, .ended, .waitingPermission] {
            XCTAssertNil(OfficeBubbleText.text(status: status, activity: "Edit", target: "a.swift"), "\(status)")
        }
    }

    func testTargetVariants() {
        XCTAssertEqual(text("Edit", target: "main.swift"), "main.swift düzenliyor")
        XCTAssertEqual(text("Write", target: "a.md"), "a.md düzenliyor")
        XCTAssertEqual(text("Read", target: "Package.swift"), "Package.swift okuyor")
        XCTAssertEqual(text("Bash", target: "swift"), "swift çalıştırıyor")
        XCTAssertEqual(text("Edit", target: "  "), "Dosya düzenliyor", "boş hedef varsayılana düşer")
        // Hedefi olmaması gereken araçlar hedef gelse bile söylemez.
        XCTAssertEqual(text("Grep", target: "SECRET"), "Arıyor")
        XCTAssertEqual(text("WebFetch", target: "x.test"), "Web'de geziniyor")
        XCTAssertEqual(text("Task", target: "x"), "Ajan çağırıyor")
        // Araç adı etkinlikte yoksa durumdan gelir.
        XCTAssertEqual(OfficeBubbleText.text(status: .tool("Read"), activity: nil, target: "x.txt"), "x.txt okuyor")
    }

    func testUnknownToolAndLongNamesAreShortened() {
        XCTAssertEqual(text("TodoWrite"), "TodoWrite kullanıyor")
        XCTAssertEqual(text("mcp__github__create_issue"), "create_issue kullanıyor", "MCP adının son bileşeni")
        XCTAssertEqual(OfficeBubbleText.sanitizedToolName("Çok Garip!Araç*"), "ok" + "GaripAra", "yalnızca güvenli karakterler")
        XCTAssertNil(OfficeBubbleText.sanitizedToolName("***"))
        XCTAssertEqual(text("***"), "Araç kullanıyor")
        XCTAssertEqual(OfficeBubbleText.sanitizedToolName(String(repeating: "x", count: 40))?.count, OfficeBubbleText.maxToolName)
        for name in ["VeryLongUnknownToolName_v2", String(repeating: "x", count: 60), "mcp__server__a_very_long_tool_name_here"] {
            let shown = try? XCTUnwrap(text(name))
            XCTAssertLessThanOrEqual(shown?.count ?? 99, OfficeBubbleText.maxLength, name)
            XCTAssertTrue(shown?.hasSuffix(" kullanıyor") ?? false, "fiil her zaman tam kalır: \(shown ?? "")")
            XCTAssertFalse(shown?.contains("\n") ?? true)
        }
        let longTarget = String(repeating: "a", count: 40) + ".swift"
        let shown = try? XCTUnwrap(text("Edit", target: longTarget))
        XCTAssertLessThanOrEqual(shown?.count ?? 99, OfficeBubbleText.maxLength)
        XCTAssertTrue(shown?.hasSuffix("… düzenliyor") ?? false, "uzun hedef … ile kısalır, fiil tam: \(shown ?? "")")
        let shownBash = try? XCTUnwrap(text("Bash", target: "abcdefghijklmnopqrstuvwx"))
        XCTAssertLessThanOrEqual(shownBash?.count ?? 99, OfficeBubbleText.maxLength)
        XCTAssertTrue(shownBash?.hasSuffix(" çalıştırıyor") ?? false, shownBash ?? "")
    }

    func testExpiryAfterTenSeconds() {
        let t0 = Date(timeIntervalSince1970: 5_000_000)
        XCTAssertFalse(OfficeBubbleText.isExpired(activityAt: t0, now: t0))
        XCTAssertFalse(OfficeBubbleText.isExpired(activityAt: t0, now: t0.addingTimeInterval(9.9)))
        XCTAssertTrue(OfficeBubbleText.isExpired(activityAt: t0, now: t0.addingTimeInterval(10)))
        XCTAssertTrue(OfficeBubbleText.isExpired(activityAt: t0, now: t0.addingTimeInterval(60)))
        XCTAssertFalse(OfficeBubbleText.isExpired(activityAt: nil, now: t0.addingTimeInterval(1_000)), "zamansız (demo) balon sönmez")
        XCTAssertEqual(OfficeBubbleText.remaining(activityAt: t0, now: t0.addingTimeInterval(3)) ?? -1, 7, accuracy: 0.001)
        XCTAssertEqual(OfficeBubbleText.remaining(activityAt: t0, now: t0.addingTimeInterval(30)), 0)
        XCTAssertNil(OfficeBubbleText.remaining(activityAt: nil, now: t0))
        // Yeni olay süreyi sıfırlar: aynı metin, yeni zaman.
        XCTAssertFalse(OfficeBubbleText.isExpired(activityAt: t0.addingTimeInterval(8), now: t0.addingTimeInterval(15)))
    }

    func testMembersCarryActivityForBubbles() {
        let now = Date()
        let s = AgentSession(id: "s", project: "p", model: "claude-opus-4-8", status: .tool("Edit"), startedAt: now, lastEventAt: now,
                             subagents: [AgentSubagent(agentID: "a", agentType: "x", model: nil, status: .tool("Bash"), activity: "Bash", target: "ls", activityAt: now)],
                             activity: "Edit", target: "main.swift", activityAt: now)
        let members = OfficeMember.members(from: [s])
        XCTAssertEqual(members[0].activity, "Edit"); XCTAssertEqual(members[0].target, "main.swift"); XCTAssertEqual(members[0].activityAt, now)
        XCTAssertEqual(members[1].activity, "Bash"); XCTAssertEqual(members[1].target, "ls")
    }
}
