import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Widget görünümleri ve ayar panelleri (ekran dışı). `ADALMON_PREVIEW_DIR` verilince `bat3-*.png` yazar.
@MainActor
final class WidgetPreviewTests: XCTestCase {
    private var previewDir: URL? {
        (ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"]).flatMap { $0.isEmpty ? nil : URL(filePath: $0) }
    }

    /// Görüntüyü çizer, boş olmadığını doğrular (≥ 12 farklı renk) ve istenirse PNG yazar.
    @discardableResult
    private func render<V: View>(_ view: V, size: NSSize?, name: String, dark: Bool = true) async throws -> NSSize {
        let host = NSHostingView(rootView: view.padding(20).background(dark ? Color(white: 0.11) : Color(white: 0.93)).preferredColorScheme(dark ? .dark : .light))
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: size?.width ?? 400, height: size?.height ?? 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        let final = size ?? host.fittingSize
        host.frame = NSRect(origin: .zero, size: final)
        window.setContentSize(final)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(0.3))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        var colors = Set<UInt32>()
        for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    colors.insert(UInt32(c.redComponent * 31) << 10 | UInt32(c.greenComponent * 31) << 5 | UInt32(c.blueComponent * 31))
                }
            }
        }
        XCTAssertGreaterThan(colors.count, 12, "\(name): görüntü boş görünüyor")
        XCTAssertGreaterThan(final.width, 100)
        if let dir = previewDir {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appending(path: "\(name).png"))
        }
        window.close()
        return final
    }

    private func row(_ kind: WidgetPreviewKind, snapshot: WidgetSnapshot, options: WidgetBatteryOptions, sizes: [WidgetSize] = WidgetSize.allCases) -> some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(sizes) { WidgetPreviewContent(kind: kind, size: $0, snapshot: snapshot, options: options) }
        }
    }

    func testAllBatteriesEveryStyleAndSize() async throws {
        for style in WidgetBatteryStyle.allCases {
            var o = WidgetBatteryOptions()
            o.style = style
            try await render(row(.allBatteries, snapshot: .sample(), options: o), size: nil, name: "bat3-all-\(style.rawValue)")
        }
        var noNames = WidgetBatteryOptions()
        noNames.showNames = false
        noNames.includeMac = false
        try await render(row(.allBatteries, snapshot: .sample(), options: noNames), size: nil, name: "bat3-all-rings-nonames")
        var list = noNames
        list.style = .list
        try await render(row(.allBatteries, snapshot: .sample(), options: list, sizes: [.small, .medium]), size: nil, name: "bat3-all-list-nonames")
    }

    func testMonochromeLightStaleAndEmpty() async throws {
        var mono = WidgetBatteryOptions()
        mono.appearance = .mono
        for style in WidgetBatteryStyle.allCases {
            mono.style = style
            try await render(row(.allBatteries, snapshot: .sample(), options: mono, sizes: [.small, .medium]), size: nil, name: "bat3-all-mono-\(style.rawValue)-light", dark: false)
        }
        let stale = WidgetSnapshot.sample(now: Date.now.addingTimeInterval(-30 * 60))
        try await render(row(.allBatteries, snapshot: stale, options: WidgetBatteryOptions(), sizes: [.small, .medium]), size: nil, name: "bat3-all-stale")
        var menuBar = WidgetBatteryOptions()
        menuBar.selection = .sameAsMenuBar
        var emptySnap = WidgetSnapshot.sample()
        emptySnap.pinnedDeviceIDs = []
        menuBar.includeMac = false
        try await render(row(.allBatteries, snapshot: emptySnap, options: menuBar, sizes: [.small, .medium]), size: nil, name: "bat3-all-empty")
    }

    func testMacSystemAndMobileWidgets() async throws {
        let o = WidgetBatteryOptions()
        try await render(row(.macBattery, snapshot: .sample(), options: o), size: nil, name: "bat3-mac")
        var charging = WidgetSnapshot.sample()
        charging.mac = WidgetSnapshot.MacEntry(level: 64, state: .charging, minutesToEmpty: nil, minutesToFull: 40, healthPercent: 86, cycles: 178,
                                                cycleLimit: 1000, temperatureC: 33.2, adapterWatts: 70, powerW: 52.3)
        try await render(row(.macBattery, snapshot: charging, options: o), size: nil, name: "bat3-mac-charging")
        try await render(row(.macBattery, snapshot: .sample(), options: o), size: nil, name: "bat3-mac-light", dark: false)
        try await render(row(.system, snapshot: .sample(), options: o), size: nil, name: "bat3-system")
        try await render(row(.mobileQuota, snapshot: .sample(), options: o), size: nil, name: "bat3-mobile")
        var over = WidgetSnapshot.sample()
        over.system?.mobileTodayBytes = 2_700_000_000
        try await render(row(.mobileQuota, snapshot: over, options: o), size: nil, name: "bat3-mobile-warn")
        // Mac pili olmayan masaüstü ve hiç sistem verisi olmayan durum çökmeden çizilir.
        var desktop = WidgetSnapshot.sample()
        desktop.mac = nil
        desktop.system = nil
        try await render(row(.macBattery, snapshot: desktop, options: o, sizes: [.small, .medium]), size: nil, name: "bat3-desktop")
    }

    func testEveryKindAndSizeRenders() async throws {
        for kind in WidgetPreviewKind.allCases {
            for size in WidgetSize.allCases {
                let fitted = try await render(WidgetPreviewContent(kind: kind, size: size, snapshot: .sample(), options: WidgetBatteryOptions()), size: nil,
                                              name: "bat3-cell-\(kind.rawValue)-\(size.rawValue)")
                XCTAssertEqual(fitted.width, size.canvas.width + 40, accuracy: 1, "\(kind) \(size)")
                XCTAssertEqual(fitted.height, size.canvas.height + 40, accuracy: 1, "\(kind) \(size)")
            }
        }
    }

    func testSettingsPanes() async throws {
        let pane = WidgetsSettingsPane(snapshot: { .sample() }, isLive: { true }, kind: .allBatteries, size: .medium)
        try await render(pane.frame(width: 860, height: 1250), size: NSSize(width: 900, height: 1290), name: "bat3-settings-widgets")
        let mac = WidgetsSettingsPane(snapshot: { .sample() }, isLive: { false }, kind: .macBattery, size: .large)
        try await render(mac.frame(width: 860, height: 1250), size: NSSize(width: 900, height: 1290), name: "bat3-settings-widgets-mac")
        try await render(ShortcutsSettingsPane().frame(width: 860, height: 700), size: NSSize(width: 900, height: 740), name: "bat3-settings-shortcuts")
        try await render(WidgetsSettingsPane(snapshot: { .sample() }, isLive: { true }).frame(width: 860, height: 1250), size: NSSize(width: 900, height: 1290),
                         name: "bat3-settings-widgets-light", dark: false)
    }
}
