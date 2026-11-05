import Foundation

/// How a `DataField` value is measured and formatted.
enum FieldKind: Sendable, Equatable {
    case percent
    case temperature
    case bytes(binary: Bool)
    case rate
    case pressure
    case mobileUsage
    case connection
}
