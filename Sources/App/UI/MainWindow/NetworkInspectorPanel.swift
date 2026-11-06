import SwiftUI

/// Ağ kullanımı sayfasının sağ paneli: üstte başlık + kapatma (×) düğmesi, altında seçili uygulamanın ayrıntıları.
/// Esc de paneli kapatır.
struct NetworkInspectorPanel: View {
    let selectedID: String?
    let data: PanelData
    let model: AppModel
    let actions: PanelActions
    let onToggleBlock: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Uygulama ayrıntıları")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button("Paneli kapat", systemImage: "xmark", action: onClose)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Paneli kapat (Esc)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            content
        }
        .onExitCommand(perform: onClose)
    }

    @ViewBuilder
    private var content: some View {
        if let id = selectedID {
            AppInspectorView(
                appID: id,
                usage: data.today.first { $0.app == id },
                last60Bytes: data.last60.first { $0.app == id }?.bytes ?? 0,
                isBlocked: data.isBlocked(id),
                isMobile: data.isMobile,
                model: model,
                actions: actions,
                onToggleBlock: { onToggleBlock(id) }
            )
        } else {
            ContentUnavailableView("Uygulama seçilmedi", systemImage: "sidebar.trailing",
                                   description: Text("Ayrıntılarını görmek için tablodan bir uygulama seç."))
        }
    }
}
