import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Regresyon: Süreçler sayfası (canlı tablo) kenar çubuğunu boşaltıp başlığı pencerenin üstüne itiyordu
/// (kullanıcı sayfadan çıkamıyordu). Ana pencere içeriği pencereyi hiçbir sayfada aşmamalı.
@MainActor
final class ProcessesLayoutTests: XCTestCase {
    func testProcessesPageStaysInsideWindowAt1400x900() async throws { try await assertLayout(NSSize(width: 1400, height: 900)) }
    func testProcessesPageStaysInsideWindowAtMinimumSize() async throws { try await assertLayout(NSSize(width: 940, height: 600)) }

    private func assertLayout(_ size: NSSize, file: StaticString = #filePath, line: UInt = #line) async throws {
        let h = MainWindowHarness(size: size, section: .processes)
        h.show()
        // Canlı tablo birkaç tur dolsun (ilk örnek taban çizgisidir).
        try await Task.sleep(for: .seconds(4))
        let bounds = h.contentBounds
        let views = h.allViews()

        // 1) Hiçbir görünüm (kenar çubuğu/ayrıntı ana bölmesi) pencere içerik alanını dikeyde aşmamalı.
        let split = try XCTUnwrap(views.first { $0 is NSSplitView }, "NSSplitView yok", file: file, line: line)
        let splitRect = h.windowRect(of: split)
        XCTAssertLessThanOrEqual(splitRect.height, bounds.height + 1, "Bölme görünümü pencereden uzun: \(splitRect)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(splitRect.minY, bounds.minY - 1, "Bölme görünümü pencerenin dışına kaymış: \(splitRect)", file: file, line: line)

        // 2) Kenar çubuğu: tüm sayfa satırlarına sahip ve pencerede görünür.
        let sidebar = try XCTUnwrap(views.compactMap { $0 as? NSTableView }.first { h.windowRect(of: $0).midX < 300 },
                                    "kenar çubuğu tablosu yok", file: file, line: line)
        XCTAssertGreaterThanOrEqual(sidebar.numberOfRows, MainSection.pages.count, "kenar çubuğu satırları kayıp", file: file, line: line)
        let sidebarRect = h.windowRect(of: sidebar).intersection(bounds)
        XCTAssertGreaterThan(sidebarRect.height, 200, "kenar çubuğu görünür değil", file: file, line: line)
        let firstRow = h.windowRect(of: sidebar).intersection(bounds)
        XCTAssertFalse(firstRow.isNull, file: file, line: line)

        // 3) Sayfa başlığı (görünüm seçici) pencerenin görünür alanında.
        h.router.selectedMainSection = .overview
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(h.router.selectedMainSection, .overview, file: file, line: line)
        let overviewRect = h.windowRect(of: try XCTUnwrap(h.allViews().first { $0 is NSSplitView }))
        XCTAssertLessThanOrEqual(overviewRect.height, bounds.height + 1, file: file, line: line)
        h.close()
    }
}
