import SwiftUI

/// Panel ayarlarında bir bölüm ya da kart satırı: görünürlük anahtarı + yukarı/aşağı taşıma.
struct PanelReorderRow: View {
    let title: String
    let systemImage: String
    @Binding var isVisible: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMove: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $isVisible) {
                Label(title, systemImage: systemImage)
            }
            Spacer()
            Button("Yukarı taşı", systemImage: "chevron.up") { onMove(-1) }
                .disabled(!canMoveUp)
            Button("Aşağı taşı", systemImage: "chevron.down") { onMove(1) }
                .disabled(!canMoveDown)
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
    }
}
