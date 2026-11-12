import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Genel bakış "Kompakt pano": karo → sayfa eşlemesi, karo metinleri, kaydırmasız sığma ve (isteğe bağlı) PNG önizlemeleri.
@MainActor
final class OverviewPageTests: XCTestCase {
    // MARK: Mantık

    func testTileDestinations() {
        XCTAssertEqual(OverviewTileKind.network.destination, OverviewDestination(section: .network))
        XCTAssertEqual(OverviewTileKind.mobile.destination, OverviewDestination(section: .mobile))
        XCTAssertEqual(OverviewTileKind.cpu.destination, OverviewDestination(section: .processes, processesTab: .performance))
        XCTAssertEqual(OverviewTileKind.gpu.destination, OverviewDestination(section: .processes, processesTab: .performance))
        XCTAssertEqual(OverviewTileKind.memory.destination, OverviewDestination(section: .processes, processesTab: .performance))
        XCTAssertEqual(OverviewTileKind.disk.destination, OverviewDestination(section: .processes, processesTab: .disk))

        let router = SettingsRouter(isDockModeOn: { true })
        OverviewTileKind.disk.destination.open(router)
        XCTAssertEqual(router.selectedMainSection, .processes)
        XCTAssertEqual(router.processesTab, .disk)
        OverviewTileKind.mobile.destination.open(router)
        XCTAssertEqual(router.selectedMainSection, .mobile)
        XCTAssertEqual(router.processesTab, .disk, "Süreçler dışı hedef sekmeye dokunmaz")
    }

    func testTilesFromSampleKeepImportantInfo() {
        let data = PanelData.sample
        let today = TodaySummary.make(data: data, stats: OverviewDayStats(yesterdayTotal: 2_000_000_000))
        let tiles = OverviewTile.all(data: data, today: today, budget: .sample)
        XCTAssertEqual(tiles.map(\.kind), [.network, .mobile, .cpu, .gpu, .memory, .disk])
        let byKind = Dictionary(uniqueKeysWithValues: tiles.map { ($0.kind, $0) })
        XCTAssertEqual(byKind[.mobile]?.value, "%41")
        XCTAssertEqual(byKind[.mobile]?.secondary.hasSuffix(" biter"), true)
        XCTAssertEqual(byKind[.cpu]?.secondary, "54 °C")
        XCTAssertEqual(byKind[.memory]?.secondary.hasSuffix("boş"), true)
        XCTAssertEqual(byKind[.network]?.help.contains("Dün"), true, "Dün karşılaştırması ipucunda")
        XCTAssertEqual(byKind[.network]?.help.contains("Mobil"), true)

        var noGPU = data
        noGPU.snapshot?.gpu = nil
        XCTAssertFalse(OverviewTile.all(data: noGPU, today: today, budget: .sample).contains { $0.kind == .gpu })
    }

    func testShortEta() {
        var b = BudgetSnapshot.sample
        b.etaRecentRate = .reached
        XCTAssertEqual(OverviewBudgetSummary.shortEtaText(b), "doldu")
        b.etaRecentRate = .notToday
        XCTAssertEqual(OverviewBudgetSummary.shortEtaText(b), "bugün dolmaz")
    }

    func testTileColumnsWrapBalanced() {
        XCTAssertEqual(OverviewTileGrid.columns(count: 6, width: 1_030), 6)
        XCTAssertEqual(OverviewTileGrid.columns(count: 6, width: 680), 3, "4 + 2 yerine 3 + 3")
        XCTAssertEqual(OverviewTileGrid.columns(count: 5, width: 680), 3)
        XCTAssertEqual(OverviewTileGrid.columns(count: 6, width: 100), 1)
    }

    func testTodayRowsFilterAndSort() {
        let usage = [AppUsage(app: "a", bytes: 100, mobileBytes: 80, domains: []),
                     AppUsage(app: "b", bytes: 300, mobileBytes: 0, domains: [])]
        XCTAssertEqual(LiveAppUsage.today(usage, interface: .all).map(\.app), ["b", "a"])
        XCTAssertEqual(LiveAppUsage.today(usage, interface: .mobile).map(\.bytes), [80])
        XCTAssertEqual(LiveAppUsage.today(usage, interface: .wifi, rates: ["a": 7]).map(\.rate), [0, 7])
    }

    // MARK: Kaydırmasız sığma

    /// Seçilen satır sayısıyla listenin gerçek yüksekliği ayrılan alana sığmalı (filtre uyarısı + "Tümü" bağlantısı dahil en kötü durum).
    func testListFitsAllocatedHeight() {
        let rows = Self.sampleRows(count: 20)
        let controls = LiveAppControls(limit: { _ in nil }, blockScope: { _ in nil }, setLimit: { _, _ in }, setBlockScope: { _, _ in },
                                       filterReady: { false })
        let router = SettingsRouter(isDockModeOn: { true })
        let ranks = (0..<20).map { ResourceRank(app: "/Applications/App\($0).app", value: Double(20 - $0) * 1e10) }
        for height in stride(from: CGFloat(140), through: 620, by: 40) {
            let n = OverviewLayout.listRows(height: height)
            let header = AnyView(OverviewListHeader(tab: .constant(.network)))
            let live = LiveAppUsageList(source: .fixed(rows), controls: controls, maxRows: n, compact: true, initialRange: .hour1,
                                        initialRows: rows, showsToday: true, headerLeading: header, moreAction: {})
            let resource = OverviewResourceList(store: UsageStore(path: ":memory:"), metric: .cpu, maxRows: n, header: header,
                                                router: router, initialRanks: ranks)
            XCTAssertLessThanOrEqual(fittingHeight(live, width: 700), height, "Ağ listesi \(n) satırla \(height) pt'ye sığmalı")
            XCTAssertLessThanOrEqual(fittingHeight(resource, width: 700), height, "Kaynak listesi \(n) satırla \(height) pt'ye sığmalı")
        }
    }

    /// Gerçek ana pencere (varsayılan çerçeve ve en küçük boyut): bölme görünümü pencereyi aşmaz.
    func testOverviewStaysInsideWindow() async throws {
        let defaultSize = MainWindowController.defaultFrame(visible: NSRect(x: 0, y: 40, width: 1512, height: 880)).size
        for size in [defaultSize, NSSize(width: 940, height: 600)] {
            let h = MainWindowHarness(size: size, section: .overview, source: .fixed(.sample, liveRows: Self.sampleRows(count: 20)))
            h.window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(800))
            let bounds = h.contentBounds
            let split = try XCTUnwrap(h.allViews().first { $0 is NSSplitView })
            XCTAssertLessThanOrEqual(h.windowRect(of: split).height, bounds.height + 1, "\(size)")
            XCTAssertFalse(h.allViews().contains { $0 is NSScrollView && h.windowRect(of: $0).minX > 250 && ($0 as? NSScrollView)?.hasVerticalScroller == true },
                           "Genel bakış kaydırma görünümü kullanmamalı (\(size))")
            h.close()
        }
    }

    private func fittingHeight(_ view: some View, width: CGFloat) -> CGFloat {
        let host = NSHostingView(rootView: view.frame(width: width))
        return host.fittingSize.height
    }

    static func sampleRows(count: Int) -> [LiveAppUsage] {
        let apps = ["/Applications/Safari.app", "/Applications/Google Chrome.app", "/Applications/Xcode.app",
                    "/System/Applications/Music.app", "/System/Applications/Mail.app", "/usr/libexec/nsurlsessiond",
                    "/System/Applications/Messages.app", "/System/Applications/Photos.app"]
        return (0..<count).map { i in
            let app = i < apps.count ? apps[i] : "/Applications/Uygulama \(i).app"
            return LiveAppUsage(app: app, down: UInt64(316_000_000 / (i + 1)), up: UInt64(4_000_000 / (i + 1)), rate: i < 3 ? UInt64(240_000 / (i + 1)) : 0)
        }
    }

    // MARK: Önizleme (yalnızca TEST_RUNNER_ADALMON_PREVIEW_DIR verilince)

    func testRenderOverviewPreviews() async throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaultSize = MainWindowController.defaultFrame(visible: NSRect(x: 0, y: 40, width: 1512, height: 880)).size
        let source = MainWindowDataSource.fixed(.sample, liveRows: Self.sampleRows(count: 20))
        for (size, tag) in [(defaultSize, "varsayilan"), (NSSize(width: 940, height: 600), "940")] {
            for dark in [false, true] {
                let h = MainWindowHarness(size: size, section: .overview, dark: dark, source: source)
                h.window.layoutIfNeeded()
                try await Task.sleep(for: .seconds(1.5))
                let url = dir.appending(path: "genel-bakis-\(tag)-\(dark ? "dark" : "light").png")
                try h.capture(to: url)
                print("OVERVIEW_PREVIEW \(url.path)")
                h.close()
            }
        }
        // CPU sekmesi (kaynak listesi) — sahte sıralama, gerçek kayda dokunmaz.
        let ranks = ["/Applications/Xcode.app", "/Applications/Safari.app", "/System/Applications/Mail.app", "/usr/bin/git"]
            .enumerated().map { ResourceRank(app: $0.element, value: Double(4 - $0.offset) * 4e10) }
        let router = SettingsRouter(isDockModeOn: { true })
        for dark in [false, true] {
            let list = OverviewResourceList(store: UsageStore(path: ":memory:"), metric: .cpu, maxRows: 6,
                                            header: AnyView(OverviewListHeader(tab: .constant(.cpu))), router: router, initialRanks: ranks)
                .padding(20)
                .frame(width: 760)
                .background(Color(nsColor: .windowBackgroundColor))
            try MenuBarSettingsSnapshotTestsAccess.snapshot(list, dark: dark, size: NSSize(width: 760, height: 230),
                                                            to: dir.appending(path: "genel-bakis-cpu-\(dark ? "dark" : "light").png"))
        }
    }
}
