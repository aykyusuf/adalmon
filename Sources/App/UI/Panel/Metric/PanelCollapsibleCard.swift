import SwiftUI

/// Juicy tarzı daraltılabilir kart: simgeli başlık + chevron; açık/kapalı durum `PanelConfig` içinde hatırlanır.
/// Açılıp kapanma yumuşak (içerik solar, yükseklik animasyonlu); Hareketi azalt açıkken anında.
struct PanelCollapsibleCard<Accessory: View, Content: View, Footer: View>: View {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    @Binding var config: PanelConfig
    /// Hiç dokunulmamış hali kapalı mı (ör. "Pil bilgisi").
    var defaultCollapsed = false
    /// Menü çubuğundaki cihaz öğesinden gelinince bölüm geçici olarak açık gösterilir (kayıtlı durum değişmez).
    var forceOpen = false
    /// İçerik alanı iç boşluğu (satır tabanlı listelerde 0).
    var contentPadding: CGFloat = 12
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var forceDismissed = false

    private var collapsed: Bool {
        if forceOpen && !forceDismissed { return false }
        return config.isDetailCollapsed(id, defaultCollapsed: defaultCollapsed)
    }

    var body: some View {
        let collapsed = collapsed
        PanelCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.panelExpand(reduceMotion: reduceMotion)) {
                        if forceOpen && !forceDismissed {
                            forceDismissed = true
                            config.detailCollapsed.insert(id)
                            config.detailExpanded.remove(id)
                        } else {
                            config.toggleDetailCollapsed(id, defaultCollapsed: defaultCollapsed)
                        }
                    }
                } label: {
                    header(collapsed: collapsed)
                }
                .buttonStyle(PanelRowButtonStyle())
                .accessibilityLabel(title)
                .accessibilityValue(collapsed ? "Daraltıldı" : "Açık")
                .accessibilityHint(collapsed ? "Bölümü aç" : "Bölümü daralt")
                if !collapsed {
                    VStack(alignment: .leading, spacing: 0) {
                        Divider().opacity(0.6)
                        VStack(alignment: .leading, spacing: 10) { content }
                            .padding(contentPadding)
                        footer
                    }
                    .transition(.opacity.combined(with: .offset(y: -6)))
                }
            }
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
        }
        .padding(-0)
    }

    private func header(collapsed: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.16), in: .circle)
                .accessibilityHidden(true)
            Text(title).font(.callout.weight(.semibold))
            Spacer(minLength: 6)
            accessory.font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                .rotationEffect(.degrees(collapsed ? 180 : 0))
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .contentShape(.rect)
    }
}

extension PanelCollapsibleCard where Footer == EmptyView {
    init(id: String, title: String, symbol: String, tint: Color, config: Binding<PanelConfig>, defaultCollapsed: Bool = false,
         forceOpen: Bool = false, contentPadding: CGFloat = 12,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.init(id: id, title: title, symbol: symbol, tint: tint, config: config, defaultCollapsed: defaultCollapsed, forceOpen: forceOpen,
                  contentPadding: contentPadding, accessory: accessory, content: content, footer: { EmptyView() })
    }
}
