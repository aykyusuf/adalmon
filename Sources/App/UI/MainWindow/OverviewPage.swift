import SwiftUI

/// Genel bakış = bugünün özeti. Gövde yalnızca küçük değer yapıları üretir; kartlar kendi girdileri değişmedikçe yeniden çizilmez.
struct OverviewPage: View {
    let model: AppModel
    let source: MainWindowDataSource
    let router: SettingsRouter
    @State private var dayStats = OverviewDayStats()

    var body: some View {
        let data = source.panelData()
        let now = Date.now
        let attention = OverviewAttention.items(
            data: data, rules: model.prefs.usageRules, statuses: model.ruleStatuses(now: now),
            ladder: model.rules.ladderStatus, burstThreshold: model.prefs.burstThresholdBytes)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: MainSection.overview.title) {
                    ConnectionBadge(medium: data.medium, isMobile: data.isMobile, interfaceName: data.interfaceName)
                }
                if !attention.isEmpty {
                    OverviewAttentionCard(items: attention, router: router)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)], spacing: 16) {
                    OverviewTodayCard(summary: TodaySummary.make(data: data, stats: dayStats))
                    OverviewBudgetCard(budget: model.budget(now: now), router: router)
                }
                OverviewTopAppsCard(rows: TopAppRow.top(data.today), showsFilterCallout: data.showsFilterCallout, router: router)
                OverviewLiveSection(data: data)
            }
            .padding(24)
        }
        .task { await refreshDayStats() }
    }

    /// Dün/↓↑ verisi sık değişmez: açılışta ve ardından 2 dakikada bir okunur (her saniye değil).
    private func refreshDayStats() async {
        while !Task.isCancelled {
            dayStats = await OverviewDayLoader.load(store: model.store)
            try? await Task.sleep(for: .seconds(120))
        }
    }
}
