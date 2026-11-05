import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Paneli sahte veriyle PNG olarak çizer ve yüksekliğini ölçer.
/// Çıktı dizini: ADALMON_PANEL_PREVIEW_DIR ya da geçici dizin/panel-previews.
@MainActor
final class PanelSnapshotTests: XCTestCase {
    func testRenderPanelDensities() throws {
        let dir = Self.outputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var variants: [(name: String, config: PanelConfig, data: PanelData)] = [
            ("compact", PanelConfig(), .sample),
            ("comfortable", PanelConfig(density: .comfortable), .sample),
            ("compact-rows", PanelConfig(tileStyle: .rows), .sample),
            ("comfortable-cards", PanelConfig(density: .comfortable, tileStyle: .cards, chartHeight: .medium), .sample),
        ]
        var noFilter = PanelData.sample
        noFilter.filterConnected = false
        noFilter.installerState = .notInstalled
        variants.append(("compact-nofilter", PanelConfig(), noFilter))
        var withToast = PanelData.sample
        withToast.toast = AppModel.Toast(message: "Safari mobil veride engellendi (şu an Wi-Fi'desin, etkilenmez)", undoApp: "x", undoBlocked: false)
        variants.append(("compact-toast-collapsed", PanelConfig(collapsed: [.system, .networkChart, .mobileCap]), withToast))

        var heights: [String: CGFloat] = [:]
        for variant in variants {
            for scheme in [ColorScheme.dark, .light] {
                let view = PanelContent(data: variant.data, config: .constant(variant.config), actions: .inert)
                    .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.95))
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage, "render failed")
                heights[variant.name] = image.size.height
                let tiff = try XCTUnwrap(image.tiffRepresentation)
                let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
                let url = dir.appending(path: "panel-\(variant.name)-\(scheme == .dark ? "dark" : "light").png")
                try png.write(to: url)
                print("PANEL_PREVIEW: \(url.path()) height=\(image.size.height)pt")
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
