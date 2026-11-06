import SwiftUI

/// Bağlantıları yenile / uygulamayı yeniden başlat.
struct AppInspectorActions: View {
    let appID: String
    let actions: PanelActions
    @State private var confirmingRestart = false

    private var canRestart: Bool { appID.hasSuffix(".app") }

    var body: some View {
        InspectorSection("Eylemler") {
            VStack(alignment: .leading, spacing: 8) {
                Button("Bağlantıları yenile", systemImage: "arrow.triangle.2.circlepath") {
                    actions.resetConnections(appID)
                }
                .help("Açık bağlantıları keser; uygulama yeniden bağlanır ve yeni sınır ya da engel hemen geçerli olur")
                if canRestart {
                    Button("Uygulamayı yeniden başlat", systemImage: "arrow.clockwise") {
                        confirmingRestart = true
                    }
                    .help("Uygulamayı kapatıp yeniden açar")
                }
            }
            .controlSize(.regular)
        }
        .confirmationDialog(
            "\(AppCatalog.shared.name(for: appID)) yeniden başlatılsın mı?",
            isPresented: $confirmingRestart,
            titleVisibility: .visible
        ) {
            Button("Yeniden başlat", role: .destructive) { actions.restartApp(appID) }
        } message: {
            Text("Uygulama kapatılıp yeniden açılır. Kaydedilmemiş çalışma varsa uygulama sana sorar.")
        }
    }
}
