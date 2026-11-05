import Foundation

/// Etkin widget'lar tek bir menü çubuğu öğesinde mi, ayrı öğelerde mi?
enum MenuBarDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case combined, separate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .combined: "Tek öğe"
        case .separate: "Ayrı öğeler"
        }
    }
}
