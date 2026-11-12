import SwiftUI

/// Elle engellenen uygulamalar (kapsam rozetiyle: Mobilde / Wi-Fi'de / Her yerde). Liste boşsa hiç görünmez.
struct BlockedAppsSection: View {
    let data: PanelData
    @Binding var config: PanelConfig
    let actions: PanelActions
    @Environment(\.panelDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let apps = data.blockedEntries
        if !apps.isEmpty {
            let collapsed = config.isCollapsed(.blockedApps)
            VStack(alignment: .leading, spacing: 2) {
                PanelSectionHeader(title: "Engellenenler", isCollapsed: collapsed, tint: .red) {
                    withAnimation(.panel(reduceMotion: reduceMotion)) { config.toggleCollapsed(.blockedApps) }
                } accessory: {
                    let active = apps.filter { $0.isActive(onMobile: data.isMobile) }.count
                    Text(active == apps.count ? "\(apps.count) engelli" : "\(apps.count) · şu an \(active) etkin")
                }
                if !collapsed {
                    ForEach(apps) { entry in
                        let app = entry.app
                        HStack(spacing: 6) {
                            Image(nsImage: AppCatalog.shared.icon(for: app))
                                .resizable()
                                .frame(width: density.iconSize, height: density.iconSize)
                                .accessibilityHidden(true)
                            Text(AppCatalog.shared.name(for: app))
                                .font(.callout)
                                .lineLimit(1)
                            BlockScopeBadge(scope: entry.scope)
                            Spacer()
                            Button("Kaldır") { actions.setBlockScope(app, nil) }
                                .buttonStyle(.link)
                                .font(.caption)
                                .accessibilityLabel("\(AppCatalog.shared.name(for: app)) engelini kaldır")
                        }
                        .frame(height: density.rowHeight)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.08), in: .rect(cornerRadius: PanelMetricCard.cornerRadius, style: .continuous))
        }
    }
}
