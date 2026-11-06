import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// "Ağ kullanımı" sayfasını gerçek (araç çubuklu, NSHostingController'lı) bir pencerede, ayrıntı paneli açıkken çizip PNG yazar.
/// Yalnızca ADALMON_PREVIEW_DIR (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class MainWindowInspectorPreviewTests: XCTestCase {
    func testRenderNetworkWithInspector() async throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, size) in [("network-inspector-1000x680", NSSize(width: 1000, height: 680)),
                             ("network-inspector-min", NSSize(width: 900, height: 600))] {
            try await render(name: name, size: size, dir: dir)
        }
    }

    /// Mobil veri sayfasının tamamı (altındaki ayar kartlarıyla), yüksek bir pencerede.
    func testRenderMobilePageWithSettings() async throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel()
        let size = NSSize(width: 1000, height: 2000)
        let host = NSHostingView(rootView: MobileDataPage(data: .sample, actions: .inert, model: model).frame(width: 780, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -3000, y: -3000), size: size),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(1))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appending(path: "mobile-page-full.png"))
        window.close()
    }

    private func render(name: String, size: NSSize, dir: URL) async throws {
        let model = AppModel()
        let router = SettingsRouter(isDockModeOn: { true })
        router.selectedMainSection = .network
        router.selectedAppID = PanelData.sample.today[0].app
        let view = MainWindowView(model: model, source: .fixed(.sample), actions: .inert, router: router) { settings in
            SettingsDetailView(section: settings, model: model)
        }
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.minSize]
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 40, y: 60), size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Adalmon"
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 940, height: 600)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        window.setContentSize(size)
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .seconds(2))
        try capture(window, to: dir.appending(path: "\(name).png"))
        if name.hasSuffix("1000x680") {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0,
                                                        windowNumber: window.windowNumber, context: nil, characters: "i",
                                                        charactersIgnoringModifiers: "i", isARepeat: false, keyCode: 34))
            let handled = window.performKeyEquivalent(with: event)
            print("MAINWINDOW_PREVIEW: toggle handled=\(handled)")
            try await Task.sleep(for: .seconds(1))
            try capture(window, to: dir.appending(path: "\(name)-toggled.png"))
        }
        print("MAINWINDOW_PREVIEW: window=\(window.frame.size) content=\(window.contentLayoutRect.size)")
        window.close()
    }

    private func capture(_ window: NSWindow, to url: URL) throws {
        let frameView = try XCTUnwrap(window.contentView?.superview)
        frameView.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("MAINWINDOW_PREVIEW: \(url.path())")
    }
}
