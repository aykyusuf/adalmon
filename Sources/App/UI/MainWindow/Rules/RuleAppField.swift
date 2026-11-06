import SwiftUI

/// Düzenleyicide seçili uygulama + "Seç…" popover'ı.
struct RuleAppField: View {
    let model: AppModel
    @Binding var app: String
    @State private var isPicking = false
    @State private var known: [String] = []

    var body: some View {
        LabeledContent("Uygulama") {
            Button(action: beginPicking) {
                HStack(spacing: 8) {
                    if !app.isEmpty {
                        Image(nsImage: AppCatalog.shared.icon(for: app))
                            .resizable()
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                    }
                    Text(app.isEmpty ? "Seç…" : AppCatalog.shared.name(for: app)).lineLimit(1)
                }
            }
            .popover(isPresented: $isPicking, arrowEdge: .bottom) {
                AppPickerPopover(apps: known, onPick: pick)
            }
        }
    }

    private func beginPicking() {
        known = KnownApps.collect(model: model, extra: app.isEmpty ? [] : [app])
        isPicking = true
    }

    private func pick(_ app: String) { self.app = app }
}
