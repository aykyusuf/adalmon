import Foundation

/// Bir panel kartının sırası ve görünürlüğü.
struct PanelCardItem: Codable, Hashable, Sendable, Identifiable {
    var kind: PanelCardKind
    var isVisible: Bool

    var id: PanelCardKind { kind }
}
