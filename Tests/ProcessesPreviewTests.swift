import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Süreçler sayfasını ekran dışında çizip PNG yazar (ADALMON_PREVIEW_DIR / TEST_RUNNER_ADALMON_PREVIEW_DIR) ve
/// gerçek klasör taramasının maliyetini ölçer (ADALMON_BENCH_SCAN=1). Varsayılan çalıştırmada ikisi de atlanır.
@MainActor
final class ProcessesPreviewTests: XCTestCase {
    func testRenderProcessesPages() async throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = FileManager.default.temporaryDirectory.appending(path: "prev-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let model = AppModel()
        let store = model.store
        let now = Date()
        let nowTs = Int(now.timeIntervalSince1970)
        let apps = ["/Applications/Safari.app", "/System/Applications/Mail.app", "/Applications/Xcode.app", "/usr/bin/git",
                    "/System/Applications/Music.app", ResourceKeys.system]
        for m in stride(from: 600, to: 0, by: -1) {
            var rows: [KeyedUsage] = []
            for (i, a) in apps.enumerated() {
                let wave = 1 + sin(Double(m) / (20 + Double(i) * 7))
                rows.append(KeyedUsage(key: a, usage: ResourceUsage(
                    cpuNs: UInt64(Double(8_000_000_000 - i * 1_000_000_000) * wave / 2), gpuNs: UInt64(Double(i) * 2e8 * wave),
                    writeBytes: UInt64(Double(i + 1) * 3e6 * wave), readBytes: 0, energyNj: UInt64(5e9 * wave), footprint: UInt64(2e9 / Double(i + 1)))))
            }
            await store.addResourceMinute(ts: nowTs / 60 * 60 - m * 60, rows: rows, freeBytes: UInt64(14e9 - Double(m) * 4e6))
        }
        await store.addFolderSnapshot(ts: nowTs - 7_200, entries: [
            FolderSnapshotEntry(path: NSHomeDirectory() + "/Library/Developer", depth: 0, bytes: 11_000_000_000),
            FolderSnapshotEntry(path: NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData", depth: 2, bytes: 3_000_000_000)])
        await store.addFolderSnapshot(ts: nowTs - 60, entries: [
            FolderSnapshotEntry(path: NSHomeDirectory() + "/Library/Developer", depth: 0, bytes: 13_000_000_000),
            FolderSnapshotEntry(path: NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData", depth: 2, bytes: 5_000_000_000),
            FolderSnapshotEntry(path: NSHomeDirectory() + "/Library/Caches/Homebrew", depth: 1, bytes: 800_000_000)])
        model.mainWindowVisible = true
        let size = NSSize(width: 1180, height: 760)
        try await render(ProcessLiveView(model: model).padding(24), name: "processes-live", dir: dir, size: size, wait: 4)
        try await render(ProcessHistoryView(store: store).padding(24), name: "processes-history", dir: dir, size: size, wait: 2)
        try await render(ProcessDiskView(model: model).padding(24), name: "processes-disk", dir: dir, size: NSSize(width: 1180, height: 1250), wait: 2)
        let router = SettingsRouter(isDockModeOn: { true })
        try await render(OverviewResourceCard(store: store, router: router).padding(24), name: "overview-resource-card", dir: dir,
                         size: NSSize(width: 900, height: 220), wait: 2)
        model.mainWindowVisible = false
    }

    func testBenchRealFolderScan() throws {
        guard ProcessInfo.processInfo.environment["ADALMON_BENCH_SCAN"] == "1" else { throw XCTSkip("ADALMON_BENCH_SCAN=1 değil") }
        var perRoot: [String] = []
        let cpu0 = clock()
        let wall0 = DispatchTime.now().uptimeNanoseconds
        var entries = 0
        for root in FolderWatchList.roots() {
            let c = clock(), w = DispatchTime.now().uptimeNanoseconds
            if let r = FolderScanner.scan(root: root) {
                entries += r.entries.count
                perRoot.append("\(FolderWatchList.displayPath(root.path)): \(r.totalBytes / 1_048_576) MB, \(r.files) files, \(r.unreadableDirs) unreadable, cpu \(Double(clock() - c) / Double(CLOCKS_PER_SEC)) s, wall \(Double(DispatchTime.now().uptimeNanoseconds - w) / 1e9) s")
            }
        }
        let cpu = Double(clock() - cpu0) / Double(CLOCKS_PER_SEC)
        let wall = Double(DispatchTime.now().uptimeNanoseconds - wall0) / 1e9
        print("SCAN_BENCH total cpu \(cpu) s wall \(wall) s entries \(entries) => hourly avg CPU \(cpu / 3600 * 100)%")
        for l in perRoot { print("SCAN_BENCH_ROOT", l) }
    }

    private func render<V: View>(_ view: V, name: String, dir: URL, size: NSSize, wait: Double) async throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -3000, y: -3000), size: size),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(wait))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: dir.appending(path: "\(name).png"))
        window.close()
    }
}
