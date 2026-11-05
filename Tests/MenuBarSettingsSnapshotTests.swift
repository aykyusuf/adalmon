import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Opt-in PNGs of the simple "Menü çubuğu" settings page, drawn through an offscreen NSHostingView
/// (ImageRenderer does not draw AppKit-backed controls). Run with TEST_RUNNER_ADALMON_PREVIEW_DIR=<dir>.
final class MenuBarSettingsSnapshotTests: XCTestCase {
    @MainActor
    func testExportSimpleSettingsPage() throws {
        guard let path = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"] else { return }
        let dir = URL(filePath: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "MenuBarSettingsSnapshotTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MenuBarConfigStore(defaults: defaults)
        var cards = MetricCardConfig.defaults
        cards[1].showGraph = true
        cards[1].thresholdColor = true
        cards[4].shown = true
        store.apply(cards: cards)

        for dark in [true, false] {
            let page = MenuBarCardsForm(store: store, values: .sample, cards: .constant(cards), isSimple: true, onOpenAdvanced: {})
            try Self.snapshot(page, dark: dark, size: NSSize(width: 760, height: 1500),
                              to: dir.appending(path: "settings-cards-\(dark ? "dark" : "light").png"))
        }
        let advanced = MenuBarCardsForm(store: store, values: .sample, cards: .constant(cards), isSimple: false, onOpenAdvanced: {})
        try Self.snapshot(advanced, dark: true, size: NSSize(width: 760, height: 520),
                          to: dir.appending(path: "settings-cards-advanced-notice.png"))
    }

    @MainActor
    private static func snapshot(_ view: some View, dark: Bool, size: NSSize, to url: URL) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
        window.contentView = nil
        print("MENUBAR_PREVIEW: \(url.path())")
    }
}
