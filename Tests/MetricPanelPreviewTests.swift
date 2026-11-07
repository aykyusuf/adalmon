import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Metrik panellerini sahte veriyle ekran dışı pencerede çizip PNG yazar (p5-*.png) ve yükseklik sınırını doğrular.
/// Çıktı dizini: ADALMON_P5_DIR (xcodebuild için TEST_RUNNER_ADALMON_P5_DIR) ya da geçici dizin.
@MainActor
final class MetricPanelPreviewTests: XCTestCase {
    private func outputDir() throws -> URL {
        let env = ProcessInfo.processInfo.environment["ADALMON_P5_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        let dir = env.map { URL(filePath: $0) } ?? FileManager.default.temporaryDirectory.appending(path: "p5-previews")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func battery(charging: Bool = false) -> BatteryPanelSource {
        var reading: BatteryReading = charging ? .sampleCharging : .sample
        if !charging { reading.cycles = 178; reading.appleMaxCapacityPercent = 82 }
        return BatteryPanelSource(
            reading: reading, lastRefresh: Date().addingTimeInterval(-180),
            apps: [.init(app: "/Applications/Warp.app", name: "Warp", share: 0.60), .init(app: "/System/Applications/Messages.app", name: "WhatsApp", share: 0.20),
                   .init(app: "/Applications/Xcode.app", name: "Xcode", share: 0.17)],
            devices: DeviceBattery.samples, lowPowerControl: .readOnly)
    }

    @discardableResult
    private func render(_ kind: PanelKind, name: String, data: PanelData = .metricSample, config: PanelConfig = PanelConfig(),
                        battery source: BatteryPanelSource? = nil, hover: Double? = nil, maxHeight: CGFloat? = nil, png: Bool = true) async throws -> NSSize {
        let live = PanelLiveSources(model: nil)
        live.setFixtures(processes: PanelData.metricProcesses.map { p in
            kind == .memory ? TopProcess(key: p.key, name: p.name, valueText: "\(Int(p.fraction * 2400) + 180) MB", fraction: p.fraction) : p
        }, writers: PanelData.metricProcesses.map { TopProcess(key: $0.key, name: $0.name, valueText: "\(Int($0.fraction * 9_000) + 40) MB", fraction: $0.fraction) })
        let view = PanelKindView(kind: kind, data: data, live: live, config: .constant(config), actions: .inert,
                                 battery: source ?? battery(), maxHeight: maxHeight, previewHover: hover)
            .background(Color(white: 0.13))
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
            .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: PanelContent.width, height: 1400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
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
        try await Task.sleep(for: .milliseconds(200))
        if png {
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let url = try outputDir().appending(path: "p5-\(name).png")
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
            print("P5_PREVIEW: \(url.path()) \(Int(size.width))x\(Int(size.height))")
        }
        return size
    }

    func testRenderAllPanels() async throws {
        let cpu = try await render(.cpu, name: "cpu", hover: 0.62)
        try await render(.gpu, name: "gpu", hover: 0.35)
        try await render(.memory, name: "memory")
        try await render(.disk, name: "disk", hover: 0.8)
        try await render(.network, name: "network", data: networkData())
        try await render(.temperature, name: "temperature")
        let bat = try await render(.battery, name: "battery")
        try await render(.battery, name: "battery-charging", battery: battery(charging: true))
        var full = BatteryReading.sampleCharging
        full.level = 100; full.isCharging = false; full.isFullyCharged = true; full.amperageMA = 0; full.timeToFullMinutes = nil
        full.systemPowerMW = 14_200; full.batteryPowerMW = 0
        try await render(.battery, name: "battery-full", battery: BatteryPanelSource(reading: full, lastRefresh: .now, apps: battery().apps, devices: DeviceBattery.samples))
        let collapsed = try await render(.battery, name: "battery-collapsed",
                                         config: PanelConfig(detailCollapsed: ["battery.apps", "battery.devices"]))
        XCTAssertLessThan(collapsed.height + 250, bat.height, "daraltılan bölümler paneli belirgin küçültmeli")
        XCTAssertGreaterThan(cpu.height, 400)
    }

    func testMetricPanelHeightIsCappedAndScrolls() async throws {
        let open = PanelConfig(detailExpanded: ["battery.info"]) // varsayılan kompakt; "Pil bilgisi" açılınca uzun
        let natural = try await render(.battery, name: "x", config: open, maxHeight: nil, png: false).height
        XCTAssertGreaterThan(natural, 900, "pil paneli doğal olarak uzun")
        let capped = try await render(.battery, name: "battery-capped", config: open, maxHeight: 640).height
        XCTAssertLessThanOrEqual(capped, 641, "panel sınırı aştı: \(capped)")
        XCTAssertGreaterThan(capped, 600, "panel kalan yeri kullanmalı")
        let cpuNatural = try await render(.cpu, name: "x", png: false).height
        let cpuRoomy = try await render(.cpu, name: "x", maxHeight: cpuNatural + 300, png: false).height
        XCTAssertEqual(cpuRoomy, cpuNatural, accuracy: 2, "sığıyorsa doğal yükseklik")
    }

    private func networkData() -> PanelData {
        var d = PanelData.metricSample
        d.isMobile = true
        d.opensMainWindow = true
        return d
    }
}
