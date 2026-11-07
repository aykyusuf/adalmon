import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Menü çubuğu paneli ekrandan uzun olamaz: üst bölümler kaydırılır, alt bilgi görünür kalır.
@MainActor
final class PanelHeightCapTests: XCTestCase {
    private func tallData() -> PanelData {
        var data = PanelData.sample
        data.battery = .sample
        data.devices = DeviceBattery.samples
        return data
    }

    /// Panelin pencerede yerleşip ölçümlerin (onGeometryChange) oturmasından sonraki doğal boyutu.
    private func settledSize(maxHeight: CGFloat?, png: String? = nil) throws -> NSSize {
        let view = PanelContent(data: tallData(), config: .constant(PanelConfig()), actions: .inert, maxHeight: maxHeight)
            .background(Color(white: 0.16))
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: PanelContent.width, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        for _ in 0..<4 {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            host.layoutSubtreeIfNeeded()
        }
        let size = host.fittingSize
        if let png {
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: png))
            }
        }
        return size
    }

    func testPanelNeverExceedsMaxHeightButKeepsNaturalHeightWhenItFits() throws {
        let natural = try settledSize(maxHeight: nil).height
        XCTAssertGreaterThan(natural, 700, "test verisi yeterince uzun olmalı")
        let cap: CGFloat = 520
        let dir = FileManager.default.temporaryDirectory.path()
        let capped = try settledSize(maxHeight: cap, png: dir + "panel-capped.png").height
        XCTAssertLessThanOrEqual(capped, cap + 1, "panel sınırı aştı: \(capped)")
        XCTAssertGreaterThan(capped, cap - 60, "panel kalan yeri kullanmalı: \(capped)")
        let roomy = try settledSize(maxHeight: natural + 400).height
        XCTAssertEqual(roomy, natural, accuracy: 2, "sığıyorsa doğal yükseklik korunur")
    }

    func testAvailableHeightFollowsScreenAndButtonPosition() {
        let visible = NSRect(x: 0, y: 0, width: 1512, height: 944)
        let h = PanelController.availableHeight(buttonMinY: 944, visible: visible)
        XCTAssertLessThan(h, visible.height)
        XCTAssertEqual(h, 944 - 2 * 12, accuracy: 0.5, "ekran yüksekliği - iki kenar boşluğu")
        XCTAssertEqual(PanelController.availableHeight(buttonMinY: 600, visible: visible), 600 - 6 - 12, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(PanelController.availableHeight(buttonMinY: 100, visible: visible), 240)
    }
}
