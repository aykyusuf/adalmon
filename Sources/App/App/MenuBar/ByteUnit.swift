import Foundation

enum ByteUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, mb, gb

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "Otomatik"
        case .mb: "MB"
        case .gb: "GB"
        }
    }
}
