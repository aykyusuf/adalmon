import SwiftUI

/// "Uygulama geçmişi": seçilen pencerede (1 sa … 7 gün) uygulama başına CPU/GPU süresi, disk yazma, ağ, enerji, bellek tepe;
/// Görev Yöneticisi'nin "Uygulama geçmişi" sekmesi gibi sıralanabilir ısı haritalı tablo. Satır seçilince zaman grafiği.
struct ProcessHistoryView: View {
    let store: UsageStore
    @State private var window: ResourceWindow = .hours6
    @State private var rows: [AppHistoryRow] = []
    @State private var hints: [String: String] = [:]
    @State private var sortColumn: HistoryColumn = .cpu
    @State private var sortAscending = false
    @State private var selected: String?
    @State private var series: [ResourceSeriesPoint] = []
    @State private var firstRecord: Int?
    @State private var loaded = false
    @Environment(\.colorScheme) private var scheme

    private struct Request: Hashable {
        var window: ResourceWindow
        var selected: String?
        var metric: ResourceMetric?
    }

    private var chartMetric: ResourceMetric { sortColumn.resourceMetric ?? .cpu }
    private var coverage: Double { ResourceFormat.coverage(window: window, firstRecord: firstRecord) }

    var body: some View {
        let sorted = sortedRows
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("Pencere", selection: $window) {
                    ForEach(ResourceWindow.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                if loaded, firstRecord != nil, coverage < Double(window.seconds) - 120 {
                    Text("Kayıt \(ResourceFormat.duration(seconds: coverage)) önce başladı").font(.caption).foregroundStyle(.secondary)
                }
            }
            if loaded && firstRecord == nil {
                ResourceCard(title: "Uygulama geçmişi", systemImage: "chart.bar.doc.horizontal") { ResourceEmptyNote(text: ResourceEmptyText.collecting) }
                Spacer(minLength: 0)
            } else {
                header(sorted)
                Divider()
                List(selection: $selected) {
                    ForEach(sorted) { row in
                        HistoryRowView(row: row, maxima: maxima, dark: scheme == .dark, hint: hints[row.app])
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, ProcessTableLayout.rowHeight)
                .overlay { if sorted.isEmpty { ContentUnavailableView("Bu pencerede kayıt yok", systemImage: "chart.bar.doc.horizontal") } }
                if selected != nil, series.contains(where: { $0.value > 0 }) { detailChart }
            }
        }
        .task(id: Request(window: window, selected: selected, metric: chartMetric)) { await refreshLoop() }
    }

    // MARK: Veri

    private var sortedRows: [AppHistoryRow] {
        rows.sorted { a, b in
            if sortColumn == .name {
                let c = ResourceDisplay.name(a.app).localizedStandardCompare(ResourceDisplay.name(b.app))
                return sortAscending ? c == .orderedAscending : c == .orderedDescending
            }
            let x = sortColumn.value(of: a), y = sortColumn.value(of: b)
            if x != y { return sortAscending ? x < y : x > y }
            return a.app < b.app
        }
    }

    private var maxima: [HistoryColumn: Double] {
        Dictionary(uniqueKeysWithValues: HistoryColumn.numeric.map { c in (c, rows.map { c.value(of: $0) }.max() ?? 0) })
    }

    private func header(_ rows: [AppHistoryRow]) -> some View {
        HStack(spacing: 0) {
            Button { sort(.name) } label: {
                HStack(spacing: 4) {
                    Text("Ad").font(.callout.weight(.medium))
                    indicator(.name)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .frame(height: 44, alignment: .bottomLeading)
                .padding(.bottom, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            ForEach(HistoryColumn.numeric) { column in
                Button { sort(column) } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(column == .memory ? "" : column.text(rows.reduce(0) { $0 + column.value(of: $1) }))
                            .font(.callout.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        HStack(spacing: 3) {
                            indicator(column)
                            Text(column.title).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(width: column.width, height: 44, alignment: .trailing)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(column.title), sırala")
            }
        }
        .padding(.horizontal, 0)
    }

    @ViewBuilder
    private func indicator(_ column: HistoryColumn) -> some View {
        if sortColumn == column {
            Image(systemName: sortAscending ? "chevron.up" : "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private func sort(_ column: HistoryColumn) {
        if sortColumn == column { sortAscending.toggle() } else { sortColumn = column; sortAscending = column == .name }
    }

    private var detailChart: some View {
        ResourceCard(title: "\(ResourceDisplay.name(selected ?? "")) · \(chartMetric.title) · son \(window.title)", systemImage: "chart.xyaxis.line") {
            ResourceSeriesChart(points: series, metric: chartMetric, window: window).frame(height: 150)
        }
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(for: .seconds(60), tolerance: .seconds(10))
        }
    }

    private func load() async {
        let all = await store.appHistoryRows(window: window)
        let range = await store.resourceTimeRange()
        rows = all
        hints = DuplicateNameHints.hints(keys: all.map(\.app), name: { ResourceDisplay.name($0) })
        firstRecord = range?.first
        if let selected {
            series = await store.resourceSeries(app: selected, metric: chartMetric, window: window)
        } else {
            series = []
        }
        loaded = true
    }
}
