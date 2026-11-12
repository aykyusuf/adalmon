import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Yer kaplayanlar haritasını sahte veriyle ekran dışında çizip PNG yazar (açık + koyu; hover; geçiş ortası).
/// Yalnızca ADALMON_PREVIEW_DIR (xcodebuild için TEST_RUNNER_ADALMON_PREVIEW_DIR) verilince çalışır.
@MainActor
final class SpaceLensPreviewTests: XCTestCase {
    private func node(_ path: String, _ kind: SpaceNode.Kind, _ mb: Double) -> SpaceNode {
        SpaceNode(path: path, kind: kind, bytes: UInt64(mb * 1_048_576))
    }

    private var rootNodes: [SpaceNode] {
        [node("/h/Library", .folder, 41_000), node("/h/Movies", .folder, 22_500), node("/h/Developer", .folder, 18_200),
         node("/h/Applications", .folder, 9_800), node("/h/Documents", .folder, 6_400), node("/h/Pictures", .folder, 5_100),
         node("/h/backup.dmg", .file, 4_200), node("/h/archive.zip", .file, 2_300), node("/h/node_modules", .folder, 1_800),
         node("/h/Music", .folder, 1_200), node("/h/notes.txt", .file, 640), node("/h/Projects", .folder, 520),
         node("/h/Studio.app", .folder, 380), node("/h/data.bin", .file, 150), node("/h/misc", .folder, 90),
         node("/h/Mail", .skipped(.fullDiskAccess), 0)]
    }

    private var childNodes: [SpaceNode] {
        [node("/h/Library/Caches", .folder, 18_000), node("/h/Library/Application Support", .folder, 12_000),
         node("/h/Library/Developer", .folder, 7_000), node("/h/Library/Logs", .folder, 1_800), node("/h/Library/big.log", .file, 900),
         node("/h/Library/Preferences", .folder, 400)]
    }

    private struct Transition: View {
        let root: [SpaceNode]
        let child: [SpaceNode]
        @State private var inside = false
        var body: some View {
            TreemapCanvas(nodes: inside ? child : root, otherBytes: 3_000_000, selectedID: nil, contextPath: inside ? "/h/Library" : "/h") { _ in }
                .task {
                    try? await Task.sleep(for: .milliseconds(800))
                    inside = true
                }
        }
    }

    func testRenderTreemap() async throws {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            let bg = dark ? Color(white: 0.13) : Color(white: 0.96)
            let plain = VStack(alignment: .leading, spacing: 8) {
                TreemapCanvas(nodes: rootNodes, otherBytes: 3_000_000, selectedID: nil, contextPath: "/h") { _ in }.frame(height: 340)
                TreemapLegend(nodes: rootNodes)
            }.padding(16).background(bg)
            try await render(plain, name: "spacelens-root-\(mode)", dir: dir, size: NSSize(width: 760, height: 410), dark: dark, wait: 1.6)
            let hovered = TreemapCanvas(nodes: rootNodes, otherBytes: 3_000_000, selectedID: "/h/Documents", contextPath: "/h",
                                        previewHoverID: "/h/Movies") { _ in }
                .frame(height: 340).padding(16).background(bg)
            try await render(hovered, name: "spacelens-hover-\(mode)", dir: dir, size: NSSize(width: 760, height: 372), dark: dark, wait: 1.6)
            let renderer = ImageRenderer(content: hovered.frame(width: 760, height: 372).environment(\.colorScheme, dark ? .dark : .light))
            renderer.scale = 1
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try png.write(to: dir.appending(path: "spacelens-hover-imagerenderer-\(mode).png"))
            }
            let narrow = TreemapCanvas(nodes: childNodes, selectedID: nil, contextPath: "/h/Library") { _ in }
                .frame(width: 320, height: 200).padding(16).background(bg)
            try await render(narrow, name: "spacelens-small-\(mode)", dir: dir, size: NSSize(width: 352, height: 232), dark: dark, wait: 1.6)
        }
        // Geçiş ortası (0,8 sn sonra tetiklenir; ~0,15 sn sonrası yakalanır).
        let mid = Transition(root: rootNodes, child: childNodes).frame(height: 340).padding(16).background(Color(white: 0.13))
        try await render(mid, name: "spacelens-transition-dark", dir: dir, size: NSSize(width: 760, height: 372), dark: true, wait: 1.05)
    }

    private func render<V: View>(_ view: V, name: String, dir: URL, size: NSSize, dark: Bool, wait: Double) async throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).preferredColorScheme(dark ? .dark : .light))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(wait))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = dir.appending(path: "\(name).png")
        try png.write(to: url)
        print("SPACELENS_PREVIEW: \(url.path())")
        window.close()
    }
}
