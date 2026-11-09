import SwiftUI

/// Ayrı "Ajan ofisi" penceresinin içeriği: ince araç şeridi + ofis sahnesi. Ana penceredeki sayfayla AYNI `AgentMonitorModel`'i
/// okur; sahne örneği ayrıdır. İçerik yalnızca pencere açıkken vardır (kapanınca hosting controller bırakılır).
struct OfficeWindowRoot: View {
    let model: AppModel
    @Bindable var state: OfficeWindowState
    @AppStorage(OfficeLighting.defaultsKey) private var lightingRaw = OfficeLightingMode.auto.rawValue
    @State private var stripHeight: CGFloat = 36

    var body: some View {
        let sessions = model.agents.monitor.state.orderedSessions
        let members = OfficeMember.members(from: sessions)
        // Tam ekranda şerit sahnenin üstüne biner (sahne tüm yüksekliği kullanır) ve 3 sn hareketsizlikte solar; pencerede eskisi gibi hep görünür.
        ZStack(alignment: .top) {
            OfficeSceneContainer(members: members, selectedRoom: $state.selectedRoom, panoActive: state.panoActive)
                .padding(.top, state.isFullScreen ? 0 : stripHeight)
                .overlay { if sessions.isEmpty { emptyHint } }
                .accessibilityLabel("Ajan ofisi: \(sessions.count) oturum")
            if state.panoActive {
                let night = OfficeLighting.isNight(mode: OfficeLightingMode(rawValue: lightingRaw) ?? .auto, date: state.clock.now)
                OfficePanoCorners(members: members, now: state.clock.now, night: night, showsClock: state.settings.showsClockSummary)
                    .opacity(state.settings.showsClockSummary ? 1 : 0)
                    // Tam ekranda şerit sahnenin üstüne biner: görünürken köşe pill'leri onun altına iner (yapışık durmasın).
                    .padding(.top, state.isFullScreen ? (state.stripShown ? stripHeight : 0) : stripHeight)
                    .animation(.easeOut(duration: OfficeChromeVisibility.fadeDuration), value: state.stripShown)
            }
            strip(sessions: sessions)
                .opacity(state.stripShown ? 1 : 0)
                .allowsHitTesting(state.stripShown)
                .animation(.easeOut(duration: OfficeChromeVisibility.fadeDuration), value: state.stripShown)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stripHeight = $0 }
        }
        .onAppear { model.agents.monitor.addShellObserver() }
        .onDisappear { model.agents.monitor.removeShellObserver() }
    }

    private func strip(sessions: [AgentSession]) -> some View {
        HStack(spacing: 12) {
            Button("Hepsini göster", systemImage: "rectangle.grid.2x2") { state.selectedRoom = nil }
                .disabled(state.selectedRoom == nil)
                .help("Odadan çık, tüm odaları göster (Esc)")
            Spacer(minLength: 8)
            Button("Tam ekran", systemImage: "arrow.up.left.and.arrow.down.right") { state.onToggleFullScreen?() }
                .help("Tam ekran pano görünümü (⌃⌘F)")
            Toggle("Hep üstte", isOn: $state.settings.alwaysOnTop)
                .help("Pencere diğer pencerelerin üstünde kalır")
            Toggle("Tüm masaüstlerinde", isOn: $state.settings.allSpaces)
                .help("Pencere tüm masaüstlerinde (Space) görünür")
            Menu {
                Toggle("Şeffaf başlık çubuğu", isOn: $state.settings.transparentTitlebar)
                OfficeThemeMenu()
                OfficeLightingMenu()
                Picker("Pano görünümü: \(state.settings.panoMode.title)", selection: $state.settings.panoMode) {
                    ForEach(OfficePanoMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                Toggle("Saat ve özet", isOn: $state.settings.showsClockSummary)
                Toggle("Ekranı uyanık tut", isOn: $state.settings.keepAwake)
                Text("Uyanık tut: yalnızca tam ekranda; pilde açıkken yorabilir")
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
