import AppKit
import SwiftUI

/// Geçmiş: Gün (saatlik) / Hafta / Ay (günlük) yığılmış çubuklar + seçili çubuğun en çok kullananları.
/// Veri sayfa açılınca ve aralık değişince okunur; her saniye değil (dakikada bir sessiz yenileme yalnızca bugünü kapsayan aralıklarda).
struct HistoryPage: View {
    let store: UsageStore

    @State private var range = HistoryRange.day
    @State private var offset = 0
    @State private var reload = 0
    @State private var content = HistoryContent.empty
    @State private var isLoaded = false
    @State private var selectedID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: MainSection.history.title) {
                    HistoryControls(range: $range, offset: $offset, periodTitle: content.periodTitle)
                }
                HistoryChartCard(content: content, isLoaded: isLoaded, range: range, selectedID: $selectedID)
                if let bar = content.bars.first(where: { $0.id == selectedID }) {
                    HistoryDetailCard(bar: bar, bars: content.bars, store: store, selectedID: $selectedID)
                }
            }
            .padding(24)
        }
        .task(id: HistoryRequest(range: range, offset: offset, reload: reload)) { await load() }
        .task { await autoRefresh() }
        .onChange(of: range) {
            offset = 0
            selectedID = nil
        }
        .onChange(of: offset) { selectedID = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if offset == 0 { reload += 1 }
        }
    }

    private func load() async {
        let loaded = await HistoryLoader.load(range: range, offset: offset, store: store)
        guard !Task.isCancelled else { return }
        content = loaded
        isLoaded = true
        if selectedID == nil || !loaded.bars.contains(where: { $0.id == selectedID }) {
            selectedID = loaded.defaultSelection
        }
    }

    /// Bugünü kapsayan aralıklar dakikada bir yenilenir (uygulama arka plandaysa atlanır).
    private func autoRefresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            if offset == 0, NSApp.isActive { reload += 1 }
        }
    }
}
