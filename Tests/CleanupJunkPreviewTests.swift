import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Sistem çöpü ve Geliştirici sihirbazı (karşılama, tarama, sonuç, bitti, her şey temiz) açık/koyu PNG olarak.
/// Sahte veri, sahte evde ve sahte araç çalıştırıcısıyla; gerçek diske, brew'a ya da Docker'a dokunmaz.
/// Yalnızca ADALMON_PREVIEW_DIR (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class CleanupJunkPreviewTests: XCTestCase {
    private var home = ""
    private let now = Date()

    private func item(_ rel: String, _ category: CleanupCategory, mb: Int, daysAgo: Double, root: String, blocked: String? = nil) -> CleanupItem {
        CleanupItem(path: home + rel, rootPath: home + root, category: category, bytes: UInt64(mb) << 20, isDirectory: true,
                    modified: now.addingTimeInterval(-daysAgo * 86_400), dev: 1, ino: UInt64(abs(rel.hashValue % 100_000)),
                    blockedReason: blocked)
    }

    private func makeModel(_ group: CleanupGroup, scanned: Bool, withFolder: Bool = false) throws -> CleanupViewModel {
        let defaults = UserDefaults(suiteName: "cleanup-preview-\(UUID().uuidString)")!
        let store = ProjectFoldersStore(defaults: defaults, home: home)
        let vm = CleanupViewModel(home: home, probe: PathProbe { _ in .ok }, folderStore: store)
        if withFolder {
            let folder = home + "/Developer"
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            XCTAssertNil(vm.addProjectFolder(folder))
        }
        if scanned {
            vm.scannedCategories = Set(group.scanCategories)
            for root in CleanupCatalog.roots(home: home) where group.categories.contains(root.category) { vm.rootStates[root.path] = .scanned }
        }
        return vm
    }

    private func junkModel(clean: Bool = false) throws -> CleanupViewModel {
        let vm = try makeModel(.junk, scanned: true)
        vm.trashState = (.scanned, 4_200 << 20)
        if clean { return vm }
        vm.items = [
            item("/Library/Caches/com.spotify.client", .appCaches, mb: 2_400, daysAgo: 1, root: "/Library/Caches"),
            item("/Library/Caches/com.figma.Desktop", .appCaches, mb: 900, daysAgo: 1, root: "/Library/Caches"),
            item("/Library/Caches/com.linear.app", .appCaches, mb: 410, daysAgo: 3, root: "/Library/Caches"),
            item("/Library/Caches/Google/Chrome/Default", .browserCaches, mb: 1_300, daysAgo: 0, root: "/Library/Caches/Google/Chrome", blocked: "Açık"),
            item("/Library/Logs/Zed", .logs, mb: 310, daysAgo: 2, root: "/Library/Logs"),
            item("/Library/Logs/DiagnosticReports", .logs, mb: 120, daysAgo: 9, root: "/Library/Logs"),
            item("/Downloads/Xcode_26.xip", .downloads, mb: 3_400, daysAgo: 60, root: "/Downloads"),
        ]
        vm.scannedCategories.insert(.downloads)
        let backup = home + "/Library/Application Support/MobileSync/Backup"
        vm.rootStates[backup] = .noAccess
        vm.access.update(states: [backup: .noAccess])
        vm.selection = Set(vm.items.filter { $0.category.defaultSelected && $0.blockedReason == nil }.map(\.id))
        return vm
    }

    private func devModel(clean: Bool = false) throws -> CleanupViewModel {
        let vm = try makeModel(.dev, scanned: true, withFolder: true)
        if clean { return vm }
        vm.items = [
            item("/Library/Developer/Xcode/DerivedData/Adalmon-abc", .derivedData, mb: 8_200, daysAgo: 1, root: "/Library/Developer/Xcode/DerivedData"),
            item("/Library/Developer/Xcode/DerivedData/Stage-def", .derivedData, mb: 2_100, daysAgo: 12, root: "/Library/Developer/Xcode/DerivedData"),
            item("/Library/Developer/Xcode/Archives/2026-10-01", .archives, mb: 640, daysAgo: 40, root: "/Library/Developer/Xcode/Archives"),
            item("/Library/Developer/Xcode/iOS DeviceSupport/18.2", .deviceSupport, mb: 5_600, daysAgo: 70, root: "/Library/Developer/Xcode/iOS DeviceSupport"),
            item("/Library/Developer/CoreSimulator/Caches/dyld", .simCaches, mb: 3_100, daysAgo: 20, root: "/Library/Developer/CoreSimulator/Caches"),
            item("/.npm/_cacache", .pkgCaches, mb: 1_900, daysAgo: 4, root: "/.npm"),
            item("/Library/Caches/Homebrew", .pkgCaches, mb: 780, daysAgo: 4, root: "/Library/Caches/Homebrew"),
            item("/Developer/old-shop/node_modules", .projectArtifacts, mb: 1_450, daysAgo: 160, root: "/Developer"),
            item("/Developer/ios-demo/.build", .projectArtifacts, mb: 2_050, daysAgo: 75, root: "/Developer"),
        ]
        vm.scannedCategories.insert(.projectArtifacts)
        vm.selection = Set(vm.items.filter { $0.category.defaultSelected && $0.blockedReason == nil }.map(\.id))
        return vm
    }

    private func toolModels() async -> [ToolCommandModel] {
        let runner = CleanupToolRunner(
            run: { _, arguments, _ in
                if arguments.first == "cleanup" {
                    return CommandResult(status: 0, output: "Removing: /opt/homebrew/Cellar/node/22.1.0...\nRemoving: /Users/demo/Library/Caches/Homebrew/node--22.1.0...\n==> This operation would free approximately 1.2GB of disk space.")
                }
                return CommandResult(status: 0, output: "TYPE TOTAL ACTIVE SIZE RECLAIMABLE\nImages 4 2 1.9GB 800MB (42%)\nBuild Cache 31 0 3.2GB 3.2GB")
            },
            isExecutable: { _ in true }
        )
        var models: [ToolCommandModel] = []
        for tool in CleanupTool.allCases {
            let model = ToolCommandModel(tool: tool, home: home, runner: runner)
            model.locate()
            if tool == .brew { await model.loadPreview() }
            models.append(model)
        }
        return models
    }

    private func finished(_ vm: CleanupViewModel) {
        vm.lastResult = vm.selectedItems.map { CleanupResult(candidate: DeletionCandidate(item: $0, roots: []), outcome: .trashed(to: nil)) }
        vm.lastMode = .trash
    }

    private func render<V: View>(_ view: V, name: String, dark: Bool, dir: URL, height: CGFloat = 760) throws {
        let framed = view
            .padding(24)
            .frame(width: 820, height: height)
            .background(Color(nsColor: .windowBackgroundColor))
            .preferredColorScheme(dark ? .dark : .light)
            // Offscreen anlık görüntü 3D katmanları çizemez; hareketsiz (sabit) hâl çizilir.
            .environment(\.cleanupStaticArtwork, true)
        let host = NSHostingView(rootView: framed)
        let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 820, height: height),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.6))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = dir.appending(path: "\(name)-\(dark ? "dark" : "light").png")
        try png.write(to: url)
        print("CLEANUP_PREVIEW: \(url.path())")
        window.close()
    }

    func testRenderJunkAndDevStates() async throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        home = FileManager.default.temporaryDirectory.appending(path: "cleanup-preview-\(UUID().uuidString)", directoryHint: .isDirectory).path
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }
        let tools = await toolModels()

        for dark in [false, true] {
            // Sistem çöpü
            try render(CleanupView(group: .junk, model: try makeModel(.junk, scanned: false)), name: "junk-1-welcome", dark: dark, dir: dir)
            let junkScan = try makeModel(.junk, scanned: false)
            junkScan.phase = .scanning(.browserCaches)
            try render(CleanupView(group: .junk, model: junkScan), name: "junk-2-scanning", dark: dark, dir: dir)
            try render(CleanupView(group: .junk, model: try junkModel()), name: "junk-3-result", dark: dark, dir: dir, height: 1_000)
            let junkDone = try junkModel()
            finished(junkDone)
            try render(CleanupView(group: .junk, model: junkDone, startDone: true), name: "junk-4-done", dark: dark, dir: dir)
            try render(CleanupView(group: .junk, model: try junkModel(clean: true)), name: "junk-5-allclean", dark: dark, dir: dir)

            // Geliştirici
            try render(CleanupView(group: .dev, model: try makeModel(.dev, scanned: false)), name: "dev-1-welcome", dark: dark, dir: dir)
            let devScan = try makeModel(.dev, scanned: false)
            devScan.phase = .scanning(.simCaches)
            try render(CleanupView(group: .dev, model: devScan), name: "dev-2-scanning", dark: dark, dir: dir)
            try render(CleanupView(group: .dev, model: try devModel(), toolModels: tools), name: "dev-3-result", dark: dark, dir: dir, height: 1_100)
            let devDone = try devModel()
            finished(devDone)
            try render(CleanupView(group: .dev, model: devDone, startDone: true), name: "dev-4-done", dark: dark, dir: dir)
            try render(CleanupView(group: .dev, model: try devModel(clean: true), toolModels: tools), name: "dev-5-allclean", dark: dark, dir: dir, height: 900)
        }
    }

    /// Adım seçimi: varsayılan seçimler ve engeller görünümden bağımsızdır; burada yalnızca modelin sihirbaza verdiği durum denetlenir.
    func testViewModelStateFeedsWizard() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "cleanup-preview-\(UUID().uuidString)", directoryHint: .isDirectory).path
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }
        let vm = try junkModel()
        XCTAssertFalse(vm.scannedCategories.isDisjoint(with: CleanupGroup.junk.scanCategories))
        XCTAssertTrue(vm.selectedItems.allSatisfy { $0.blockedReason == nil && $0.category.defaultSelected })
        XCTAssertFalse(vm.selectedItems.contains { $0.category == .browserCaches }, "açık tarayıcının önbelleği seçilemez")
        XCTAssertFalse(vm.selectedItems.contains { $0.category == .downloads }, "İndirilenler kendiliğinden seçilmez")
        XCTAssertFalse(vm.access.blocked.isEmpty)
    }
}
