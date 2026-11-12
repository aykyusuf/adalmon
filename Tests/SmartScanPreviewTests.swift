import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Akıllı tarama ekranları (boş, tarama sürüyor, sonuç) açık/koyu PNG olarak. Sahte veriyle; gerçek diske dokunmaz.
/// Yalnızca ADALMON_PREVIEW_DIR (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class SmartScanPreviewTests: XCTestCase {
    private let home = "/Users/demo"
    private let now = Date()

    private func item(_ path: String, _ category: CleanupCategory, mb: Int, daysAgo: Double, root: String, blocked: String? = nil) -> CleanupItem {
        CleanupItem(path: path, rootPath: root, category: category, bytes: UInt64(mb) << 20, isDirectory: true,
                    modified: now.addingTimeInterval(-daysAgo * 86_400), dev: 1, ino: UInt64(abs(path.hashValue % 100_000)),
                    blockedReason: blocked)
    }

    private func sampleResult() -> SmartScanResult {
        var r = SmartScanResult()
        func add(_ s: SmartScanStepResult) { r.results[s.step] = s; r.completed.append(s.step) }
        add(SmartScanStepResult(step: .appCaches, state: .scanned, items: [
            item(home + "/Library/Caches/com.spotify.client", .appCaches, mb: 2_400, daysAgo: 1, root: home + "/Library/Caches"),
            item(home + "/Library/Caches/com.figma.Desktop", .appCaches, mb: 900, daysAgo: 1, root: home + "/Library/Caches"),
            item(home + "/Library/Caches/com.slack.Slack", .appCaches, mb: 410, daysAgo: 1, root: home + "/Library/Caches", blocked: "Açık"),
        ]))
        add(SmartScanStepResult(step: .logs, state: .scanned, items: [item(home + "/Library/Logs/Zed", .logs, mb: 310, daysAgo: 2, root: home + "/Library/Logs")]))
        add(SmartScanStepResult(step: .browserCaches, state: .scanned, items: [
            item(home + "/Library/Caches/Google/Chrome/Default", .browserCaches, mb: 1_300, daysAgo: 0, root: home + "/Library/Caches/Google/Chrome"),
        ]))
        add(SmartScanStepResult(step: .devCaches, state: .scanned, items: [
            item(home + "/Library/Developer/Xcode/DerivedData/Adalmon-abc", .derivedData, mb: 8_200, daysAgo: 1, root: home + "/Library/Developer/Xcode/DerivedData"),
            item(home + "/Library/Developer/CoreSimulator/Caches/dyld", .simCaches, mb: 3_100, daysAgo: 20, root: home + "/Library/Developer/CoreSimulator/Caches"),
            item(home + "/.npm/_cacache", .pkgCaches, mb: 1_900, daysAgo: 4, root: home + "/.npm"),
        ]))
        add(SmartScanStepResult(step: .projectArtifacts, state: .scanned, items: [
            item(home + "/Developer/old-shop/node_modules", .projectArtifacts, mb: 1_450, daysAgo: 160, root: home + "/Developer"),
            item(home + "/Developer/ios-demo/.build", .projectArtifacts, mb: 2_050, daysAgo: 75, root: home + "/Developer"),
            item(home + "/Documents/GitHub/blog/node_modules", .projectArtifacts, mb: 880, daysAgo: 6, root: home + "/Documents"),
            item(home + "/Desktop/rust-toy/target", .projectArtifacts, mb: 3_300, daysAgo: 240, root: home + "/Desktop"),
        ], rootStates: [home + "/Developer": .scanned, home + "/Documents": .scanned, home + "/Desktop": .noAccess]))
        add(SmartScanStepResult(step: .trash, state: .scanned, trashBytes: 4_200 << 20))
        add(SmartScanStepResult(step: .largeFiles, state: .scanned, reviewCount: 5, reviewBytes: 9_800 << 20))
        add(SmartScanStepResult(step: .orphans, state: .scanned, reviewCount: 7, reviewBytes: 640 << 20))
        return r
    }

    private func render(_ model: SmartScanModel, name: String, dark: Bool, dir: URL, startDone: Bool = false) throws {
        let view = SmartScanSection(model: model, startDone: startDone)
            .padding(24)
            .frame(width: 820, height: 760)
            .background(Color(nsColor: .windowBackgroundColor))
            .preferredColorScheme(dark ? .dark : .light)
            // Offscreen anlık görüntü 3D katmanları çizemez; hareketsiz (sabit) hâl çizilir.
            .environment(\.cleanupStaticArtwork, true)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 820, height: 760),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        // Kahraman giriş animasyonu (~1 sn) ve sayaç animasyonu bitsin.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.6))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = dir.appending(path: "smartscan-\(name)-\(dark ? "dark" : "light").png")
        try png.write(to: url)
        print("SMARTSCAN_PREVIEW: \(url.path())")
        window.close()
    }

    func testRenderSmartScanStates() throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "smartscan-preview-\(UUID().uuidString)")!
        func makeModel() -> SmartScanModel { SmartScanModel(home: home, folderStore: ProjectFoldersStore(defaults: defaults, home: home)) }

        for dark in [false, true] {
            try render(makeModel(), name: "1-welcome", dark: dark, dir: dir)

            let scanning = makeModel()
            let full = sampleResult()
            for step in SmartScanStep.allCases.prefix(4) {
                scanning.result.results[step] = full.results[step]
                scanning.result.completed.append(step)
            }
            scanning.phase = .scanning
            scanning.currentStep = .projectArtifacts
            scanning.currentDetail = "Documents"
            try render(scanning, name: "2-scanning", dark: dark, dir: dir)

            let done = makeModel()
            done.adopt(full, now: now)
            done.expanded = [.projectArtifacts]
            try render(done, name: "3-result", dark: dark, dir: dir)

            let finished = makeModel()
            finished.adopt(full, now: now)
            let freed = finished.selectedItems.map { item in
                CleanupResult(candidate: DeletionCandidate(item: item, roots: []), outcome: .trashed(to: nil))
            }
            finished.lastResult = freed
            finished.lastMode = .trash
            try render(finished, name: "4-done", dark: dark, dir: dir, startDone: true)

            let clean = makeModel()
            var empty = SmartScanResult()
            for step in SmartScanStep.allCases.filter(\.isCleanable) {
                empty.results[step] = SmartScanStepResult(step: step, state: .scanned)
                empty.completed.append(step)
            }
            clean.adopt(empty, now: now)
            try render(clean, name: "5-allclean", dark: dark, dir: dir)
        }
    }
}
