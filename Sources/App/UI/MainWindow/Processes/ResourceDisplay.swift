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
}

import SwiftUI

/// Simge + ad (tablo ve liste satırlarında ortak).
struct ResourceAppLabel: View {
    let key: String
    var size: CGFloat = 22
    /// Aynı adlı başka satır varsa yer ipucu ("DerivedData", "/Applications").
    var hint: String?

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
}
