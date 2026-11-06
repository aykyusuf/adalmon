import AppKit

/// Uygulama kimliği → ikon. `.app` paketi kendi ikonunu, ödünç ikonlu servisler temsilci uygulamanın ikonunu,
/// komut satırı araçları terminal rozetini, sistem servisleri dişli rozetini alır.
@MainActor
enum AppIconFactory {
    private static let tileSize: CGFloat = 128

    static func icon(for identity: AppIdentity, appPath: String) -> NSImage {
        let path = AppNaming.outermostApp(of: appPath)
        if identity.kind == .application {
            if FileManager.default.fileExists(atPath: path) { return NSWorkspace.shared.icon(forFile: path) }
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        if let id = identity.iconBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        switch identity.kind {
        case .commandLineTool: return tile(symbol: "terminal.fill", gray: 0.14)
        case .systemService, .application: return tile(symbol: "gearshape.fill", gray: 0.46)
        }
    }

    /// Yuvarlatılmış kare zemin üstünde beyaz SF Symbol (Dock ikonlarıyla uyumlu görünür, açık/koyu temada aynı kalır).
    private static func tile(symbol: String, gray: CGFloat) -> NSImage {
        let size = NSSize(width: tileSize, height: tileSize)
        let image = NSImage(size: size, flipped: false) { rect in
            let body = rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.04)
            let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
            NSColor(white: gray, alpha: 1).setFill()
            path.fill()

            let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.44, weight: .semibold)
                .applying(.init(paletteColors: [.white]))
            guard let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
                return true
            }
            let g = glyph.size
            glyph.draw(in: NSRect(x: rect.midX - g.width / 2, y: rect.midY - g.height / 2, width: g.width, height: g.height))
            return true
        }
        image.isTemplate = false
        return image
    }
}
