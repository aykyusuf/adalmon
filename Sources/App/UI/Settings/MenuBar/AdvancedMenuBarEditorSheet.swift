import SwiftUI

/// The full component editor (presets, library, inspector), opened from the simple cards page.
struct AdvancedMenuBarEditorSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MenuBarSettingsTab(model: model)
                .navigationTitle("Gelişmiş düzenleyici")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Bitti") { dismiss() }
                    }
                }
        }
        .frame(minWidth: 780, idealWidth: 860, minHeight: 640, idealHeight: 760)
    }
}
