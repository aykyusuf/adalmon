import SwiftUI

/// Değer kutusunun bir satırı: renk noktası + seri adı + değer metni.
struct ChartTooltipRow: Identifiable, Equatable {
    var name: String
    var color: Color
    var text: String
    var id: String { name }
}
