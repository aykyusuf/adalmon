import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Yer kaplayanlar sihirbazı ekranları (karşılama, tarama, harita + seçim çubuğu, bitti) açık/koyu PNG olarak. Sahte tarayıcı ve
/// sahte ev klasörü; gerçek diske dokunmaz. Yalnızca ADALMON_PREVIEW_DIR (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class SpaceLensWizardPreviewTests: XCTestCase {
    private let home = "/Users/demo"

    /// Hazır ağacı döndüren tarayıcı.
    private struct StubScanner: SpaceTreeScanning {
        let scan: SpaceLensScan
        func scan(path: String, isCancelled: @escaping () -> Bool, progress: @escaping (Int, Int, String) -> Void) -> SpaceLensScan { scan }
    }

    private func node(_ name: String, _ kind: SpaceNode.Kind, _ mb: Double) -> SpaceNode {
        SpaceNode(path: home + "/" + name, kind: kind, bytes: UInt64(mb * 1_048_576))
    }

    private var rootNodes: [SpaceNode] {
        [node("Library", .folder, 41_000), node("Movies", .folder, 22_500), node("Developer", .folder, 18_200),
         node("Applications", .folder, 9_800), node("Documents", .folder, 6_400), node("Pictures", .folder, 5_100),
         node("backup.dmg", .file, 4_200), node("archive.zip", .file, 2_300), node("node_modules", .folder, 1_800),
         node("Music", .folder, 1_200), node("notes.txt", .file, 640), node("Projects", .folder, 520),
         node("Studio.app", .folder, 380), node("data.bin", .file, 150), node("misc", .folder, 90),
         node("Mail", .skipped(.fullDiskAccess), 0)]
    }

    private func makeModel() async -> SpaceLensModel {
        let dir = SpaceDir(nodes: rootNodes, otherBytes: 3_000_000, otherCount: 40)
        let scan = SpaceLensScan(root: home, dirs: [home: dir], state: .scanned)
        let model = SpaceLensModel(home: home, scanner: StubScanner(scan: scan),
                                   identity: { path in (dev: 1, ino: UInt64(abs(path.hashValue % 1_000_000))) })
        model.start(root: home)
        await model.waitUntilIdle()
        return model
    }

    private func render(_ section: SpaceLensSection, name: String, dark: Bool, dir: URL) async throws {
        let size = NSSize(width: 860, height: 780)
        let view = section
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
        try await Task.sleep(for: .seconds(1.0))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = dir.appending(path: "spacelens-\(name)-\(dark ? "dark" : "light").png")
        try png.write(to: url)
        print("SPACELENS_WIZARD_PREVIEW: \(url.path())")
        window.close()
    }

    func testRenderSpaceLensWizard() async throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for dark in [false, true] {
            try await render(SpaceLensSection(model: SpaceLensModel(home: home)), name: "w1-welcome", dark: dark, dir: dir)

            let scanning = SpaceLensModel(home: home)
            scanning.phase = .scanning
            scanning.progressText = "~ · Developer"
            scanning.progressFraction = 0.42
            try await render(SpaceLensSection(model: scanning), name: "w2-scanning", dark: dark, dir: dir)

            let explorer = await makeModel()
            try await render(SpaceLensSection(model: explorer), name: "w3-map", dark: dark, dir: dir)

            let selected = await makeModel()
            for name in ["Movies", "Developer", "backup.dmg"] {
                if let target = selected.nodes.first(where: { $0.name == name }) { selected.toggleMark(target) }
            }
            try await render(SpaceLensSection(model: selected), name: "w4-selected", dark: dark, dir: dir)

            let finished = await makeModel()
            for name in ["Movies", "Developer"] {
                if let target = finished.nodes.first(where: { $0.name == name }) { finished.toggleMark(target) }
            }
            let results = finished.candidates().map { CleanupResult(candidate: $0, outcome: .trashed(to: nil)) }
            finished.deleteFinished(results, mode: .trash)
            try await render(SpaceLensSection(model: finished, startDone: true), name: "w5-done", dark: dark, dir: dir)
        }
    }
}
