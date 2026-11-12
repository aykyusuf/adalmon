import SwiftUI

struct NetworkUsagePage: View, Equatable {
    let data: PanelData
    let limits: [String: AppLimit]
    let actions: PanelActions
    let model: AppModel
    let router: SettingsRouter

    /// Yalnızca sayfanın gösterdiği veri; eylem kapanışları/model/router kimlik olarak sabittir. `.equatable()` ile
    /// ölçüm adımı bu veriyi değiştirmediyse gövde (ve tablo) yeniden çalışmaz.
    nonisolated static func == (lhs: NetworkUsagePage, rhs: NetworkUsagePage) -> Bool {
        lhs.data == rhs.data && lhs.limits == rhs.limits
    }

    @State private var query = ""
    @State private var sortOrder = [KeyPathComparator(\AppUsageTableRow.total, order: .reverse)]
    @State private var selectedID: String?
    @State private var showInspector = false
    @State private var pendingBlock: AppUsageTableRow?

    var body: some View {
        let rows = visibleRows
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: MainSection.network.title) {
                Text("Bugün ↓\(Format.bytes(data.downToday)) ↑\(Format.bytes(data.upToday))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 24)
            FilterLinkBanner(level: data.filterAlert, canReconnect: data.installerState == .active,
                             onReconnect: actions.reconnectFilter, onOpenSettings: actions.openFilterSettings)
                .padding(.horizontal, 24)
            if data.showsFilterCallout {
                FilterInstallCallout(state: data.installerState, onInstall: actions.installFilter)
                    .padding(.horizontal, 24)
                Spacer()
            } else {
                LiveAppUsageList(source: .live(model), controls: .live(model), maxRows: 5)
                    .padding(.horizontal, 24)
                NetworkUsageTable(rows: rows, isSearching: !query.isEmpty, selection: $selectedID, sortOrder: $sortOrder,
                                  onShowDetails: select, onToggleBlock: toggleBlock, onClose: closeInspector)
            }
        }
        .padding(.top, 24)
        .searchable(text: $query, prompt: "Uygulama veya alan adı ara")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Uygulama ayrıntıları", systemImage: "sidebar.trailing", action: toggleInspector)
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .help(showInspector ? "Ayrıntı panelini gizle (⌥⌘I)" : "Ayrıntı panelini göster (⌥⌘I)")
            }
        }
        .inspector(isPresented: $showInspector) {
            NetworkInspectorPanel(selectedID: selectedID, data: data, model: model, actions: actions,
                                  onToggleBlock: toggleBlock(id:), onClose: closeInspector)
                .inspectorColumnWidth(min: 300, ideal: 320, max: 380)
        }
        .onAppear(perform: consumeDeepLink)
        .onChange(of: router.selectedAppID) { consumeDeepLink() }
        // Seçim ve panel birlikte hareket eder: seçim → açılır, seçim kalkarsa → kapanır, panel kapanırsa → seçim kalkar.
        .onChange(of: selectedID) { showInspector = selectedID != nil }
        .onChange(of: showInspector) { if !showInspector { selectedID = nil } }
        .confirmationDialog(
            pendingBlock.map { "\($0.name) mobil veride engellensin mi?" } ?? "",
            isPresented: Binding(get: { pendingBlock != nil }, set: { if !$0 { pendingBlock = nil } }),
            titleVisibility: .visible,
            presenting: pendingBlock
        ) { row in
            Button("Engelle", role: .destructive) { actions.setBlocked(row.id, true) }
        } message: { _ in
            Text(data.isMobile ? "Şu an mobil verideysin; uygulamanın interneti hemen kesilir." : "Şu an Wi-Fi'desin, etkilenmez; mobil veriye geçince uygulanır.")
        }
    }

    private var visibleRows: [AppUsageTableRow] {
        data.today
            .map { AppUsageTableRow(usage: $0, blocked: data.blockedApps, limits: limits) }
            .filter { $0.matches(query) }
            .sorted(using: sortOrder)
    }

    private func select(_ id: String) {
        selectedID = id
        showInspector = true
    }

    /// Araç çubuğu düğmesi (⌥⌘I): açıkken kapatır, kapalıyken açar (seçim yoksa "seçilmedi" durumu görünür).
    private func toggleInspector() {
        if showInspector { closeInspector() } else { showInspector = true }
    }

    private func closeInspector() {
        showInspector = false
        selectedID = nil
    }

    /// Genel bakıştan gelen derin bağlantı: satırı seç, ayrıntı panelini aç (bir kez).
    private func consumeDeepLink() {
        guard let id = router.selectedAppID else { return }
        query = ""
        select(id)
        router.selectedAppID = nil
    }

    private func toggleBlock(_ row: AppUsageTableRow) {
        toggleBlock(id: row.id, name: row.name, isBlocked: row.isBlocked)
    }

    private func toggleBlock(id: String) {
        toggleBlock(id: id, name: AppCatalog.shared.name(for: id), isBlocked: data.isBlocked(id))
    }

    private func toggleBlock(id: String, name: String, isBlocked: Bool) {
        if isBlocked {
            actions.setBlocked(id, false)
        } else {
            pendingBlock = data.today.first { $0.app == id }.map { AppUsageTableRow(usage: $0, blocked: data.blockedApps, limits: limits) }
                ?? AppUsageTableRow(id: id, name: name, domains: [], total: 0, mobile: 0, isBlocked: false, limit: nil)
        }
    }
}
