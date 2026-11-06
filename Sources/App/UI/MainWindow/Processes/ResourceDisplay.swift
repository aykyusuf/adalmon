import AppKit

/// Uygulama anahtarı → görünen ad / simge. Ağ sayfalarıyla aynı `AppCatalog`; özel anahtarlar burada eşlenir.
@MainActor
enum ResourceDisplay {
    static func name(_ key: String) -> String {
        switch key {
        case ResourceKeys.system: "Sistem (macOS)"
        case ResourceKeys.other: "Diğer"
        case ResourceKeys.unknown: "Bilinmeyen"
        default: AppCatalog.shared.name(for: key)
        }
    }

    static func icon(_ key: String) -> NSImage {
        switch key {
        case ResourceKeys.system: symbol("gearshape.2.fill")
        case ResourceKeys.other: symbol("ellipsis.circle.fill")
        case ResourceKeys.unknown: symbol("questionmark.circle.fill")
        default: AppCatalog.shared.icon(for: key)
        }
    }

    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }
}

import SwiftUI

/// Simge + ad (tablo ve liste satırlarında ortak).
struct ResourceAppLabel: View {
    let key: String
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: ResourceDisplay.icon(key))
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
            Text(ResourceDisplay.name(key))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
