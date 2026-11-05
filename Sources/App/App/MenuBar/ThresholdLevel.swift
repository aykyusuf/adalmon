import Foundation

/// Eşik renk modunda değerin düştüğü bölge.
enum ThresholdLevel: Sendable, Equatable {
    case normal, warning, critical
}
