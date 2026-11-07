import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Faz 6 önizlemeleri (p6-*.png): opak koyu yüzey, pil paneli, iskelet/yüklü CPU paneli, cihaz menü çubuğu şeridi.
/// Çıktı dizini: ADALMON_P6_DIR (xcodebuild için TEST_RUNNER_ADALMON_P6_DIR) ya da geçici dizin.
@MainActor
final class PanelP6PreviewTests: XCTestCase {
    private func outputDir() throws -> URL {
        let env = ProcessInfo.processInfo.environment["ADALMON_P6_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        let dir = env.map { URL(filePath: $0) } ?? FileManager.default.temporaryDirectory.appending(path: "p6-previews")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func png<V: View>(_ view: V, name: String, dark: Bool = true) async throws -> NSSize {
        let host = NSHostingView(rootView: view.preferredColorScheme(dark ? .dark : .light))
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 600, height: 1600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        defer { window.close() }
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
        }
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let url = try outputDir().appending(path: "p6-\(name).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("P6_PREVIEW: \(url.path()) \(Int(size.width))x\(Int(size.height))")
        return size
    }

    /// Parlak duvar kâğıdı benzeri zemin üzerinde panel: opaklığı ve gölgeyi gösterir.
    private func onWallpaper<V: View>(_ panel: V, dark: Bool = true) -> some View {
        panel
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            .padding(26)
            .background(LinearGradient(colors: [Color(red: 0.93, green: 0.88, blue: 0.62), Color(red: 0.55, green: 0.78, blue: 0.92)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func batterySource(loading: Bool = false, pinned: Set<String> = ["yusuf iphone"]) -> BatteryPanelSource {
        var reading = BatteryReading.sampleCharging
        reading.level = 100; reading.isCharging = false; reading.isFullyCharged = true; reading.amperageMA = 0; reading.timeToFullMinutes = nil
        reading.cycles = 178; reading.appleMaxCapacityPercent = 82
        let devices: [DeviceBattery] = [
            DeviceBattery(id: "orochi v2", name: "Orochi V2", kind: .mouse, level: 18, lastSeen: .now, sources: [.hid]),
            DeviceBattery(id: "yusuf iphone", name: "Yusuf iPhone", kind: .iPhone, level: 32, lastSeen: .now, sources: [.gatt]),
            DeviceBattery(id: "yusuf ipad", name: "Yusuf iPad", kind: .iPad, level: 72, lastSeen: .now, sources: [.gatt]),
            DeviceBattery(id: "keychron k10 he", name: "Keychron K10 HE", kind: .keyboard, level: 78, lastSeen: .now, sources: [.hid]),
            DeviceBattery(id: "yusuf's airpods pro", name: "Yusuf’s AirPods Pro", kind: .airPodsPro, level: 97, left: 97, right: 100, lastSeen: .now, sources: [.advertisement]),
        ]
        return BatteryPanelSource(
            reading: reading, lastRefresh: Date().addingTimeInterval(-60),
            apps: loading ? [] : [.init(app: "/Applications/Safari.app", name: "Safari", share: 0.52), .init(app: "/Applications/Adalmon.app", name: "Adalmon", share: 0.27),
                                  .init(app: "/Applications/Warp.app", name: "Warp", share: 0.18)],
            devices: loading ? [] : devices, lowPowerControl: .toggle, pinnedDeviceIDs: pinned, appsLoading: loading, devicesLoading: loading)
    }

    private func panel(_ kind: PanelKind, live: PanelLiveSources, config: PanelConfig = PanelConfig(), battery: BatteryPanelSource? = nil,
                       focus: String? = nil, dark: Bool = true) -> some View {
        let v = PanelKindView(kind: kind, data: .metricSample, live: live, config: .constant(config), actions: .inert,
                              battery: battery ?? batterySource(), maxHeight: nil, previewHover: 0.6, focusDeviceID: focus)
            .panelSurface(config.background)
        return onWallpaper(v, dark: dark)
    }

    private func loadedLive() -> PanelLiveSources {
        let live = PanelLiveSources(model: nil)
        live.setFixtures(processes: PanelData.metricProcesses, writers: PanelData.metricProcesses)
        return live
    }

    func testBatteryPanelPreviews() async throws {
        let live = loadedLive()
        let normal = try await png(panel(.battery, live: live), name: "battery-default")
        let open = try await png(panel(.battery, live: live, config: PanelConfig(detailExpanded: ["battery.info"])), name: "battery-info-open")
        XCTAssertGreaterThan(open.height, normal.height + 300, "Pil bilgisi açılınca uzar; varsayılan kapalı")
        XCTAssertLessThan(normal.height, 1000, "varsayılan kompakt")
        _ = try await png(panel(.battery, live: live, battery: batterySource(loading: true)), name: "battery-loading")
        _ = try await png(panel(.battery, live: live, focus: "yusuf iphone"), name: "battery-focus-device")
        _ = try await png(panel(.battery, live: live, config: PanelConfig(background: .glass)), name: "battery-glass")
        _ = try await png(panel(.battery, live: live, dark: false), name: "battery-light", dark: false)
    }

    func testCPUPanelSkeletonAndLoaded() async throws {
        let loading = PanelLiveSources(model: nil)
        XCTAssertTrue(loading.isMeasuring)
        let skeleton = try await png(panel(.cpu, live: loading), name: "cpu-skeleton")
        let loaded = try await png(panel(.cpu, live: loadedLive()), name: "cpu-loaded")
        XCTAssertEqual(skeleton.height, loaded.height, accuracy: 1.5, "iskelet gerçek satırla aynı yükseklikte: yerleşim zıplamaz")
        let diskSkeleton = try await png(panel(.disk, live: loading), name: "disk-skeleton")
        let diskLoaded = try await png(panel(.disk, live: loadedLive()), name: "disk-loaded")
        XCTAssertEqual(diskSkeleton.height, diskLoaded.height, accuracy: 1.5)
    }

    func testDeviceMenuBarStrip() async throws {
        var values = WidgetValues.sample
        var devices = DeviceBattery.samples
        devices[0].level = 32
        values.devices = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, BatteryGlyphState(device: $0)) })
        var low = BatteryGlyphState(device: DeviceBattery(id: "orochi v2", name: "Orochi V2", kind: .mouse, level: 18, lastSeen: .now))
        low.isApproximate = false
        values.devices["orochi v2"] = low
        var config = MenuBarConfig.default
        config.components += [.device("yusuf iphone"), .device("yusuf's airpods pro"), .device("orochi v2"), .device("yusuf ipad")]
        var mac = MenuBarComponent(.batteryLevel, visual: .batteryCapsule)
        mac.battery.showTime = false
        config.components.insert(mac, at: 0)
        let groups = StatusItemPlan.groups(for: config)
        XCTAssertEqual(groups.count, 5, "birleşik öğe + 4 ayrı cihaz öğesi")
        let items = groups.map { g in
            Image(nsImage: MenuBarComposer.bitmap(MenuBarComposer.image(for: g.items, config: config, values: values, appearance: .darkAqua, zoom: 3),
                                                  appearance: NSAppearance(named: .darkAqua)!, scale: 1))
                .interpolation(.high)
        }
        let strip = HStack(spacing: 30) { ForEach(items.indices, id: \.self) { items[$0] } }
            .padding(.horizontal, 28).padding(.vertical, 12)
            .background(Color(red: 0.14, green: 0.2, blue: 0.22), in: .rect(cornerRadius: 12))
            .padding(24)
            .background(Color(white: 0.12))
        _ = try await png(strip, name: "menubar-device-strip")
    }
}
