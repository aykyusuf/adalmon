import Foundation

/// Panel zemini: opak (Juicy gibi koyu; açık görünümde eşdeğer açık yüzey) ya da Liquid Glass.
enum PanelBackground: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Koyu, neredeyse opak yüzey (varsayılan). Açık görünümde opak açık yüzey.
    case solid
    /// Saydam Liquid Glass.
    case glass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .solid: "Koyu (opak)"
        case .glass: "Cam (saydam)"
        }
    }

    static let `default`: PanelBackground = .solid
}
