import SwiftUI

/// Tek uygulama satırı: ikon, ad › alan adı, byte, engelle düğmesi ve açılır ▸ (en çok kullanılan alan adları).
/// Engelle eylemi VoiceOver (accessibilityAction) ve sağ tık menüsünden her zaman erişilebilir.
struct AppUsageRow: View {
    let usage: AppUsage
    let maxBytes: UInt64
    let isBlocked: Bool
    let isMobile: Bool
    let setBlocked: @MainActor (String, Bool) -> Void
    let resetConnections: @MainActor (String) -> Void
    let restartApp: @MainActor (String) -> Void
    @Environment(\.panelDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var confirming = false
    @State private var hovering = false

    private var expandable: Bool { !usage.domains.isEmpty }
    private var animation: Animation? { .panel(reduceMotion: reduceMotion) }

    var body: some View {
        let name = AppCatalog.shared.name(for: usage.app)
        VStack(alignment: .leading, spacing: 2) {
            line(name: name)
            if confirming {
                BlockConfirmation(name: name, isMobile: isMobile) {
                    withAnimation(animation) { confirming = false }
                } onConfirm: {
                    setBlocked(usage.app, true)
                    withAnimation(animation) { confirming = false }
                }
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if expanded {
                domainList
                    .transition(.opacity)
            }
        }
    }

    private var domainList: some View {
        VStack(spacing: 2) {
            ForEach(usage.domains, id: \.name) { d in
                HStack(spacing: 6) {
                    Text(d.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(Format.bytes(d.bytes)).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, density.iconSize + 6)
        .padding(.trailing, 20)
        .padding(.bottom, 4)
    }

    private var fraction: Double { Double(usage.bytes) / Double(max(1, maxBytes)) }

    private var topDomain: String? {
        guard let top = usage.domains.first?.name, top != AppCatalog.shared.name(for: usage.app) else { return nil }
        return top
    }

    private func toggleExpanded() {
        guard expandable else { return }
        withAnimation(animation) { expanded.toggle() }
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
                .frame(minWidth: 56, alignment: .trailing)
            blockButton
            chevron
        }
        .frame(height: density.rowHeight)
        .background(alignment: .bottomLeading) { usageBar }
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture { toggleExpanded() }
        .contextMenu { menuItems }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(name: name))
        .accessibilityValue(expandable ? (expanded ? "Açık" : "Kapalı") : "")
        .accessibilityAddTraits(expandable ? .isButton : [])
        .accessibilityHint(expandable ? "Alan adı dökümünü aç veya kapat" : "")
        .accessibilityAction { toggleExpanded() }
        .accessibilityAction(named: isBlocked ? "Engeli kaldır" : "Mobilde engelle") { blockTapped() }
        .help(topDomain.map { "\(name) › \($0)" } ?? name)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .animation(animation, value: expanded)
            .frame(width: 10)
            .opacity(expandable ? 1 : 0)
            .accessibilityHidden(true)
    }

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
        if expandable {
            Button(expanded ? "Alan adlarını gizle" : "Alan adlarını göster") { toggleExpanded() }
        }
        Divider()
        Button("Bağlantıları yenile", systemImage: "arrow.triangle.2.circlepath") { resetConnections(usage.app) }
        if usage.app.hasSuffix(".app") {
            Button("Uygulamayı yeniden başlat", systemImage: "arrow.clockwise") { restartApp(usage.app) }
        }
    }

    private func blockTapped() {
        if isBlocked { setBlocked(usage.app, false) }
        else { withAnimation(animation) { confirming.toggle() } }
    }

    private func accessibilityText(name: String) -> String {
        var parts = [name, Format.bytes(usage.bytes)]
        if let topDomain { parts.append(topDomain) }
        if usage.mobileBytes > 0 && usage.mobileBytes != usage.bytes { parts.append("mobil \(Format.bytes(usage.mobileBytes))") }
        if isBlocked { parts.append("mobilde engelli") }
        return parts.joined(separator: ", ")
    }
}
