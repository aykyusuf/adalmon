import SwiftUI

/// Süreçler sayfası: İşlemler | Performans | Tarayıcılar | Uygulama geçmişi | Başlangıç | Disk | Temizlik (Görev Yöneticisi gibi). Canlı örnekleme
/// yalnızca İşlemler ve Performans sekmelerinde, sayfa ve pencere görünürken çalışır.
struct ProcessesPage: View {
    let model: AppModel
    @Bindable var router: SettingsRouter
    @State private var live = ProcessLiveModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: MainSection.processes.title) {}
                .padding(.horizontal, 24)
            CapsuleTabBar(selection: $router.processesTab)
                .padding(.horizontal, 24)
            BoundedHeight { content }
        }
        .padding(.top, 24)
        .task(id: router.processesTab.needsLiveSampling) {
            guard router.processesTab.needsLiveSampling else { return }
            await live.run(service: model.resources, model: model)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch router.processesTab {
        case .processes: ProcessTableView(model: model, router: router, live: live)
        case .performance: PerformanceView(model: model, live: live)
        case .browsers: BrowserTabsView(model: model).padding(.horizontal, 24)
        case .history: ProcessHistoryView(store: model.store).padding(.horizontal, 24)
        case .startup: StartupItemsView().padding(.horizontal, 24)
        case .disk: ProcessDiskView(model: model).padding(.horizontal, 24)
        case .cleanup: CleanupView().padding(.horizontal, 24)
        }
    }
}
