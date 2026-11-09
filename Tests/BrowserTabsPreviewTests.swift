import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

private final class PreviewSafari: SafariTabsSource, @unchecked Sendable {
    func permission(ask: Bool) async -> SafariAutomationPermission { .granted }
    func fetchTabs() async throws -> [SafariTab] {
        [SafariTab(window: 1, index: 1, title: "YouTube", url: "https://www.youtube.com/"),
         SafariTab(window: 1, index: 2, title: "Model - Antidepresan Gülümsemesi Konser Kaydı // Fatma Turgut'un Duygulandığı Konser - YouTube", url: "https://www.youtube.com/watch?v=1"),
         SafariTab(window: 1, index: 3, title: "Tufan'ın 100 Liralık Masajla İmtihanı | Var Bunlar - YouTube", url: "https://www.youtube.com/watch?v=2"),
         SafariTab(window: 1, index: 4, title: "X", url: "https://x.com/home"),
         SafariTab(window: 2, index: 1, title: "GitHub", url: "https://github.com/aykyusuf/adalmon")]
    }
}

/// Tarayıcılar sayfasını sahte veriyle çizip PNG yazar (ADALMON_PREVIEW_DIR verilirse).
@MainActor
final class BrowserTabsPreviewTests: XCTestCase {
    func testRenderBrowsersPage() async throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else { throw XCTSkip("ADALMON_PREVIEW_DIR yok") }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "adalmon.preview.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: BrowserTabsModel.safariEnabledKey)
        let mb: UInt64 = 1_048_576
        let model = BrowserTabsModel(defaults: defaults, safari: PreviewSafari(), safariPIDs: { [1] },
                                     webContentScan: { _ in [WebContentProcess(pid: 5720, footprint: 897 * mb), WebContentProcess(pid: 10708, footprint: 383 * mb),
                                                             WebContentProcess(pid: 10692, footprint: 357 * mb), WebContentProcess(pid: 5768, footprint: 271 * mb),
                                                             WebContentProcess(pid: 9691, footprint: 177 * mb), WebContentProcess(pid: 7768, footprint: 18 * mb)] },
                                     useNetwork: false)
        await model.refreshSafari(ask: false)
        let app = AppModel()
        try await render(BrowserTabsView(model: app, browser: model).padding(24).background(Color(white: 0.13)), name: "browsers-safari", dir: dir, size: NSSize(width: 1100, height: 700))
    }

    private func render<V: View>(_ view: V, name: String, dir: URL, size: NSSize) async throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -3000, y: -3000), size: size),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(1.5))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appending(path: "\(name).png"))
        window.close()
    }
}
