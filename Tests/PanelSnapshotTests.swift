import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Paneli sahte veriyle ekran dışı bir pencerede (gerçek denetimlerle) çizip PNG yazar ve yüksekliğini ölçer.
/// Çıktı dizini: ADALMON_PANEL_PREVIEW_DIR ya da geçici dizin/panel-previews.
@MainActor
final class PanelSnapshotTests: XCTestCase {
    func testRenderPanelDensities() throws {
        let dir = Self.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var variants: [(name: String, config: PanelConfig, data: PanelData)] = [
            ("compact", PanelConfig(), .sample),
            ("comfortable", PanelConfig(density: .comfortable), .sample),
            ("compact-disk", PanelConfig(cards: PanelConfig.defaultCards.map { PanelCardItem(kind: $0.kind, isVisible: true) }), .sample),
        ]
        var noFilter = PanelData.sample
        noFilter.filterConnected = false
        noFilter.installerState = .notInstalled
        variants.append(("compact-nofilter", PanelConfig(), noFilter))
        var hotspot = PanelData.sample
        hotspot.isMobile = true
        hotspot.medium = .wifi
        hotspot.opensMainWindow = true
        var withToast = hotspot
        withToast.toast = AppModel.Toast(message: "Safari mobil veride engellendi (şu an Wi-Fi'desin, etkilenmez)", undoApp: "x", undoBlocked: false)
        variants.append(("compact-hotspot-toast-collapsed", PanelConfig(collapsed: [.last60, .today]), withToast))

        var heights: [String: CGFloat] = [:]
        for variant in variants {
            for dark in [true, false] {
                let view = PanelContent(data: variant.data, config: .constant(variant.config), actions: .inert)
                    .background(dark ? Color(white: 0.16) : Color(white: 0.93))
                let host = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: PanelContent.width, height: 900),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = host
                window.isReleasedWhenClosed = false
                window.orderBack(nil)
                host.layoutSubtreeIfNeeded()
                let size = host.fittingSize
                host.frame = NSRect(origin: .zero, size: size)
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                let url = dir.appending(path: "panel-\(variant.name)-\(dark ? "dark" : "light").png")
                try png.write(to: url)
                heights[variant.name] = size.height
                print("PANEL_PREVIEW: \(url.path()) height=\(size.height)pt")
                window.close()
            }
        }
        let compact = try XCTUnwrap(heights["compact"])
        XCTAssertLessThanOrEqual(compact, 620, "Kompakt panel 620 pt'yi aşmamalı")
        XCTAssertLessThan(compact, try XCTUnwrap(heights["comfortable"]))
    }

    private static func outputDirectory() -> URL {
        let env = ProcessInfo.processInfo.environment["ADALMON_PANEL_PREVIEW_DIR"]
        return URL(filePath: env ?? NSTemporaryDirectory()).appending(path: env == nil ? "panel-previews" : "")
    }
}
