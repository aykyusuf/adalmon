import SwiftUI

/// Uygulama listesi bölümü ("Son 60 sn", "Bugün"): daraltılabilir başlık, sınırlı satır ve isteğe bağlı "+N daha".
struct AppList: View {
    let section: PanelSection
    let title: String
    let summary: String
    let apps: [AppUsage]
    let limit: Int
    let emptyText: String
    let data: PanelData
    @Binding var config: PanelConfig
    let actions: PanelActions
    /// Satıra dokununca alan adı dökümü açılsın mı.
    var expandable = false
    /// Sınırın ötesindeki satırlar "+N daha" ile açılabilsin mi.
    var allowsShowMore = false
    @State private var showAll = false

    private static let expandedLimit = 30

    var body: some View {
        let collapsed = config.isCollapsed(section)
        let visibleCount = showAll ? max(limit, Self.expandedLimit) : limit
        let shown = Array(apps.prefix(visibleCount))
        VStack(alignment: .leading, spacing: 0) {
            PanelSectionHeader(title: title, isCollapsed: collapsed) {
                withAnimation(.snappy) { config.toggleCollapsed(section) }
            } accessory: {
                Text(summary)
            }
            .padding(.bottom, 3)
            if !collapsed {
                if apps.isEmpty {
                    Text(emptyText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 2)
                } else {
                    let maxBytes = apps.first?.bytes ?? 1
                    ForEach(shown) { usage in
                        AppUsageRow(usage: usage, maxBytes: maxBytes, isBlocked: data.isBlocked(usage.app),
                                    isMobile: data.isMobile, expandable: expandable, setBlocked: actions.setBlocked,
                                    resetConnections: actions.resetConnections, restartApp: actions.restartApp)
                    }
                    moreButton(hidden: apps.count - shown.count)
                }
            }
        }
    }

    @ViewBuilder
    private func moreButton(hidden: Int) -> some View {
        if allowsShowMore, hidden > 0 || showAll, apps.count > limit {
            Button(showAll ? "Daha az" : "+\(hidden) daha") {
                withAnimation(.snappy) { showAll.toggle() }
            }
            .buttonStyle(.link)
            .font(.caption)
            .padding(.top, 2)
            .accessibilityLabel(showAll ? "Daha az göster" : "\(hidden) uygulama daha göster")
        }
    }
}
