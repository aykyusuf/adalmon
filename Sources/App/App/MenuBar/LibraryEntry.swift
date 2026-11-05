import Foundation

/// A ready-made component shown in the settings library.
struct LibraryEntry: Identifiable, Sendable {
    let id: String
    let title: String
    let category: FieldCategory
    let component: MenuBarComponent

    init(_ id: String, _ title: String, _ category: FieldCategory, _ component: MenuBarComponent) {
        self.id = id
        self.title = title
        self.category = category
        self.component = component
    }
}
