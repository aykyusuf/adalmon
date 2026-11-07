import SwiftUI

struct PanelContent: View {
    static let width: CGFloat = 372

    let data: PanelData
    @Binding var config: PanelConfig
    let actions: PanelActions
    /// Panelin (alt bilgi + dolgular dahil) alabileceği en büyük yükseklik. `nil` ise sınırsız (ör. anlık görüntü testleri);
    /// aşılırsa üst bölümler kaydırılır, alt bilgi her zaman görünür kalır.
    var maxHeight: CGFloat?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Kaydırılan gövdenin doğal (sınırsız) yüksekliği; `onGeometryChange` ile ölçülür.
    @State private var bodyHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

    init(data: PanelData, config: Binding<PanelConfig>, actions: PanelActions, maxHeight: CGFloat? = nil) {
        self.data = data
        self._config = config
        self.actions = actions
        self.maxHeight = maxHeight
    }

    var body: some View {
        let density = config.density
        VStack(alignment: .leading, spacing: density.sectionSpacing) {
            if maxHeight != nil {
                ScrollView {
                    sectionStack(density: density)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: scrollHeight(density: density))
            } else {
                sectionStack(density: density)
            }
            PanelFooter(data: data, onQuit: actions.quit)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .padding(density.padding)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .environment(\.panelDensity, density)
    }

    /// Kaydırma alanının yüksekliği: gövde sığıyorsa gövde kadar, sığmıyorsa kalan yer kadar. Ölçüm gelmeden önce `nil` (doğal).
    private func scrollHeight(density: PanelDensity) -> CGFloat? {
        guard let maxHeight, bodyHeight > 0 else { return nil }
        let available = maxHeight - 2 * density.padding - footerHeight - density.sectionSpacing
        return max(120, min(bodyHeight, available))
    }

    private func sectionStack(density: PanelDensity) -> some View {
        VStack(alignment: .leading, spacing: density.sectionSpacing) {
            PanelHeader(data: data, config: $config, openApp: actions.openApp, openSettings: actions.openSettings)
            ToastBanner(toast: data.toast, onUndo: actions.undoToast) { action in
                switch action {
                case .restart(let app): actions.restartApp(app)
                }
            }
            .animation(.panel(reduceMotion: reduceMotion), value: data.toast)
            ForEach(sectionsToShow) { section in
                sectionView(section)
            }
        }
    }

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
            if !config.visibleCards.isEmpty {
                PanelCardGrid(data: data, cards: config.visibleCards, onOpen: actions.openApp)
            }
        case .battery:
            BatteryPanelSection(data: data, config: $config)
        case .mobileCap:
            MobileQuotaRow(data: data)
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
                        allowsShowMore: true)
            }
        }
    }
}
