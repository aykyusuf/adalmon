import SwiftUI

/// Uygulama anahtarı listesi (korunan uygulamalar, izin listesi): satır başına kaldır, "Ekle…" ile popover seçici.
struct AppKeyListEditor: View {
    let model: AppModel
    @Binding var apps: [String]
    let emptyText: String
    @State private var isPicking = false
    @State private var known: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if apps.isEmpty {
                Text(emptyText).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(apps, id: \.self) { app in
                AppKeyRow(app: app) { remove(app) }
            }
            Button("Uygulama ekle…", systemImage: "plus", action: beginPicking)
                .buttonStyle(.borderless)
                .popover(isPresented: $isPicking, arrowEdge: .bottom) {
                    AppPickerPopover(apps: known.filter { !apps.contains($0) }, onPick: add)
                }
        }
    }

    private func beginPicking() {
        known = KnownApps.collect(model: model)
        isPicking = true
    }

    private func add(_ app: String) {
        if !apps.contains(app) { apps.append(app) }
    }

    private func remove(_ app: String) {
        apps.removeAll { $0 == app }
    }
}
