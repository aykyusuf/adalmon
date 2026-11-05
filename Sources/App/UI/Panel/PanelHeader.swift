import SwiftUI

struct PanelHeader: View {
    let data: PanelData
    @Binding var config: PanelConfig
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Adalmon")
                .font(.headline)
            ConnectionBadge(medium: data.medium, isMobile: data.isMobile, interfaceName: data.interfaceName)
            Spacer()
            PanelCustomizeMenu(config: $config, openSettings: openSettings)
        }
    }
}
