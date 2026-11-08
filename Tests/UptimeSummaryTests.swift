import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Birleşik panel alt bilgisi ve Genel bakış kartı, mevcut `UptimeFormatter` metinlerini taşır.
@MainActor
final class UptimeSummaryTests: XCTestCase {
    private let boot = Date(timeIntervalSince1970: 1_000_000)

    func testSummaryUsesFormatter() throws {
        let now = boot.addingTimeInterval(2 * 86400 + 23 * 3600 + 14 * 60)
        let summary = try XCTUnwrap(UptimeSummary.make(boot: boot, now: now))
        XCTAssertEqual(summary.duration, "2 g 23 sa 14 dk")
        XCTAssertEqual(summary.shortDuration, "2 g 23 sa")
        XCTAssertEqual(summary.boot, UptimeFormatter.bootStamp(boot))
        XCTAssertEqual(summary.line, "Açık: 2 g 23 sa · Son açılış \(UptimeFormatter.bootStamp(boot))")
        // CPU paneli ile aynı metin
        let cpu = CPUPanelModel.make(PanelData.metricSample, processes: [], bootTime: boot, now: now)
        XCTAssertEqual(cpu.uptimeText, summary.duration)
    }

    func testSummaryIsNilWithoutBootTime() {
        XCTAssertNil(UptimeSummary.make(boot: nil, now: .now))
    }

    func testSummaryAdvancesWithNow() throws {
        let a = try XCTUnwrap(UptimeSummary.make(boot: boot, now: boot.addingTimeInterval(14 * 60)))
        let b = try XCTUnwrap(UptimeSummary.make(boot: boot, now: boot.addingTimeInterval(15 * 60)))
        XCTAssertEqual(a.shortDuration, "14 dk")
        XCTAssertEqual(b.shortDuration, "15 dk")
    }

    private func height<V: View>(_ view: V, width: CGFloat) -> CGFloat {
        let host = NSHostingView(rootView: view.frame(width: width))
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: width, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    func testPanelFooterKeepsHeightWhenUptimeFitsOnStatusRow() {
        let width = PanelContent.width - 32
        let with = height(PanelFooter(data: .sample, onQuit: {}, bootTime: boot), width: width)
        let without = height(PanelFooter(data: .sample, onQuit: {}, bootTime: nil), width: width)
        XCTAssertEqual(with, without, accuracy: 0.5)
    }

    func testPanelFooterWrapsUptimeToSecondRowWhenStatusIsLong() {
        var data = PanelData.sample
        data.proxyPorts = [8080]
        data.proxyOwnerPaths = ["/Applications/Çok Uzun Bir Uygulama Adı.app"]
        let width = PanelContent.width - 32
        let with = height(PanelFooter(data: data, onQuit: {}, bootTime: boot), width: width)
        let without = height(PanelFooter(data: data, onQuit: {}, bootTime: nil), width: width)
        XCTAssertGreaterThan(with, without)
    }

    func testOverviewCardHiddenWithoutBootTime() {
        XCTAssertGreaterThan(height(OverviewUptimeCard(boot: boot), width: 340), 40)
        XCTAssertLessThan(height(OverviewUptimeCard(boot: nil), width: 340), 1)
    }
}
