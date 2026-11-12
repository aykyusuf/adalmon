import SwiftUI

/// Genel bakış ("Kompakt pano"): üstte tıklanabilir özet karoları, ortada tek "En çok kullananlar" listesi
/// [Ağ | CPU | Bellek], altta ince durum şeridi. Kaydırma yok: liste satır sayısı kalan yüksekliğe göre seçilir.
///
/// Pil: canlı değerler sayfa görünürken ölçüm adımıyla gelir; liste kendi görevini yalnızca görünürken çalıştırır
/// (Ağ: saniyede bir bellekten, CPU/Bellek: dakikada bir kayıttan). Yeni zamanlayıcı/örnekleyici yok.
struct OverviewPage: View {
    let model: AppModel
    let source: MainWindowDataSource
    let router: SettingsRouter
    @State private var dayStats = OverviewDayStats()
    @State private var tab: OverviewListTab

    init(model: AppModel, source: MainWindowDataSource, router: SettingsRouter, initialTab: OverviewListTab = .network) {
        self.model = model
        self.source = source
        self.router = router
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        let data = source.panelData()
        let now = Date.now
        let attention = OverviewAttention.items(
            data: data, rules: model.prefs.usageRules, statuses: model.ruleStatuses(now: now),
            ladder: model.rules.ladderStatus, burstThreshold: model.prefs.burstThresholdBytes)
        let tiles = OverviewTile.all(data: data, today: TodaySummary.make(data: data, stats: dayStats), budget: data.budget ?? model.budget(now: now))
        // Ajan servisi tembel kurulur: özellik kapalıyken dokunulmaz.
        let agents = model.prefs.agentsEnabled ? model.agents.monitor.summary : nil
        GeometryReader { page in
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: MainSection.overview.title)
                FilterLinkBanner(level: data.filterAlert, canReconnect: data.installerState == .active,
                                 onReconnect: { model.reconnectFilter() }, onOpenSettings: { router.open(.filter) })
                OverviewTileGrid(tiles: tiles, width: max(0, page.size.width - 48), router: router)
                GeometryReader { area in
                    topList(maxRows: OverviewLayout.listRows(height: area.size.height))
                        .frame(width: area.size.width, height: area.size.height, alignment: .top)
                }
                OverviewStatusStrip(attention: attention, agents: agents, data: data, router: router)
            }
            .padding(24)
            .frame(width: page.size.width, height: page.size.height, alignment: .topLeading)
        }
        .task { await refreshDayStats() }
    }

    @ViewBuilder private func topList(maxRows: Int) -> some View {
        let header = AnyView(OverviewListHeader(tab: $tab))
        switch tab {
        case .network:
            LiveAppUsageList(source: source.liveRows ?? .live(model), controls: .live(model), maxRows: maxRows, compact: true,
                             initialRange: .hour1, showsToday: true, headerLeading: header,
                             moreAction: { OverviewTileKind.network.destination.open(router) })
        case .cpu, .memory:
            OverviewResourceList(store: model.store, metric: tab == .cpu ? .cpu : .memoryPeak, maxRows: maxRows,
                                 header: header, router: router)
                .id(tab)
        }
    }

    private func refreshDayStats() async {
        while !Task.isCancelled {
            dayStats = await OverviewDayLoader.load(store: model.store)
            try? await Task.sleep(for: .seconds(120))
        }
    }
}
