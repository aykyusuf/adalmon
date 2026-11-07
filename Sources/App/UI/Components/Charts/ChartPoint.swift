import Foundation

/// Zaman serisi grafiklerinin tek noktası.
struct ChartPoint: Identifiable, Equatable, Sendable {
    var date: Date
    var value: Double
    var id: Date { date }
}
