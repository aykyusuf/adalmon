import Charts
import SwiftUI

/// "Geçmiş": pencere + ölçüt seçici, sıralı çubuk listesi, seçili uygulamanın zaman grafiği.
struct ProcessHistoryView: View {
    let store: UsageStore
    @State private var window: ResourceWindow = .hours6
    @State private var metric: ResourceMetric = .cpu
    @State private var selected: String?
    @State private var ranks: [ResourceRank] = []
    @State private var series: [ResourceSeriesPoint] = []
    @State private var firstRecord: Int?
    @State private var loaded = false

    private struct Request: Hashable {
        var window: ResourceWindow
        var metric: ResourceMetric
        var selected: String?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if loaded && firstRecord == nil {
                    ResourceCard(title: metric.title, systemImage: metric.symbol) { ResourceEmptyNote(text: ResourceEmptyText.collecting) }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) { rankCard.frame(minWidth: 420); detailCard.frame(minWidth: 380) }
                        VStack(spacing: 14) { rankCard; detailCard }
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .task(id: Request(window: window, metric: metric, selected: selected)) { await refreshLoop() }
    }

    private var coverage: Double { ResourceFormat.coverage(window: window, firstRecord: firstRecord) }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Pencere", selection: $window) {
                ForEach(ResourceWindow.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 280)
            Picker("Ölçüt", selection: $metric) {
                ForEach(ResourceMetric.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 170)
            Spacer()
        }
    }

    private var rankCard: some View {
        ResourceCard(title: "En çok: \(metric.title) · son \(window.title)", systemImage: metric.symbol) {
            if ranks.isEmpty {
                ResourceEmptyNote(text: loaded ? "Bu pencerede kayıt yok." : "Yükleniyor…")
            } else {
                let peak = max(1, ranks.first?.value ?? 1)
                ForEach(ranks) { rank in
                    Button { selected = rank.app } label: {
                        ResourceRankRow(rank: rank, fraction: rank.value / peak, metric: metric, coverage: coverage,
                                        isSelected: rank.app == selected)
                    }
                    .buttonStyle(.plain)
                }
                if coverage < Double(window.seconds) - 120 {
                    Text("Kayıt \(ResourceFormat.duration(seconds: coverage)) önce başladı; pencere kısmen dolu.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if metric == .memoryAvg || metric == .memoryPeak {
                    Text("Bellek, dakikalık kayıtta ilk 15'e giren uygulamalar için tutulur.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var detailCard: some View {
        ResourceCard(title: selected.map { ResourceDisplay.name($0) } ?? "Ayrıntı", systemImage: "chart.xyaxis.line") {
            if selected == nil || series.allSatisfy({ $0.value == 0 }) {
                ResourceEmptyNote(text: selected == nil ? "Soldan bir uygulama seç." : "Bu pencerede bu ölçüt için değer yok.")
            } else {
                ResourceSeriesChart(points: series, metric: metric, window: window)
                    .frame(height: 200)
            }
        }
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(for: .seconds(60), tolerance: .seconds(10))
        }
    }

    private func load() async {
        let r = await store.topConsumers(metric: metric, window: window)
        let range = await store.resourceTimeRange()
        ranks = r
        firstRecord = range?.first
        if selected == nil || !r.contains(where: { $0.app == selected }) {
            if let first = r.first?.app, first != selected { selected = first; return } // görev yeniden başlar
        }
        if let selected {
            series = await store.resourceSeries(app: selected, metric: metric, window: window)
        } else {
            series = []
        }
        loaded = true
    }
}

/// Tek uygulamanın zaman grafiği (alan + çizgi). Kova toplamları orana çevrilir (CPU/GPU %, enerji W, yazma B/sn).
struct ResourceSeriesChart: View {
    let points: [ResourceSeriesPoint]
    let metric: ResourceMetric
    let window: ResourceWindow

    var body: some View {
        let data = points.map {
            (date: Date(timeIntervalSince1970: TimeInterval($0.ts)),
             value: ResourceFormat.seriesValue(metric: metric, bucketValue: $0.value, bucketSeconds: window.bucketSeconds))
        }
        Chart {
            ForEach(data, id: \.date) { p in
                AreaMark(x: .value("Zaman", p.date), y: .value(metric.title, p.value))
                    .foregroundStyle(.linearGradient(colors: [.accentColor.opacity(0.35), .accentColor.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Zaman", p.date), y: .value(metric.title, p.value))
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: 0...max(1e-9, (data.map(\.value).max() ?? 1) * 1.15))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(ResourceFormat.axisLabel(metric: metric, value: v)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisValueLabel(format: window == .days7 ? .dateTime.weekday(.abbreviated).hour() : .dateTime.hour().minute())
            }
        }
        .accessibilityLabel("\(metric.title) zaman grafiği")
    }
}
