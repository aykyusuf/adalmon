import SwiftUI

/// Başlık: uygulama adı, bağlantı/hotspot rozeti ve dişli düğmesi.
struct PanelHeader: View {
    let data: PanelData
    @Binding var config: PanelConfig
    let openApp: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Adalmon")
                .font(.headline)
            ConnectionBadge(medium: data.medium, isMobile: data.isMobile, interfaceName: data.interfaceName)
            Spacer(minLength: 8)
            PanelCustomizeMenu(config: $config, opensMainWindow: data.opensMainWindow,
                               openApp: openApp, openSettings: openSettings)
        }
        .frame(minHeight: 24)
    }
}
