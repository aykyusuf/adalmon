import Foundation

/// Bir widget'ın menü çubuğunda nasıl çizileceği.
enum WidgetStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case text, stacked, verticalBar, horizontalBar, ring, sparkline
    case speedTwoLine, speedOneLine, networkChart, dot, iconValue

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: "Metin"
        case .stacked: "Etiket + değer"
        case .verticalBar: "Dikey çubuk"
        case .horizontalBar: "Yatay çubuk"
        case .ring: "Halka"
        case .sparkline: "Çizgi grafik"
        case .speedTwoLine: "Hız (iki satır)"
        case .speedOneLine: "Hız (tek satır)"
        case .networkChart: "Ağ grafiği"
        case .dot: "Nokta"
        case .iconValue: "İkon + değer"
        }
    }
}
