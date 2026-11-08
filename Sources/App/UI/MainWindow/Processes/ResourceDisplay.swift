import AppKit

/// Uygulama anahtarı → görünen ad / simge. Ağ sayfalarıyla aynı `AppCatalog`; özel anahtarlar burada eşlenir.
@MainActor
enum ResourceDisplay {
    static func name(_ key: String) -> String {
        switch key {
        case ResourceKeys.system: return "Sistem (macOS)"
        case ResourceKeys.other: return "Diğer"
        case ResourceKeys.unknown: return "Bilinmeyen"
        default:
            if let cached = compoundNames[key] { return cached }
            if let compound = TerminalChildKey.displayName(key, appName: { AppCatalog.shared.name(for: $0) }) {
                compoundNames[key] = compound
                return compound
            }
            return AppCatalog.shared.name(for: key)
        }
    }

    /// "Terminal › araç" adları (sıralama karşılaştırıcıları her çağrıda yeniden kurmasın).
    private static var compoundNames: [String: String] = [:]

    static func icon(_ key: String) -> NSImage {
        switch key {
        case ResourceKeys.system: symbol("gearshape.2.fill")
        case ResourceKeys.other: symbol("ellipsis.circle.fill")
        case ResourceKeys.unknown: symbol("questionmark.circle.fill")
        default: AppCatalog.shared.icon(for: TerminalChildKey.split(key)?.terminal ?? key)
        }
    }

    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }

    /// Anahtar + piksel boyutu + görünüm başına bir kez rasterleştirilmiş simge. `NSImage`'ı her çizimde SwiftUI'ye
    /// ölçeklettirmek (1024 px temsilden 40 px'e yüksek kaliteli küçültme, terminal/dişli karolarının çizim bloğunun
    /// yeniden çalışması) her ölçümde satır başına vImage evrişimi ve glif/yol çizimi demekti.
    static func rasterIcon(_ key: String, points: CGFloat, scale: CGFloat, dark: Bool) -> CGImage? {
        let pixels = max(1, Int((points * scale).rounded()))
        let cacheKey = "\(dark ? 1 : 0)|\(pixels)|\(key)" as NSString
        if let hit = rasterCache.object(forKey: cacheKey) { return hit }
        let source = icon(key)
        // Şablon simgeler (Sistem / Diğer / Bilinmeyen SF Symbol'leri) ön plan rengiyle boyanmalı; bitmap'e çizilirse siyah kalır.
        guard !source.isTemplate, let image = render(source, pixels: pixels, dark: dark) else { return nil }
        rasterCache.setObject(image, forKey: cacheKey)
        return image
    }

    private static let rasterCache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 600
        return cache
    }()

    private static func render(_ image: NSImage, pixels: Int, dark: Bool) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        appearance.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            // En-boy oranını koru (`scaledToFit` gibi): kare olmayan simgeler ortalanır.
            let size = image.size
            var target = rect
            if size.width > 0, size.height > 0, size.width != size.height {
                let f = min(rect.width / size.width, rect.height / size.height)
                target.size = NSSize(width: size.width * f, height: size.height * f)
                target.origin = NSPoint(x: (rect.width - target.width) / 2, y: (rect.height - target.height) / 2)
            }
            image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        return ctx.makeImage()
    }
}

import SwiftUI

/// Simge + ad (tablo ve liste satırlarında ortak).
struct ResourceAppLabel: View {
    let key: String
    var size: CGFloat = 22
    /// Aynı adlı başka satır varsa yer ipucu ("DerivedData", "/Applications").
    var hint: String?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: size, height: size)
                .accessibilityHidden(true)
            Text(ResourceDisplay.name(key))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if let hint {
                Text("· \(hint)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(hint)
            }
        }
    }

    /// Önbellekli, tam piksel boyutunda bitmap (ölçekleme yok); üretilemezse eski yol.
    @ViewBuilder
    private var icon: some View {
        if let cg = ResourceDisplay.rasterIcon(key, points: size, scale: displayScale, dark: scheme == .dark) {
            Image(decorative: cg, scale: displayScale)
        } else {
            Image(nsImage: ResourceDisplay.icon(key)).resizable().scaledToFit()
        }
    }
}
