import SwiftUI

/// Etkileşimli çizgi grafiğinin bir serisi (zamana göre artan noktalar).
struct ChartLine: Identifiable, Equatable {
    var name: String
    var color: Color
    var points: [ChartPoint]
    var id: String { name }
}
