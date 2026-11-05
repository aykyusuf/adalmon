import SwiftUI

/// Mobil veride engellenen uygulamalar. Liste boşsa hiç görünmez.
struct BlockedAppsSection: View {
    let data: PanelData
    @Binding var config: PanelConfig
    let actions: PanelActions
    @Environment(\.panelDensity) private var density

    var body: some View {
        let apps = data.blockedApps
        if !apps.isEmpty {
            let collapsed = config.isCollapsed(.blockedApps)
            VStack(alignment: .leading, spacing: 2) {
                PanelSectionHeader(title: "Mobilde engellenenler", isCollapsed: collapsed, tint: .red) {
                    withAnimation(.snappy) { config.toggleCollapsed(.blockedApps) }
                } accessory: {
                    Text(data.isMobile ? "\(apps.count) engelli" : "\(apps.count) · Wi-Fi'de serbest")
                }
                if !collapsed {
                    ForEach(apps, id: \.self) { app in
                        HStack(spacing: 6) {
                            Image(nsImage: AppCatalog.shared.icon(for: app))
                                .resizable()
                                .frame(width: density.iconSize, height: density.iconSize)
                                .accessibilityHidden(true)
                            Text(AppCatalog.shared.name(for: app))
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            Button("Kaldır") { actions.setBlocked(app, false) }
                                .buttonStyle(.link)
                                .font(.caption)
                                .accessibilityLabel("\(AppCatalog.shared.name(for: app)) engelini kaldır")
                        }
                        .frame(height: density.rowHeight)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.06), in: .rect(cornerRadius: 10))
        }
    }
}
