import SwiftUI

struct MobileDataPage: View, Equatable {
    let data: PanelData
    let actions: PanelActions
    let model: AppModel

    /// Yalnızca sayfanın gösterdiği veri (`.equatable()`); modelden doğrudan okunanlar sayfayı kendi gözlemiyle yeniler.
    nonisolated static func == (lhs: MobileDataPage, rhs: MobileDataPage) -> Bool { lhs.data == rhs.data }

    @State private var series: [CumulativePoint] = []
    @State private var seriesLoaded = false

    var body: some View {
        let budget = model.budget()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: MainSection.mobile.title) {
                    ConnectionBadge(medium: data.medium, isMobile: data.isMobile, interfaceName: data.interfaceName)
                }
                MobileTodayCard(budget: budget, ladder: model.rules.ladderStatus, dailyCapBytes: data.dailyCapBytes,
                                isMobile: data.isMobile, forceMobile: model.prefs.forceMobile)
                MobileCumulativeChart(points: series, loaded: seriesLoaded, budgetBytes: budget.effectiveDailyCapBytes,
                                      dailyCapBytes: data.dailyCapBytes)
                MobileCycleCard(budget: budget)
                HStack(spacing: 16) {
                    statCard("Wi-Fi bugün", value: Format.bytes(data.wifiToday), systemImage: "wifi")
                    statCard("Sistem/diğer mobil", value: Format.bytes(data.unattributedMobile), systemImage: "gearshape.2",
                             help: "Arayüz sayacı ile uygulamalara yazılan trafik arasındaki fark (DNS, sistem, VPN vb.)")
                }
                if data.showsFilterCallout {
                    FilterInstallCallout(state: data.installerState, onInstall: actions.installFilter)
                } else {
                    MobileTopApps(apps: topMobileApps)
                }
                MobileSettingsGroup(model: model, blocked: model.prefs.blockedOnMobile)
                    .padding(.top, 8)
            }
            .padding(24)
        }
        .task {
            // Sayfa görünürken ~15 sn'de bir; görünüm kapanınca görev iptal olur.
            while !Task.isCancelled {
                series = await model.todayMobileCumulativeSeries()
                seriesLoaded = true
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private var topMobileApps: [AppUsage] {
        Array(data.today.filter { $0.mobileBytes > 0 }.sorted { $0.mobileBytes > $1.mobileBytes }.prefix(8))
    }

    private func statCard(_ title: String, value: String, systemImage: String, help: String = "") -> some View {
        MobileCard(title, systemImage: systemImage) {
            Text(value)
                .font(.title.weight(.semibold))
                .monospacedDigit()
        }
        .help(help)
        .accessibilityElement(children: .combine)
    }
}
