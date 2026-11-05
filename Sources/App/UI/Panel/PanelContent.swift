import SwiftUI

/// Panelin saf görünümü: veri, ayar ve eylemleri dışarıdan alır (canlı panel, ayar önizlemesi ve test aynı görünümü çizer).
struct PanelContent: View {
    static let width: CGFloat = 372

    let data: PanelData
    @Binding var config: PanelConfig
    let actions: PanelActions

    var body: some View {
        let density = config.density
        VStack(alignment: .leading, spacing: density.sectionSpacing) {
            PanelHeader(data: data, config: $config, openSettings: actions.openSettings)
            ToastBanner(toast: data.toast, onUndo: actions.undoToast)
                .animation(.snappy, value: data.toast)
            ForEach(sectionsToShow) { section in
                sectionView(section)
            }
            PanelFooter(data: data, onQuit: actions.quit)
        }
        .padding(density.padding)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.panelDensity, density)
    }

    /// Görünür bölümler. Filtre yoksa iki liste yerine tek bir kurulum çağrısı (ilk listenin yerinde) gösterilir.
    private var sectionsToShow: [PanelSection] {
        var result = config.visibleSections
        if data.showsFilterCallout, let keep = result.first(where: { $0 == .last60 || $0 == .today }) {
            result.removeAll { ($0 == .last60 || $0 == .today) && $0 != keep }
        }
        return result
    }

    @ViewBuilder
    private func sectionView(_ section: PanelSection) -> some View {
        switch section {
        case .system:
            SystemSection(data: data, config: $config)
        case .networkChart:
            NetworkSection(data: data, config: $config)
        case .mobileCap:
            MobileCapView(data: data, config: $config)
        case .blockedApps:
            BlockedAppsSection(data: data, config: $config, actions: actions)
        case .last60, .today:
            if data.showsFilterCallout {
                FilterInstallCallout(state: data.installerState, onInstall: actions.installFilter)
            } else if section == .last60 {
                AppList(section: .last60, title: "Son 60 sn",
                        summary: "↓\(Format.bytes(data.downLast60)) ↑\(Format.bytes(data.upLast60))",
                        apps: data.last60, limit: config.last60Rows,
                        emptyText: "Şu an kayda değer trafik yok",
                        data: data, config: $config, actions: actions)
            } else {
                AppList(section: .today, title: "Bugün",
                        summary: "↓\(Format.bytes(data.downToday)) ↑\(Format.bytes(data.upToday))",
                        apps: data.today, limit: config.todayRows,
                        emptyText: "Henüz kayıt yok",
                        data: data, config: $config, actions: actions,
                        expandable: true, allowsShowMore: true)
            }
        }
    }
}
