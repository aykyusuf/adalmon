import Foundation

/// MagSafe LED modu. Ham değerler XPC üzerinden gider; SMC baytları `SMCWriteAllowlist` içinde ayrıca eşlenir.
enum MagSafeLEDMode: Int, Codable, CaseIterable, Sendable, Identifiable {
    case auto = 0, off = 1, green = 2, orange = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .auto: "Otomatik"
        case .off: "Kapalı"
        case .green: "Yeşil"
        case .orange: "Turuncu"
        }
    }
}
