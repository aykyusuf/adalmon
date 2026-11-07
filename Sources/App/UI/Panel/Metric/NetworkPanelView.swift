import SwiftUI

struct NetworkPanelView: View {
    let model: NetworkPanelModel
    let data: PanelData
    @Binding var config: PanelConfig
    let actions: PanelActions
    var maxHeight: CGFloat?
    var previewHover: Double?

    var body: some View {
        PanelScaffold(kind: .network, actions: actions, opensMainWindow: data.opensMainWindow,
                      subtitle: model.interfaceName.isEmpty ? model.connectionTitle : "\(model.connectionTitle) · \(model.interfaceName)",
                      maxHeight: maxHeight) {
            PanelCard(tint: .cyan) {
                VStack(alignment: .leading, spacing: 10) {
                    speed("İndirme", "arrow.down", model.downText, model.todayDown, model.downSeries, .cyan)
                    Divider().opacity(0.5)
                    speed("Yükleme", "arrow.up", model.upText, model.todayUp, model.upSeries, .pink)
                }
            }
            if data.showsFilterCallout {
                FilterInstallCallout(state: data.installerState, onInstall: actions.installFilter)
            }
            if data.budget != nil || data.dailyCapBytes > 0 {
                MobileQuotaRow(data: data)
            }
            if !data.showsFilterCallout {
                PanelCard {
                    AppList(section: .last60, title: "Son 60 sn", summary: "↓\(Format.bytes(data.downLast60)) ↑\(Format.bytes(data.upLast60))",
                            apps: data.last60, limit: max(3, config.last60Rows), emptyText: "Şu an kayda değer trafik yok",
                            data: data, config: $config, actions: actions)
                }
                PanelCard {
                    AppList(section: .today, title: "Bugün", summary: "↓\(Format.bytes(data.downToday)) ↑\(Format.bytes(data.upToday))",
                            apps: data.today, limit: max(5, config.todayRows), emptyText: "Henüz kayıt yok",
                            data: data, config: $config, actions: actions, allowsShowMore: true)
                }
            }
            if !data.blockedApps.isEmpty {
                BlockedAppsSection(data: data, config: $config, actions: actions)
            }
        } footer: {
            PanelFooterButton(title: data.opensMainWindow ? "Ağ kullanımını aç" : "Ayarlar'ı aç", systemImage: "network") {
                if data.opensMainWindow { actions.openRoute(.network) } else { actions.openApp() }
            }
        }
    }

    private func speed(_ title: String, _ symbol: String, _ rate: String, _ today: String, _ series: PanelSeries, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: symbol).labelStyle(PanelTitleLabelStyle(tint: tint)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(rate).font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
            }
            PanelHoverSparkline(series: series, tint: tint, height: 44, previewHover: previewHover)
            HStack { Text("Bugün").foregroundStyle(.secondary); Spacer(); Text(today).fontWeight(.medium) }
                .font(.caption).monospacedDigit()
        }
    }
}
