import SwiftUI

/// Panel satırı düğmesi: üzerine gelince / basılınca hafif vurgu (kart içinde tam genişlik tıklanabilir satır).
struct PanelRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PanelRowBody(configuration: configuration)
    }

    private struct PanelRowBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .background(.primary.opacity(configuration.isPressed ? 0.10 : (hovering && isEnabled ? 0.055 : 0)))
                .onHover { hovering = $0 }
        }
    }
}
