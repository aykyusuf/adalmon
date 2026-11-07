import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Süreçler sayfasının sekmelerini gerçek ana pencerede (kenar çubuğu + başlık dahil) koyu temada çizip PNG yazar.
/// Yalnızca ADALMON_PREVIEW_DIR (TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class ProcessesTaskManagerPreviewTests: XCTestCase {
    func testRenderTabs() async throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tabs: [(ProcessesTab, String)] = [(.processes, "processes"), (.performance, "performance"), (.history, "history"),
                                              (.startup, "startup"), (.disk, "disk")]
        for (size, suffix) in [(NSSize(width: 1400, height: 900), "1400x900"), (NSSize(width: 940, height: 600), "940x600")] {
            for (tab, name) in tabs {
                if suffix == "940x600", tab == .startup || tab == .disk { continue }
                let model = AppModel()
                try await MainWindowHarness.feedSnapshots(into: model)
                await MainWindowHarness.seedResourceHistory(into: model.store)
                let h = MainWindowHarness(size: size, section: .processes, model: model)
                h.router.processesTab = tab
                h.show()
                try await Task.sleep(for: .seconds(tab.needsLiveSampling ? 5 : 3))
                let url = dir.appending(path: "tm-\(name)-\(suffix).png")
                if try !h.screenshot(to: url) { try h.capture(to: url) }
                h.close()
            }
        }
    }
}
