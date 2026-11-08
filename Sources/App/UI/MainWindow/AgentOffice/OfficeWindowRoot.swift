import SwiftUI

/// Ayrı "Ajan ofisi" penceresinin içeriği: ince araç şeridi + ofis sahnesi. Ana penceredeki sayfayla AYNI `AgentMonitorModel`'i
/// okur; sahne örneği ayrıdır. İçerik yalnızca pencere açıkken vardır (kapanınca hosting controller bırakılır).
struct OfficeWindowRoot: View {
    let model: AppModel
    @Bindable var state: OfficeWindowState

    var body: some View {
        let sessions = model.agents.monitor.state.orderedSessions
        VStack(spacing: 0) {
            strip(sessions: sessions)
            OfficeSceneContainer(members: OfficeMember.members(from: sessions), selectedRoom: $state.selectedRoom)
                .overlay { if sessions.isEmpty { emptyHint } }
                .accessibilityLabel("Ajan ofisi: \(sessions.count) oturum")
        }
    }

    private func strip(sessions: [AgentSession]) -> some View {
        HStack(spacing: 12) {
            Button("Hepsini göster", systemImage: "rectangle.grid.2x2") { state.selectedRoom = nil }
                .disabled(state.selectedRoom == nil)
                .help("Odadan çık, tüm odaları göster (Esc)")
            Spacer(minLength: 8)
            Toggle("Hep üstte", isOn: $state.settings.alwaysOnTop)
                .help("Pencere diğer pencerelerin üstünde kalır")
            Toggle("Tüm masaüstlerinde", isOn: $state.settings.allSpaces)
                .help("Pencere tüm masaüstlerinde (Space) görünür")
            Menu {
                Toggle("Şeffaf başlık çubuğu", isOn: $state.settings.transparentTitlebar)
                OfficeLightingMenu()
            } label: {
                Label("Seçenekler", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var emptyHint: some View {
        Text("Henüz ajan olayı yok")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: .capsule)
            .allowsHitTesting(false)
    }
}
