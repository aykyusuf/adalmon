import SwiftUI
import XCTest
@testable import Adalmon

final class ProcessesTabTests: XCTestCase {
    func testNeighborMovesAndClampsAtEnds() {
        XCTAssertEqual(ProcessesTab.processes.neighbor(1), .performance)
        XCTAssertEqual(ProcessesTab.startup.neighbor(-1), .history)
        XCTAssertEqual(ProcessesTab.processes.neighbor(-1), .processes)
        XCTAssertEqual(ProcessesTab.disk.neighbor(1), .disk)
    }

    func testEveryTabHasUniqueSymbolAndTitle() {
        XCTAssertEqual(Set(ProcessesTab.allCases.map(\.systemImage)).count, ProcessesTab.allCases.count)
        XCTAssertEqual(Set(ProcessesTab.allCases.map(\.title)).count, ProcessesTab.allCases.count)
    }
}

@MainActor
final class ProcessesTabBarLayoutTests: XCTestCase {
    /// En küçük pencerede içerik alanı ~670 pt: çubuk tam etiketle ya da simge moduna düşerek sığmalı ve yüksekliği sabit kalmalı.
    func testBarFitsAtMinimumAndNarrowWidths() {
        struct Host: View {
            @State var tab: ProcessesTab = .processes
            var body: some View { CapsuleTabBar(selection: $tab) }
        }
        for width in [670.0, 420.0, 300.0] {
            let host = NSHostingView(rootView: Host().frame(width: width))
            host.frame = NSRect(x: 0, y: 0, width: width, height: 60)
            host.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(host.fittingSize.width, width + 0.5, "\(width) pt'de taşıyor")
            XCTAssertGreaterThan(host.fittingSize.height, 30)
            XCTAssertLessThan(host.fittingSize.height, 50)
        }
    }
}
