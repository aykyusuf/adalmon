import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Kaldırıcı, Büyük & eski ve Kopyalar sihirbazı ekranları (karşılama, tarama, sonuç, bitti, boş) açık/koyu PNG olarak.
/// Sahte uygulama listesi ve geçici sahte ev klasörü; gerçek diske, Çöp'e ya da kullanıcı dosyalarına dokunmaz.
/// Yalnızca ADALMON_PREVIEW_DIR (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class CleanupFilesAppsPreviewTests: XCTestCase {
    private var fixture: URL!
    private var home: String { fixture.path }

    override func setUpWithError() throws {
        // Gerçek yol (/private/var…): tarayıcı gerçek yolları döndürür, "~" kısaltması ancak böyle eşleşir.
        let base = FileManager.default.temporaryDirectory
        let real = CleanupDeleter.realPath(base.path) ?? base.path
        fixture = URL(filePath: real, directoryHint: .isDirectory)
            .appending(path: "cleanup-preview-\(UUID().uuidString)", directoryHint: .isDirectory)
        for folder in ["Downloads", "Documents", "Desktop"] {
            try FileManager.default.createDirectory(at: fixture.appending(path: folder), withIntermediateDirectories: true)
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fixture)
    }

    private func previewDir() throws -> URL {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func render<V: View>(_ content: V, name: String, dark: Bool, dir: URL, width: CGFloat = 820, height: CGFloat = 760) async throws {
        let size = NSSize(width: width, height: height)
        let view = content
            .padding(24)
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .preferredColorScheme(dark ? .dark : .light)
            // Offscreen anlık görüntü 3D katmanları çizemez; hareketsiz (sabit) hâl çizilir.
            .environment(\.cleanupStaticArtwork, true)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(1.3))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = dir.appending(path: "\(name)-\(dark ? "dark" : "light").png")
        try png.write(to: url)
        print("CLEANUP_FILESAPPS_PREVIEW: \(url.path())")
        window.close()
    }

    // MARK: Kaldırıcı

    private func leftover(_ rel: String, mb: Double, kind: LeftoverLocation, name: String) -> DeletionCandidate {
        DeletionCandidate(path: home + "/Library/" + rel, dev: 1, ino: UInt64(abs(rel.hashValue % 1_000_000)), bytes: UInt64(mb * 1_048_576),
                          kind: kind.kind, scope: .descendant(roots: [home], nameAllowlist: nil), displayName: name)
    }

    private func app(_ name: String, system: String, id: String, mb: Double, version: String, store: Bool = false, root: Bool = false,
                     leftovers: [DeletionCandidate] = []) -> InstalledApp {
        InstalledApp(path: "/System/Applications/\(system).app", dev: 1, ino: UInt64(abs(id.hashValue % 1_000_000)), bundleID: id, name: name,
                     names: [name], version: version, bytes: UInt64(mb * 1_048_576), isAppStore: store, ownerIsRoot: root, leftovers: leftovers)
    }

    private func sampleApps() -> [InstalledApp] {
        [
            app("Figma", system: "Notes", id: "com.figma.Desktop", mb: 540, version: "124.1", leftovers: [
                leftover("Application Support/Figma", mb: 1_240, kind: .applicationSupport, name: "Figma"),
                leftover("Caches/com.figma.Desktop", mb: 880, kind: .caches, name: "com.figma.Desktop"),
                leftover("Preferences/com.figma.Desktop.plist", mb: 0.1, kind: .preferences, name: "com.figma.Desktop.plist"),
                leftover("Logs/Figma", mb: 12, kind: .logs, name: "Figma"),
            ]),
            app("Spotify", system: "Music", id: "com.spotify.client", mb: 310, version: "1.2.52", leftovers: [
                leftover("Caches/com.spotify.client", mb: 2_400, kind: .caches, name: "com.spotify.client"),
                leftover("Application Support/Spotify", mb: 95, kind: .applicationSupport, name: "Spotify"),
            ]),
            app("Slack", system: "Mail", id: "com.tinyspeck.slackmacgap", mb: 420, version: "4.39", leftovers: [
                leftover("Application Support/Slack", mb: 610, kind: .applicationSupport, name: "Slack"),
            ]),
            app("Keynote", system: "Calendar", id: "com.apple.iWork.Keynote.demo", mb: 1_200, version: "14.0", store: true),
            app("Little Snitch", system: "Maps", id: "at.obdev.littlesnitch", mb: 64, version: "6.1", root: true),
        ]
    }

    private func makeUninstaller(scanned: Bool = true, tab: UninstallerModel.Tab = .apps) -> UninstallerModel {
        let model = UninstallerModel(home: home)
        model.runningProvider = { ["com.tinyspeck.slackmacgap"] }
        if scanned {
            let orphans = [
                OrphanGroup(bundleID: "com.oldvendor.Editor", items: [
                    leftover("Application Support/OldEditor", mb: 340, kind: .applicationSupport, name: "OldEditor"),
                    leftover("Caches/com.oldvendor.Editor", mb: 120, kind: .caches, name: "com.oldvendor.Editor"),
                ]),
                OrphanGroup(bundleID: "org.example.Burner", items: [
                    leftover("Containers/org.example.Burner", mb: 56, kind: .containers, name: "org.example.Burner"),
                ]),
            ]
            model.apply(AppScanOutput(apps: sampleApps(), orphans: orphans))
        }
        model.tab = tab
        return model
    }

    func testRenderUninstallerStates() async throws {
        let dir = try previewDir()
        for dark in [false, true] {
            try await render(UninstallerSection(model: makeUninstaller(scanned: false)), name: "uninstaller-1-welcome", dark: dark, dir: dir)

            let scanning = makeUninstaller(scanned: false)
            scanning.showScanningForPreview(done: 38, total: 91)
            try await render(UninstallerSection(model: scanning), name: "uninstaller-2-scanning", dark: dark, dir: dir)

            try await render(UninstallerSection(model: makeUninstaller()), name: "uninstaller-3-result-apps", dark: dark, dir: dir)

            // Çalışan uygulama seçili: kart uyarı gösterir, Kaldır kapalıdır.
            let running = makeUninstaller()
            running.select(running.apps.first { $0.name == "Slack" })
            try await render(UninstallerSection(model: running), name: "uninstaller-3b-result-running", dark: dark, dir: dir)

            // App Store uygulaması seçili: yalnızca Finder'da göster.
            let store = makeUninstaller()
            store.select(store.apps.first { $0.name == "Keynote" })
            try await render(UninstallerSection(model: store), name: "uninstaller-3c-result-appstore", dark: dark, dir: dir)

            try await render(UninstallerSection(model: makeUninstaller(tab: .orphans)), name: "uninstaller-4-result-orphans", dark: dark, dir: dir)
            try await render(UninstallerSection(model: makeUninstaller(tab: .orphans)), name: "uninstaller-4n-result-narrow", dark: dark, dir: dir,
                             width: 540, height: 700)

            let finished = makeUninstaller()
            let figma = try XCTUnwrap(finished.apps.first { $0.name == "Figma" })
            let candidates = [figma.bundleCandidate] + figma.leftovers
            let report = AppRemovalReport(results: candidates.map { CleanupResult(candidate: $0, outcome: .trashed(to: nil)) }, accessFailures: [:])
            finished.finish(report, pending: PendingRemoval(app: figma, leftovers: figma.leftovers), mode: .trash)
            try await render(UninstallerSection(model: finished, startDone: true), name: "uninstaller-5-done", dark: dark, dir: dir)

            let empty = makeUninstaller(scanned: false)
            empty.apply(AppScanOutput(apps: sampleApps(), orphans: []))
            empty.tab = .orphans
            try await render(UninstallerSection(model: empty), name: "uninstaller-6-no-orphans", dark: dark, dir: dir)
        }
    }

    // MARK: Büyük & eski + Kopyalar (geçici sahte ev klasörü)

    private func write(_ rel: String, mb: Double, fill: UInt8, daysAgo: Double) throws {
        let url = fixture.appending(path: rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: fill, count: Int(mb * 1_048_576)).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-daysAgo * 86_400)], ofItemAtPath: url.path)
    }

    private func makeStore() -> FileRootsStore {
        FileRootsStore(home: home, defaults: UserDefaults(suiteName: "cleanup-files-preview-\(UUID().uuidString)")!)
    }

    private func waitIdle(_ isBusy: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where isBusy() { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(isBusy(), "tarama zaman aşımına uğradı")
    }

    private func makeLargeOld(populated: Bool = true) async throws -> LargeOldModel {
        if populated {
            try write("Downloads/Ubuntu-24.04-desktop.iso", mb: 9.5, fill: 1, daysAgo: 420)
            try write("Documents/Projects/demo-reel-final.mov", mb: 7.2, fill: 2, daysAgo: 800)
            try write("Downloads/Xcode-backup.xip", mb: 5.4, fill: 3, daysAgo: 200)
            try write("Desktop/Screen Recording 2025-03-02.mov", mb: 3.8, fill: 4, daysAgo: 300)
            try write("Documents/Archive/photos-2019.zip", mb: 2.6, fill: 5, daysAgo: 1_100)
            try write("Downloads/conference-talk.pdf", mb: 1.4, fill: 6, daysAgo: 12)
        }
        let model = LargeOldModel(home: home, rootsStore: makeStore())
        model.minBytes = 1 << 20
        model.scan()
        try await waitIdle { model.isBusy }
        return model
    }

    func testRenderLargeOldStates() async throws {
        let dir = try previewDir()
        let model = try await makeLargeOld()
        XCTAssertTrue(model.hasScanned)
        XCTAssertEqual(model.items.count, 6)
        for dark in [false, true] {
            try await render(LargeOldSection(model: LargeOldModel(home: home, rootsStore: makeStore())), name: "largeold-1-welcome", dark: dark, dir: dir)

            let scanning = LargeOldModel(home: home, rootsStore: makeStore())
            scanning.phase = .scanning
            scanning.progressText = "1.284 dosya · ~/Documents/Projects"
            try await render(LargeOldSection(model: scanning), name: "largeold-2-scanning", dark: dark, dir: dir)

            model.selection = Set(model.items.prefix(2).map(\.id))
            model.onlyOld = false
            try await render(LargeOldSection(model: model), name: "largeold-3-result", dark: dark, dir: dir)
            try await render(LargeOldSection(model: model), name: "largeold-3n-result-narrow", dark: dark, dir: dir, width: 540, height: 700)

            model.onlyOld = true
            model.oldDays = 365
            try await render(LargeOldSection(model: model), name: "largeold-3b-result-onlyold", dark: dark, dir: dir)
            model.onlyOld = false

            let results = model.items.prefix(2).map { CleanupResult(candidate: $0.candidate(roots: [home]), outcome: .trashed(to: nil)) }
            model.lastResult = Array(results)
            model.lastMode = .trash
            try await render(LargeOldSection(model: model, startDone: true), name: "largeold-4-done", dark: dark, dir: dir)
            model.lastResult = nil
        }
    }

    func testRenderLargeOldEmpty() async throws {
        let dir = try previewDir()
        let model = try await makeLargeOld(populated: false)
        XCTAssertTrue(model.hasScanned)
        for dark in [false, true] {
            try await render(LargeOldSection(model: model), name: "largeold-5-empty", dark: dark, dir: dir)
        }
    }

    private func makeDuplicates(populated: Bool = true) async throws -> DuplicatesModel {
        if populated {
            for (rel, daysAgo) in [("Documents/Taxes/report-final.pdf", 400.0), ("Downloads/report-final.pdf", 30), ("Desktop/report-final (1).pdf", 5)] {
                try write(rel, mb: 3.1, fill: 11, daysAgo: daysAgo)
            }
            for (rel, daysAgo) in [("Documents/Trips/holiday.mov", 700.0), ("Downloads/holiday.mov", 90)] {
                try write(rel, mb: 6.4, fill: 12, daysAgo: daysAgo)
            }
            for (rel, daysAgo) in [("Downloads/installer.dmg", 60.0), ("Desktop/installer.dmg", 59)] {
                try write(rel, mb: 2.2, fill: 13, daysAgo: daysAgo)
            }
        }
        let model = DuplicatesModel(home: home, rootsStore: makeStore())
        model.minBytes = 1 << 20
        model.scan()
        try await waitIdle { model.isBusy }
        return model
    }

    func testRenderDuplicatesStates() async throws {
        let dir = try previewDir()
        let model = try await makeDuplicates()
        XCTAssertTrue(model.hasScanned)
        XCTAssertEqual(model.groups.count, 3)
        for dark in [false, true] {
            try await render(DuplicatesSection(model: DuplicatesModel(home: home, rootsStore: makeStore())), name: "duplicates-1-welcome", dark: dark, dir: dir)

            let scanning = DuplicatesModel(home: home, rootsStore: makeStore())
            scanning.phase = .scanning
            scanning.progressText = "Tam içerik karşılaştırılıyor (4/9) · holiday.mov"
            scanning.progressFraction = 0.44
            try await render(DuplicatesSection(model: scanning), name: "duplicates-2-scanning", dark: dark, dir: dir)

            model.clearSelection()
            try await render(DuplicatesSection(model: model), name: "duplicates-3-result", dark: dark, dir: dir)

            model.selectAllButKeepers()
            let first = try XCTUnwrap(model.groups.first)
            try await render(DuplicatesSection(model: model, expanded: [first.id]), name: "duplicates-3b-result-expanded", dark: dark, dir: dir)
            try await render(DuplicatesSection(model: model, expanded: [first.id]), name: "duplicates-3n-result-narrow", dark: dark, dir: dir,
                             width: 540, height: 700)

            let results = model.selectedFiles.map { CleanupResult(candidate: $0.candidate(roots: [home]), outcome: .trashed(to: nil)) }
            model.lastResult = results
            model.lastMode = .trash
            try await render(DuplicatesSection(model: model, startDone: true), name: "duplicates-4-done", dark: dark, dir: dir)
            model.lastResult = nil
            model.clearSelection()
        }
    }

    func testRenderDuplicatesEmpty() async throws {
        let dir = try previewDir()
        let model = try await makeDuplicates(populated: false)
        XCTAssertTrue(model.hasScanned)
        for dark in [false, true] {
            try await render(DuplicatesSection(model: model), name: "duplicates-5-empty", dark: dark, dir: dir)
        }
    }

    // MARK: Davranış (önizlemeden bağımsız)

    /// Kopyalar kartının onay kutusu korunan dosyayı asla seçmez; grubun hepsi seçilemez.
    func testDuplicatesGroupSelectionNeverIncludesKeeper() async throws {
        let model = try await makeDuplicates()
        for group in model.groups {
            let keeper = model.selection.keeper(of: group)
            model.selectAllButKeepers()
            XCTAssertFalse(model.selection.isSelected(keeper))
            XCTAssertEqual(model.selectedFiles.filter { selected in group.files.contains(selected) }.count, group.files.count - 1)
        }
    }
}
