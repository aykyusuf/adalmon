import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// İşlemler (geniş + en küçük pencere) ve Performans (imleç ipucuyla) önizlemeleri. Yalnızca ADALMON_PREVIEW_DIR verilince çalışır.
@MainActor
final class ProcessesInteractionPreviewTests: XCTestCase {
    private func previewDir() throws -> URL {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func render(_ size: NSSize, tab: ProcessesTab, name: String, hover: Double? = nil, wait: Double = 5) async throws {
        let dir = try previewDir()
        let model = AppModel()
        MainWindowHarness.seedSystemHistory(into: model)
        try await MainWindowHarness.feedSnapshots(into: model)
        await MainWindowHarness.seedResourceHistory(into: model.store)
        let h = MainWindowHarness(size: size, section: .processes, model: model, chartHover: hover)
        h.router.processesTab = tab
        h.show()
        // Pencere ekrandan büyükse show() sığdırır; çerçeveyi programatik olarak istenen boyuta getir.
        if h.window.frame.size != size {
            h.window.setFrame(NSRect(origin: NSPoint(x: 0, y: -200), size: size), display: true)
        }
        try await Task.sleep(for: .seconds(wait))
        let url = dir.appending(path: name)
        print("PREVIEW \(name) window=\(h.window.frame.size) content=\(h.contentBounds.size)")
        try h.capture(to: url)
        h.close()
    }

    func testProcessesWide() async throws { try await render(NSSize(width: 2400, height: 1400), tab: .processes, name: "f5-processes-2400x1400.png") }
    func testProcessesMinimum() async throws { try await render(NSSize(width: 940, height: 600), tab: .processes, name: "f5-processes-940x600.png") }
    func testPerformanceHover() async throws {
        try await render(NSSize(width: 1400, height: 900), tab: .performance, name: "f5-performance-1400x900.png", hover: 0.62, wait: 4)
    }
}
