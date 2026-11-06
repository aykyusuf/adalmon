import SwiftUI

/// Tek uygulama satırı: ikon, ad › alan adı, sağa yaslı byte, üzerine gelince engelle düğmesi.
/// Engelle eylemi VoiceOver (accessibilityAction) ve sağ tık menüsünden her zaman erişilebilir.
struct AppUsageRow: View {
    let usage: AppUsage
    let maxBytes: UInt64
    let isBlocked: Bool
    let isMobile: Bool
    let expandable: Bool
    let setBlocked: @MainActor (String, Bool) -> Void
    let resetConnections: @MainActor (String) -> Void
    let restartApp: @MainActor (String) -> Void
    @Environment(\.panelDensity) private var density
    @State private var expanded = false
    @State private var confirming = false
    @State private var hovering = false

    var body: some View {
        let name = AppCatalog.shared.name(for: usage.app)
        VStack(alignment: .leading, spacing: 2) {
            line(name: name)
            if confirming {
                BlockConfirmation(name: name, isMobile: isMobile) {
                    withAnimation(.snappy) { confirming = false }
                } onConfirm: {
                    setBlocked(usage.app, true)
                    withAnimation(.snappy) { confirming = false }
                }
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if expanded {
                ForEach(usage.domains, id: \.name) { d in
                    HStack {
                        Text(d.name).lineLimit(1)
                        Spacer()
                        Text(Format.bytes(d.bytes)).monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, density.iconSize + 6)
                    .padding(.trailing, 22)
                }
                .transition(.opacity)
            }
        }
    }

    private var fraction: Double { Double(usage.bytes) / Double(max(1, maxBytes)) }

    private var topDomain: String? {
        guard let top = usage.domains.first?.name, top != AppCatalog.shared.name(for: usage.app) else { return nil }
        return top
    }

    private func line(name: String) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: AppCatalog.shared.icon(for: usage.app))
                .resizable()
                .frame(width: density.iconSize, height: density.iconSize)
            HStack(spacing: 4) {
                Text(name)
                    .font(.callout)
                    .layoutPriority(1)
                if let topDomain {
                    Text("› \(topDomain)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .truncationMode(.middle)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            if usage.mobileBytes > 0 && usage.mobileBytes != usage.bytes {
                Text("mobil \(Format.bytes(usage.mobileBytes))")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Text(Format.bytes(usage.bytes))
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 58, alignment: .trailing)
            blockButton
        }
        .frame(height: density.rowHeight)
        .background(alignment: .bottomLeading) { usageBar }
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture { if expandable { withAnimation(.snappy) { expanded.toggle() } } }
        .contextMenu { menuItems }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(name: name))
        .accessibilityAddTraits(expandable ? .isButton : [])
        .accessibilityHint(expandable ? "Alan adı dökümünü aç veya kapat" : "")
        .accessibilityAction {
            if expandable { withAnimation(.snappy) { expanded.toggle() } }
        }
        .accessibilityAction(named: isBlocked ? "Engeli kaldır" : "Mobilde engelle") { blockTapped() }
        .help(topDomain.map { "\(name) › \($0)" } ?? name)
    }

    /// Satırın altında, en çok harcayana göre oranlı ince çubuk.
    private var usageBar: some View {
        GeometryReader { geo in
            Capsule()
                .fill(isBlocked ? Color.red.opacity(0.55) : Color.accentColor.opacity(0.45))
                .frame(width: max(2, (geo.size.width - density.iconSize - 6) * fraction), height: 2)
                .offset(x: density.iconSize + 6, y: geo.size.height - 2)
        }
        .accessibilityHidden(true)
    }

    private var blockButton: some View {
        let visible = hovering || isBlocked || confirming
        return Button(isBlocked ? "Engeli kaldır" : "Mobilde engelle",
                      systemImage: isBlocked ? "hand.raised.slash.fill" : "hand.raised",
                      action: blockTapped)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(isBlocked ? .red : .secondary)
            .frame(width: 16)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .help(isBlocked ? "Mobil veride engellendi — kaldırmak için tıkla" : "Mobil verideyken bu uygulamanın internetini kes")
    }

    @ViewBuilder
    private var menuItems: some View {
        if isBlocked {
            Button("Engeli kaldır", systemImage: "hand.raised.slash") { setBlocked(usage.app, false) }
        } else {
            Button("Mobilde engelle", systemImage: "hand.raised") { blockTapped() }
        }
        if expandable && !usage.domains.isEmpty {
            Button(expanded ? "Alan adlarını gizle" : "Alan adlarını göster") {
                withAnimation(.snappy) { expanded.toggle() }
            }
        }
        Divider()
        Button("Bağlantıları yenile", systemImage: "arrow.triangle.2.circlepath") { resetConnections(usage.app) }
        if usage.app.hasSuffix(".app") {
            Button("Uygulamayı yeniden başlat", systemImage: "arrow.clockwise") { restartApp(usage.app) }
        }
    }

    private func blockTapped() {
        if isBlocked { setBlocked(usage.app, false) }
        else { withAnimation(.snappy) { confirming.toggle() } }
    }

    private func accessibilityText(name: String) -> String {
        var parts = [name, Format.bytes(usage.bytes)]
        if let topDomain { parts.append(topDomain) }
        if usage.mobileBytes > 0 && usage.mobileBytes != usage.bytes { parts.append("mobil \(Format.bytes(usage.mobileBytes))") }
        if isBlocked { parts.append("mobilde engelli") }
        return parts.joined(separator: ", ")
    }
}
