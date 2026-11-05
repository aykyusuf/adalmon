import Foundation

enum ColorTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case visual, value, both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .visual: "Grafik"
        case .value: "Değer"
        case .both: "İkisi"
        }
    }
}
