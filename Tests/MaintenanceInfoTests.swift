import XCTest
@testable import Adalmon

/// Bakım bilgisi: yalnızca veri + kopyalanabilir komut. Çalıştırıcı bağımlılığı olmadığı kaynak taramasıyla da doğrulanır.
final class MaintenanceInfoTests: XCTestCase {
    private var allCommands: [MaintenanceCommand] { MaintenanceInfo.topics.flatMap(\.commands) }

    func testRequiredCommandsArePresentVerbatim() {
        let texts = Set(allCommands.map(\.text))
        XCTAssertTrue(texts.contains("tmutil listlocalsnapshots /"))
        XCTAssertTrue(texts.contains("sudo tmutil thinlocalsnapshots / 999999999999 4"))
        XCTAssertTrue(texts.contains("sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"))
        XCTAssertTrue(texts.contains("sudo mdutil -E /"))
        XCTAssertTrue(texts.contains("sudo purge"))
    }

    func testNeedsAdminMatchesSudoPrefixAndIdsAreUnique() {
        for command in allCommands {
            XCTAssertEqual(command.needsAdmin, command.text.hasPrefix("sudo "), command.text)
            XCTAssertFalse(command.text.isEmpty)
        }
        XCTAssertEqual(Set(allCommands.map(\.id)).count, allCommands.count)
        XCTAssertEqual(Set(MaintenanceInfo.topics.map(\.id)).count, MaintenanceInfo.topics.count)
        XCTAssertEqual(MaintenanceInfo.adminCommands.count, allCommands.filter(\.needsAdmin).count)
        XCTAssertFalse(MaintenanceInfo.adminCommands.isEmpty)
    }

    func testExplanationsCarryTheKeyWarnings() throws {
        let purge = try XCTUnwrap(MaintenanceInfo.topics.first { $0.id == "purge" })
        XCTAssertTrue(purge.summary.contains("diski boşaltmaz"))
        XCTAssertTrue(purge.summary.contains("gereksiz"))
        let spotlight = try XCTUnwrap(MaintenanceInfo.topics.first { $0.id == "spotlight-reindex" })
        XCTAssertNotNil(spotlight.warning)
        XCTAssertTrue(spotlight.warning?.contains("Pil") == true)
        XCTAssertTrue(MaintenanceInfo.terminalNote.contains("yönetici parolası ister"))
        XCTAssertNotNil(MaintenanceInfo.topics.first { $0.id == "periodic" })
    }

    /// Maintenance klasöründe komut çalıştıran hiçbir kod olmamalı; `sudo` yalnızca string literallerde geçmeli.
    func testMaintenanceSourcesNeverExecuteAnything() throws {
        let dir = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/App/Cleanup/Maintenance", directoryHint: .isDirectory)
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "swift" }
        try XCTSkipIf(files.isEmpty, "kaynak klasörü bu ortamda yok")
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for forbidden in ["CommandRunner", "Process()", "NSTask", "posix_spawn", "system(", "launchctl", "NSAppleScript"] {
                XCTAssertFalse(source.contains(forbidden), "\(file.lastPathComponent) içinde \(forbidden)")
            }
            for line in source.split(separator: "\n") where line.contains("sudo") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                XCTAssertTrue(trimmed.hasPrefix("//") || trimmed.hasPrefix("///") || line.filter { $0 == "\"" }.count >= 2,
                              "sudo string literal dışında: \(trimmed)")
            }
        }
    }
}
