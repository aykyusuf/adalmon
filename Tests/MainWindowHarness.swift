import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Gerçek (araç çubuklu, NSHostingController'lı) ana pencere: sayfa düzeni testleri ve önizlemeler için ortak kurulum.
@MainActor
struct MainWindowHarness {
    let window: NSWindow
    let hosting: NSHostingController<AnyView>
    let model: AppModel
    let router: SettingsRouter

    /// `chartHover`: grafiklerde sanki imleç çizim alanının bu oranında (0...1) duruyormuş gibi ipucu gösterir (önizleme).
    init(size: NSSize, section: MainSection, dark: Bool = true, model: AppModel = AppModel(), chartHover: Double? = nil,
         source: MainWindowDataSource = .fixed(.sample)) {
        model.mainWindowVisible = true
        let router = SettingsRouter(isDockModeOn: { true })
        router.selectedMainSection = section
        let view = MainWindowView(model: model, source: source, actions: .inert, router: router) { settings in
            SettingsDetailView(section: settings, model: model)
        }
        let hosting = NSHostingController(rootView: AnyView(view.environment(\.chartPreviewHover, chartHover)))
        hosting.sizingOptions = [.minSize]
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 40, y: 60), size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Adalmon"
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 940, height: 600)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        window.setContentSize(size)
        self.window = window
        self.hosting = hosting
        self.model = model
        self.router = router
    }

    func show() { window.makeKeyAndOrderFront(nil) }

    /// Önizleme için gerçek sistem ölçümleri yayınlar (AppModel zamanlayıcısı testte çalışmaz). Pencereden ÖNCE çağrılmalı:
    /// Performans sekmesi açılırken `AppModel` geçmişiyle tohumlanır.
    static func feedSnapshots(into model: AppModel, count: Int = 14) async throws {
        let sampler = MetricsSampler()
        _ = sampler.sample()
        for _ in 0..<count {
            try await Task.sleep(for: .milliseconds(300))
            model.apply(sampler.sample())
        }
    }

    /// Önizleme için son 10 dakikalık sentetik sistem geçmişi (gerçek örneklerden ÖNCE çağrılmalı: tampon zamanla artan yazar).
    static func seedSystemHistory(into model: AppModel, seconds: Int = 600, step: Int = 2) {
        let now = Date.now.addingTimeInterval(-30)
        for i in stride(from: seconds, to: 0, by: -step) {
            let t = Double(i)
            let wave = 0.5 + 0.5 * sin(t / 37)
            let sample = SystemSample(time: now.addingTimeInterval(-t), cpu: 0.12 + 0.3 * wave * (0.6 + 0.4 * sin(t / 9)), memory: 0.58 + 0.04 * sin(t / 120),
                                      gpu: 0.05 + 0.2 * max(0, sin(t / 55)), diskRead: 2e6 * (1 + sin(t / 17)) * wave, diskWrite: 6e6 * (1 + sin(t / 23)),
                                      down: 1.2e6 * (1 + sin(t / 31)) * wave, up: 2e5 * (1 + sin(t / 13)))
            model.systemHistory.append(sample, notify: false)
        }
    }

    /// Önizleme için 10 saatlik dakikalık kaynak kaydı ve iki klasör anlık görüntüsü.
    static func seedResourceHistory(into store: UsageStore) async {
        let nowTs = Int(Date().timeIntervalSince1970)
        let apps = ["/Applications/Safari.app", "/System/Applications/Mail.app", "/Applications/Xcode.app", "/usr/bin/git",
                    "/System/Applications/Music.app", ResourceKeys.system]
        for m in stride(from: 600, to: 0, by: -1) {
            var rows: [KeyedUsage] = []
            for (i, a) in apps.enumerated() {
                let wave = 1 + sin(Double(m) / (20 + Double(i) * 7))
                rows.append(KeyedUsage(key: a, usage: ResourceUsage(
                    cpuNs: UInt64(Double(8_000_000_000 - i * 1_000_000_000) * wave / 2), gpuNs: UInt64(Double(i) * 2e8 * wave),
                    writeBytes: UInt64(Double(i + 1) * 3e6 * wave), readBytes: UInt64(Double(i + 1) * 1e6 * wave),
                    energyNj: UInt64(5e9 * wave), footprint: UInt64(2e9 / Double(i + 1)))))
            }
            await store.addResourceMinute(ts: nowTs / 60 * 60 - m * 60, rows: rows, freeBytes: UInt64(14e9 - Double(m) * 4e6))
        }
        await store.addFolderSnapshot(ts: nowTs - 7_200, entries: [
            FolderSnapshotEntry(path: NSHomeDirectory() + "/Library/Developer", depth: 0, bytes: 11_000_000_000)])
        await store.addFolderSnapshot(ts: nowTs - 60, entries: [
            FolderSnapshotEntry(path: NSHomeDirectory() + "/Library/Developer", depth: 0, bytes: 13_000_000_000),
            FolderSnapshotEntry(path: NSHomeDirectory() + "/Library/Caches/Homebrew", depth: 1, bytes: 800_000_000)])
    }

    /// Ekrandaki gerçek pencerenin görüntüsü (kenar çubuğunun cam zemini dahil). Yoksa `capture` kullanılır.
    func screenshot(to url: URL) throws -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path)
    }

    func close() {
        model.mainWindowVisible = false
        window.close()
    }

    func allViews() -> [NSView] {
        var out: [NSView] = []
        func walk(_ v: NSView) { out.append(v); v.subviews.forEach(walk) }
        if let content = window.contentView { walk(content) }
        return out
    }

    /// Görünüm çerçevesi pencere içerik alanında (pencere koordinatları) ne kadar yer kaplıyor.
    func windowRect(of view: NSView) -> NSRect { view.convert(view.bounds, to: nil) }

    var contentBounds: NSRect { window.contentView?.convert(window.contentView?.bounds ?? .zero, to: nil) ?? .zero }

    func capture(to url: URL) throws {
        let frameView = try XCTUnwrap(window.contentView?.superview)
        frameView.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        overlaySidebar(on: rep, frameView: frameView)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    /// `cacheDisplay` kenar çubuğunun cam zeminini ve içeriğini çizmez (beyaz kalır); satırları ayrıca çizip üstüne koyar,
    /// böylece önizlemede kenar çubuğu öğeleri görünür.
    private func overlaySidebar(on rep: NSBitmapImageRep, frameView: NSView) {
        guard let sidebar = allViews().compactMap({ $0 as? NSTableView }).first(where: { windowRect(of: $0).midX < 300 }),
              let side = sidebar.bitmapImageRepForCachingDisplay(in: sidebar.visibleRect) else { return }
        sidebar.cacheDisplay(in: sidebar.visibleRect, to: side)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        let target = sidebar.convert(sidebar.visibleRect, to: frameView)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor(white: 0.13, alpha: 1).setFill()
        target.fill()
        let image = NSImage(size: sidebar.visibleRect.size)
        image.addRepresentation(side)
        image.draw(in: target)
        NSGraphicsContext.restoreGraphicsState()
    }
}
