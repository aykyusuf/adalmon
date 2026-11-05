import Foundation

/// Eşik renk modu sınırları (0...1). `warning` altı yeşil, `critical` altı turuncu, üstü kırmızı.
struct Thresholds: Codable, Equatable, Sendable {
    var warning: Double = 0.6
    var critical: Double = 0.8

    func level(for fraction: Double) -> ThresholdLevel {
        if fraction >= critical { return .critical }
        if fraction >= warning { return .warning }
        return .normal
    }
}
