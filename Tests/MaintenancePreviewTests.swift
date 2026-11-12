import SwiftUI
import XCTest
@testable import Adalmon

/// Temizlik > Bakım ekranı açık/koyu PNG olarak.
@MainActor
final class MaintenancePreviewTests: XCTestCase {
    func testRenderMaintenance() throws {
        let dir = try RD3PreviewRender.previewDir()
        for dark in [false, true] {
            try RD3PreviewRender.render(MaintenanceSection(), prefix: "maintenance", name: "1-top", dark: dark, dir: dir, height: 900)
            try RD3PreviewRender.render(MaintenanceSection(), prefix: "maintenance", name: "2-narrow", dark: dark, dir: dir, width: 560, height: 900)
            try RD3PreviewRender.render(MaintenanceCommandBlock(command: MaintenanceInfo.topics[1].commands[0], accent: .maintenance),
                                        prefix: "maintenance", name: "3-command", dark: dark, dir: dir, width: 560, height: 200, spin: 0.3)
        }
    }

    func testRiskMappingCoversEveryTopic() {
        for topic in MaintenanceInfo.topics {
            let risk = MaintenanceRisk(topic: topic)
            XCTAssertFalse(risk.title.isEmpty)
            if topic.id == "dns-flush" { XCTAssertEqual(risk, .safe) }
            if topic.id == "purge" { XCTAssertEqual(risk, .discouraged) }
        }
    }
}
