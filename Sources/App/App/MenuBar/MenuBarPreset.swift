import Foundation

enum MenuBarPreset: String, CaseIterable, Identifiable, Sendable {
    case kompakt, ayrintili, sade, minimal, renkli, grafik, sicaklik, agOdakli

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kompakt: "Kompakt"
        case .ayrintili: "Ayrıntılı"
        case .sade: "Sade"
        case .minimal: "Minimal"
        case .renkli: "Renkli"
        case .grafik: "Grafik"
        case .sicaklik: "Sıcaklık"
        case .agOdakli: "Ağ odaklı"
        }
    }

    var summary: String {
        switch self {
        case .kompakt: "Bağlantı, etiketli CPU/RAM çubukları ve iki satır hız."
        case .ayrintili: "CPU yüzdesi ile sıcaklığı alt alta, bellek kullanılan/boş, ayrı indirme ve yükleme."
        case .sade: "Etiketsiz: en dar görünüm."
        case .minimal: "Yalnızca yükleme ve indirme hızı."
        case .renkli: "Eşik renkli halkalar ve mobil veri çubuğu."
        case .grafik: "Son 60 saniyenin çizgi grafikleri."
        case .sicaklik: "CPU ve GPU sıcaklığı halkalarda, eşik renkli."
        case .agOdakli: "Ağ grafiği, anlık hız ve bugünkü toplam."
        }
    }

    var components: [MenuBarComponent] {
        let speed = MenuBarComponent(.upload, .download, visual: .stacked2, showLabel: true)
        switch self {
        case .kompakt:
            return [MenuBarComponent(.connection, visual: .dot, showValue: false),
                    MenuBarComponent(.cpu, visual: .bar, colorMode: .threshold, showLabel: true, showValue: false),
                    MenuBarComponent(.memoryPercent, visual: .bar, colorMode: .threshold, showLabel: true, showValue: false),
                    speed]
        case .ayrintili:
            return [MenuBarComponent(.cpu, .cpuTemp, visual: .stacked2, colorMode: .threshold, colorTarget: .value, showLabel: true),
                    MenuBarComponent(.memoryUsed, .memoryFree, visual: .stacked2, showLabel: true),
                    MenuBarComponent(.download, visual: .text, showLabel: true),
                    MenuBarComponent(.upload, visual: .text, showLabel: true)]
        case .sade:
            return [MenuBarComponent(.connection, visual: .dot, showValue: false),
                    MenuBarComponent(.cpu, visual: .bar, colorMode: .threshold, showValue: false),
                    MenuBarComponent(.memoryPercent, visual: .bar, colorMode: .threshold, showValue: false),
                    speed]
        case .minimal:
            return [speed]
        case .renkli:
            return [MenuBarComponent(.cpu, visual: .ring, colorMode: .threshold),
                    MenuBarComponent(.gpu, visual: .ring, colorMode: .threshold),
                    MenuBarComponent(.memoryPercent, visual: .ring, colorMode: .gradient),
                    speed,
                    MenuBarComponent(.mobileUsed, visual: .hbar, colorMode: .threshold)]
        case .grafik:
            return [MenuBarComponent(.cpu, visual: .sparkline, colorMode: .accent),
                    MenuBarComponent(.memoryPercent, visual: .sparkline, colorMode: .custom, customColor: .teal),
                    MenuBarComponent(.download, .upload, visual: .sparkline, showValue: false)]
        case .sicaklik:
            return [MenuBarComponent(.cpuTemp, visual: .ring, colorMode: .threshold, showLabel: true),
                    MenuBarComponent(.gpuTemp, visual: .ring, colorMode: .threshold, showLabel: true),
                    MenuBarComponent(.cpu, visual: .stacked2, colorMode: .threshold, colorTarget: .value, showLabel: true),
                    speed]
        case .agOdakli:
            return [MenuBarComponent(.connection, visual: .dot, showValue: false),
                    MenuBarComponent(.download, .upload, visual: .sparkline, colorMode: .accent, showValue: false),
                    speed,
                    MenuBarComponent(.downloadToday, visual: .stacked2, showLabel: true)]
        }
    }

    func makeConfig() -> MenuBarConfig { MenuBarConfig(components: components) }

    func matches(_ components: [MenuBarComponent]) -> Bool {
        let mine = self.components
        guard mine.count == components.count else { return false }
        return zip(mine, components).allSatisfy { $0.isEquivalent(to: $1) }
    }

    static func matching(_ components: [MenuBarComponent]) -> MenuBarPreset? {
        allCases.first { $0.matches(components) }
    }
}
