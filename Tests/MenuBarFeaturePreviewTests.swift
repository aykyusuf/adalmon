import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Opt-in PNGs of the 2026-11-11 features (kayıtlı düzenler + geri al şeridi, seviye renkleri, Renksiz menü çubuğu)
/// for visual sign-off. Run with TEST_RUNNER_ADALMON_PREVIEW_DIR=<dir>.
@MainActor
final class MenuBarFeaturePreviewTests: XCTestCase {
    func testExportFeaturePreviews() throws {
        guard let path = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"] else { return }
        let dir = URL(filePath: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "MenuBarFeaturePreviewTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let archiveURL = FileManager.default.temporaryDirectory.appending(path: "preview-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        // Kayıtlı düzenler + otomatik yedek + geri al şeridi.
        let store = MenuBarConfigStore(defaults: defaults, archive: MenuBarLayoutArchive(fileURL: archiveURL))
        store.config = MenuBarPreset.renkli.makeConfig()
        store.saveCurrentLayout(name: "Çalışma düzenim")
        store.config = MenuBarPreset.grafik.makeConfig()
        store.saveCurrentLayout(name: "Sunum")
        store.resetToDefault()
        let layouts = LayoutsPreview(store: store)
        for dark in [false, true] {
            try MenuBarSettingsSnapshotTestsAccess.snapshot(layouts, dark: dark, size: NSSize(width: 760, height: 620),
                                                            to: dir.appending(path: "kayitli-duzenler-\(dark ? "dark" : "light").png"))
        }

        // Seviye renkleri editörü (Normal: Renksiz, Uyarı: özel mor, Kritik: varsayılan).
        let colors = ThresholdColors(normal: .none, warning: .custom(RGBAColor(red: 0.55, green: 0.35, blue: 0.95, alpha: 1)))
        let editor = EditorPreview(thresholds: Thresholds(warning: 0.7, critical: 0.9), colors: colors)
        try MenuBarSettingsSnapshotTestsAccess.snapshot(editor, dark: false, size: NSSize(width: 620, height: 420),
                                                        to: dir.appending(path: "seviye-renkleri-editor.png"))

        // Menü çubuğu: bellek eşik modunda, normal seviye Renksiz vs varsayılan yeşil.
        for (name, normal) in [("varsayilan", LevelColor.automatic), ("renksiz", LevelColor.none)] {
            var c = MenuBarComponent(.memoryUsed, visual: .text, colorMode: .threshold, colorTarget: .value, showLabel: true)
            c.levelColors = ThresholdColors(normal: normal)
            c.thresholds = Thresholds(warning: 0.9, critical: 0.95) // örnek değer normal seviyede kalsın
            let config = MenuBarConfig(components: [MenuBarComponent(.cpu, showLabel: true), c])
            for dark in [false, true] {
                let bar = MenuBarMockPreview(config: config, values: .sample, dark: dark, zoom: 2, wallpaperMargin: 8)
                    .frame(width: 520, height: 90)
                try MenuBarSettingsSnapshotTestsAccess.snapshot(bar, dark: dark, size: NSSize(width: 520, height: 90),
                                                                to: dir.appending(path: "menubar-bellek-\(name)-\(dark ? "dark" : "light").png"))
            }
        }
    }
}

private struct LayoutsPreview: View {
    @Bindable var store: MenuBarConfigStore
    @State private var pending: LayoutConfirmation?

    var body: some View {
        Form {
            MenuBarUndoSection(store: store)
            MenuBarLayoutsSection(store: store, pending: $pending)
        }
        .formStyle(.grouped)
    }
}

private struct EditorPreview: View {
    @State var thresholds: Thresholds
    @State var colors: ThresholdColors

    var body: some View {
        Form {
            Section("Renkler ve eşikler (Bellek: boş)") {
                ThresholdColorsEditor(thresholds: $thresholds, colors: $colors, field: .memoryFree)
            }
        }
        .formStyle(.grouped)
    }
}

/// `MenuBarSettingsSnapshotTests.snapshot` ile aynı çizim (offscreen NSHostingView).
@MainActor
enum MenuBarSettingsSnapshotTestsAccess {
    static func snapshot(_ view: some View, dark: Bool, size: NSSize, to url: URL) throws {
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
    }
}
