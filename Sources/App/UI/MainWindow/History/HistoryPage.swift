import AppKit
import SwiftUI

/// Geçmiş: Gün (saatlik) / Hafta / Ay (günlük) yığılmış çubuklar + seçili çubuğun en çok kullananları
/// + seçili dönemin kısa raporu (geniş pencerede sağda, dar pencerede en altta).
/// Veri sayfa açılınca ve aralık değişince okunur; her saniye değil (dakikada bir sessiz yenileme yalnızca bugünü kapsayan aralıklarda).
struct HistoryPage: View {
    let store: UsageStore

    @State private var range: HistoryRange
    @State private var offset: Int
    @State private var reload = 0
    @State private var content = HistoryContent.empty
    @State private var isLoaded = false
    @State private var selectedID: String?
    @State private var report: HistoryReport?
    /// "Bu ay" kısayolu: rapor ayın 1'inden bugüne (grafik Ay aralığında kalır). Aralık/sayfa değişince kapanır.
    @State private var calendarMonth = false
    /// Kısayol aralığı değiştirirken `onChange(of: range)` sayfayı 0'a çekmesin diye istenen sayfa.
    @State private var pendingOffset: Int?
    @State private var isWide = false

    /// Yan yana yerleşim için gereken en küçük içerik genişliği (grafik ~560 + 16 + rapor 380).
    private static let wideThreshold: CGFloat = 960

    /// `initialRange`/`initialOffset` yalnızca önizleme ve testler için; uygulama varsayılanı Gün / bugün.
    init(store: UsageStore, initialRange: HistoryRange = .day, initialOffset: Int = 0) {
        self.store = store
        _range = State(initialValue: initialRange)
        _offset = State(initialValue: initialOffset)
    }

    private var reportPeriod: HistoryReportPeriod {
        HistoryReportPeriod.make(range: range, offset: offset, calendarMonth: calendarMonth)
    }

    private var selectedPreset: HistoryReportPreset? {
        if range == .month, offset == 0, calendarMonth { return .thisMonth }
        if range == .day, offset == 1 { return .yesterday }
        if range == .week, offset == 0 { return .lastWeek }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: MainSection.history.title) {
                    HistoryControls(range: $range, offset: $offset, periodTitle: content.periodTitle)
                }
                // Alt öğe sırası iki yerleşimde de aynı (AnyLayout): geçişte görünümler yeniden kurulmaz.
                let layout = isWide
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                layout {
                    VStack(alignment: .leading, spacing: 16) {
                        HistoryChartCard(content: content, isLoaded: isLoaded, range: range, selectedID: $selectedID)
                        if let bar = content.bars.first(where: { $0.id == selectedID }) {
                            HistoryDetailCard(bar: bar, bars: content.bars, store: store, selectedID: $selectedID)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    HistoryReportCard(report: report, isCurrent: report?.period == reportPeriod, store: store,
                                      selectedPreset: selectedPreset, onPreset: apply)
                        .frame(width: isWide ? 380 : nil)
                        .frame(maxWidth: isWide ? nil : .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: Bool.self) { $0.size.width >= Self.wideThreshold } action: { isWide = $0 }
            .padding(24)
        }
        .task(id: HistoryRequest(range: range, offset: offset, reload: reload)) { await load() }
        .task(id: HistoryReportRequest(period: reportPeriod, reload: reload)) { await loadReport() }
        .task { await autoRefresh() }
        .onChange(of: range) {
            offset = pendingOffset ?? 0
            pendingOffset = nil
            selectedID = nil
            if range != .month { calendarMonth = false }
        }
        .onChange(of: offset) {
            selectedID = nil
            if offset != 0 { calendarMonth = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if offset == 0 { reload += 1 }
        }
    }

    private func loadReport() async {
        let period = reportPeriod
        let loaded = await HistoryReportLoader.load(period: period, store: store)
        guard !Task.isCancelled else { return }
        report = loaded
    }

    /// Rapor kısayolu: grafiği ve raporu aynı döneme getirir.
    private func apply(_ preset: HistoryReportPreset) {
        switch preset {
        case .yesterday: move(to: .day, offset: 1, calendarMonth: false)
        case .lastWeek: move(to: .week, offset: 0, calendarMonth: false)
        case .thisMonth: move(to: .month, offset: 0, calendarMonth: true)
        }
    }

    private func move(to newRange: HistoryRange, offset newOffset: Int, calendarMonth month: Bool) {
        calendarMonth = month
        if range == newRange {
            offset = newOffset
        } else {
            pendingOffset = newOffset
            range = newRange
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
