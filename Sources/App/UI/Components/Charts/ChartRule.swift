import SwiftUI

/// Yatay referans çizgisi (bütçe, limit vb.).
struct ChartRule: Identifiable, Equatable {
    var name: String
    var value: Double
    var color: Color
    var dash: [CGFloat] = [5, 4]
    var lineWidth: CGFloat = 1.5
    /// Çizginin başında görünen etiket (yoksa yalnız çizgi).
    var label: String?
    var id: String { name }
}
