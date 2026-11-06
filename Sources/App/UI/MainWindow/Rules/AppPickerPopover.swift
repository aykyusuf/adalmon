import SwiftUI

/// Aranabilir uygulama listesi + "Dosyadan seç…". Seçilen uygulamanın anahtarını `onPick` ile verir.
struct AppPickerPopover: View {
    let apps: [String]
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Uygulama ara", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            List(filtered, id: \.self) { app in
                Button { pick(app) } label: {
                    HStack(spacing: 8) {
                        Image(nsImage: AppCatalog.shared.icon(for: app))
                            .resizable()
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                        Text(AppCatalog.shared.name(for: app)).lineLimit(1)
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(apps.isEmpty ? "Henüz bilinen uygulama yok" : "Sonuç yok", systemImage: "app.dashed",
                                           description: Text("Aşağıdan bir .app dosyası seçebilirsin."))
                }
            }
            Divider()
            Button("Dosyadan seç…", systemImage: "folder", action: chooseFile)
                .buttonStyle(.borderless)
                .padding(10)
        }
        .frame(width: 320, height: 380)
    }

    private var filtered: [String] {
        guard !query.isEmpty else { return apps }
        return apps.filter { AppCatalog.shared.name(for: $0).localizedStandardContains(query) }
    }

    private func pick(_ app: String) {
        onPick(app)
        dismiss()
    }

    private func chooseFile() {
        dismiss()
        if let path = AppFilePicker.pick() { onPick(path) }
    }
}
