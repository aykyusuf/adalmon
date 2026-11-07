import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Yeni sekme çubuğu ve Başlangıç sekmesi önizlemeleri (koyu tema). Yalnızca ADALMON_PREVIEW_DIR verilince çalışır.
@MainActor
final class ProcessesTabsPreviewTests: XCTestCase {
    private func render(_ size: NSSize, tab: ProcessesTab, name: String, wait: Double) async throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel()
        MainWindowHarness.seedSystemHistory(into: model)
        try await MainWindowHarness.feedSnapshots(into: model, count: 6)
        let h = MainWindowHarness(size: size, section: .processes, model: model)
        h.router.processesTab = tab
        h.show()
        if h.window.frame.size != size {
            h.window.setFrame(NSRect(origin: NSPoint(x: 0, y: -200), size: size), display: true)
        }
        try await Task.sleep(for: .seconds(wait))
        let url = dir.appending(path: name)
        if try !h.screenshot(to: url) { try h.capture(to: url) }
        print("TABS_PREVIEW \(url.path)")
        h.close()
    }

    func testTabsWide() async throws { try await render(NSSize(width: 1400, height: 900), tab: .processes, name: "tabs-processes-1400.png", wait: 4) }
    func testTabsMinimum() async throws { try await render(NSSize(width: 940, height: 600), tab: .performance, name: "tabs-performance-940.png", wait: 4) }
    func testIconsOnlyFallback() async throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else { throw XCTSkip("ADALMON_PREVIEW_DIR yok") }
        struct Host: View {
            @State var tab: ProcessesTab = .history
            var body: some View {
                VStack(spacing: 24) {
                    ProcessesTabBar(selection: $tab).frame(width: 620)
                    ProcessesTabBar(selection: $tab).frame(width: 300)
                }.padding(24).background(Color(nsColor: .windowBackgroundColor))
            }
        }
        let host = NSHostingView(rootView: Host().frame(width: 700, height: 200).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        try await Task.sleep(for: .seconds(1))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(filePath: env).appending(path: "tabs-fallback.png"))
        window.close()
    }

    func testStartup() async throws { try await render(NSSize(width: 1400, height: 900), tab: .startup, name: "tabs-startup-1400.png", wait: 14) }
    func testStartupMinimum() async throws { try await render(NSSize(width: 940, height: 600), tab: .startup, name: "tabs-startup-940.png", wait: 14) }
}
