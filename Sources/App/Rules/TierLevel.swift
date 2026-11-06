import Foundation

/// Kademeli limit merdiveninin basamağı (günlük/dönemlik kullanım yüzdesine göre).
enum TierLevel: Int, Codable, Sendable, Comparable {
    case none = 0, warn, slow, cut

    static func < (a: TierLevel, b: TierLevel) -> Bool { a.rawValue < b.rawValue }
}
