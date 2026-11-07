import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Cihaz arayüzü önizlemeleri (sabit veri). `ADALMON_PREVIEW_DIR` verilince PNG yazar.
@MainActor
final class DevicePreviewTests: XCTestCase {
    private var previewDir: URL? {
        (ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"]).flatMap { $0.isEmpty ? nil : URL(filePath: $0) }
    }

    @discardableResult
    private func snapshot<V: View>(_ view: V, size: NSSize?, name: String, dark: Bool = true) async throws -> NSSize {
        let host = NSHostingView(rootView: view.background(dark ? Color(white: 0.11) : Color(white: 0.96)).preferredColorScheme(dark ? .dark : .light))
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: size?.width ?? 420, height: size?.height ?? 900), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        let final = size ?? host.fittingSize
        if size == nil { host.frame = NSRect(origin: .zero, size: final); window.setContentSize(final) }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(0.6))
        host.layoutSubtreeIfNeeded()
        if let dir = previewDir {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appending(path: "\(name).png"))
        }
        window.close()
        return final
    }

    private func page(_ tab: BatteryTab, service: DeviceBatteryService, store: UsageStore) throws -> some View {
        let suite = try XCTUnwrap(UserDefaults(suiteName: "adalmon.preview.\(UUID().uuidString)"))
        let prefs = Preferences(defaults: suite)
        prefs.deviceSettings["yusuf iphone"] = { var s = DeviceSettings(); s.alertEnabled = true; return s }()
        prefs.menuBar.setPinned(device: "yusuf iphone", name: "Yusuf iPhone", true)
        return BatteryPage(monitor: BatteryMonitor(preview: .sample, store: store), store: store, router: SettingsRouter(isDockModeOn: { true }),
                           devices: service, prefs: prefs, initialTab: tab)
    }

    private func tempStore() throws -> (UsageStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "devp-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (UsageStore(path: dir.appending(path: "u.sqlite").path), dir)
    }

    func testPanelShowsDeviceRows() async throws {
        var data = PanelData.sample
        data.battery = .sample
        data.devices = DeviceBattery.samples
        let size = try await snapshot(PanelContent(data: data, config: .constant(PanelConfig()), actions: .inert).background(Color(white: 0.16)), size: nil, name: "bat2-panel-devices")
        XCTAssertLessThanOrEqual(size.height, 1100)
        // Mac pili olmayan masaüstünde yalnızca cihazlar.
        var desktop = data
        desktop.battery = nil
        try await snapshot(PanelContent(data: desktop, config: .constant(PanelConfig()), actions: .inert).background(Color(white: 0.16)), size: nil, name: "bat2-panel-devices-desktop")
    }

    func testDevicesAndIOSPagesRender() async throws {
        let (store, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let full = DeviceBatteryService(preview: DeviceBattery.samples, ios: [.sample])
        try await snapshot(page(.devices, service: full, store: store).frame(width: 1100, height: 900), size: NSSize(width: 1100, height: 900), name: "bat2-page-devices")
        try await snapshot(page(.ios, service: full, store: store).frame(width: 1100, height: 1500), size: NSSize(width: 1100, height: 1500), name: "bat2-page-ios")
        try await snapshot(page(.ios, service: full, store: store).frame(width: 760, height: 1700), size: NSSize(width: 760, height: 1700), name: "bat2-page-ios-narrow")
        try await snapshot(page(.devices, service: full, store: store).frame(width: 1100, height: 900), size: NSSize(width: 1100, height: 900), name: "bat2-page-devices-light", dark: false)
        let empty = DeviceBatteryService(preview: [])
        try await snapshot(page(.devices, service: empty, store: store).frame(width: 1000, height: 640), size: NSSize(width: 1000, height: 640), name: "bat2-page-devices-empty")
        try await snapshot(page(.ios, service: empty, store: store).frame(width: 1000, height: 700), size: NSSize(width: 1000, height: 700), name: "bat2-page-ios-empty")
    }

    func testMenuBarShowsPinnedDevices() async throws {
        var values = WidgetValues.sample
        values.devices = Dictionary(uniqueKeysWithValues: DeviceBattery.samples.map { ($0.id, BatteryGlyphState(device: $0)) })
        let comps = [MenuBarComponent.device("yusuf iphone"), MenuBarComponent.device("yusuf's airpods pro"), MenuBarComponent.device("magic keyboard"),
                     MenuBarComponent(.batteryLevel, visual: .batteryCapsule)]
        let config = MenuBarConfig.default
        let image = MenuBarComposer.image(for: comps, config: config, values: values, appearance: .darkAqua, zoom: 3)
        XCTAssertGreaterThan(MenuBarComposer.width(of: comps, config: config, values: values), 150)
        let strip = Image(nsImage: MenuBarComposer.bitmap(image, appearance: NSAppearance(named: .darkAqua)!, scale: 1)).interpolation(.high)
            .padding(.horizontal, 12).padding(.vertical, 6).background(Color(white: 0.12), in: .rect(cornerRadius: 8)).padding(20).background(Color(white: 0.2))
        try await snapshot(strip, size: nil, name: "bat2-menubar-devices")
    }

    func testDeviceAlertBubbleRenders() async throws {
        let event = BatteryAlertEvent(kind: .low(20), level: 18, minutes: nil, action: DeviceSettings().action, subject: "Yusuf’s AirPods Pro")
        XCTAssertEqual(event.title, "Yusuf’s AirPods Pro pili azaldı")
        try await snapshot(BatteryAlertBubbleView(event: event).padding(24), size: nil, name: "bat2-alert-device")
    }
}
