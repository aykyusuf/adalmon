import AppKit
import SwiftUI
import XCTest
@testable import Adalmon

/// Temizlik yeniden tasarım önizlemeleri için ortak PNG üretici (Gizlilik, Başlangıç, Bakım). Gerçek diske dokunmaz.
@MainActor
enum RD3PreviewRender {
    static func previewDir() throws -> URL {
        guard let env = ProcessInfo.processInfo.environment["ADALMON_PREVIEW_DIR"], !env.isEmpty else {
            throw XCTSkip("ADALMON_PREVIEW_DIR yok; önizleme atlandı")
        }
        let dir = URL(filePath: env)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func render<V: View>(_ content: V, prefix: String, name: String, dark: Bool, dir: URL,
                                width: CGFloat = 820, height: CGFloat = 760, spin: TimeInterval = 1.6) throws {
        let view = content
            .padding(24)
            .frame(width: width, height: height)
            .background(Color(nsColor: .windowBackgroundColor))
            .preferredColorScheme(dark ? .dark : .light)
            .environment(\.cleanupStaticArtwork, true)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: width, height: height),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: spin))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = dir.appending(path: "\(prefix)-\(name)-\(dark ? "dark" : "light").png")
        try png.write(to: url)
        print("\(prefix.uppercased())_PREVIEW: \(url.path())")
        window.close()
    }
}
