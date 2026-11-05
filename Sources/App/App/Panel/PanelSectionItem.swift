import Foundation

/// Bir panel bölümünün sırası ve görünürlüğü.
struct PanelSectionItem: Codable, Hashable, Sendable, Identifiable {
    var section: PanelSection
    var isVisible: Bool

    var id: PanelSection { section }
}
