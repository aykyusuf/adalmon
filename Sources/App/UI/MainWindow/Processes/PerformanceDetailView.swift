import SwiftUI

/// Performans sekmesinin sağ tarafı: başlık, aralık seçici, büyük grafik, istatistik ızgarası.
struct PerformanceDetailView: View {
    let metric: PerformanceMetric
    let model: AppModel
    let live: ProcessLiveModel
    @State private var range: PerformanceRange = .live
    @State private var totals: [ResourceTotalPoint] = []
    @State private var networkHours: [UsageStore.HourPoint] = []

    private struct LoadKey: Hashable { var metric: PerformanceMetric; var range: PerformanceRange }

    private var availableRanges: [PerformanceRange] {
        metric == .network ? [.live, .hours24] : PerformanceRange.allCases
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(metric.title).font(.title.weight(.semibold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 12)
                    Picker("Aralık", selection: $range) {
                        ForEach(availableRanges) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                chart
                    .frame(minHeight: 220, idealHeight: 300, maxHeight: 360)
                    .padding(12)
                    .background(metric.color.opacity(0.06), in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(metric.color.opacity(0.35), lineWidth: 1))
                legend
                if let snapshot = live.latest {
                    PerformanceStatsGrid(stats: PerformanceStatsBuilder.stats(
                        metric: metric, snapshot: snapshot, processCount: live.totalProcessCount,
                        facts: .init(downToday: model.downToday, upToday: model.upToday,
                                     downLast60: model.downLast60, upLast60: model.upLast60)))
                } else {
                    ResourceEmptyNote(text: "Ölçülüyor…")
                }
            }
            .padding(20)
        }
        .onChange(of: metric) { if !availableRanges.contains(range) { range = .live } }
        .task(id: LoadKey(metric: metric, range: range)) { await loadStored() }
    }

    private var span: TimeInterval {
        range.window.map { TimeInterval($0.seconds) } ?? Double(PerformanceHistory.capacity - 1) * Double(live.interval)
    }

    private var anchor: Date { range == .live ? (live.latest?.timestamp ?? .now) : .now }

    @ViewBuilder
    private var chart: some View {
        let series = chartSeries
        if series.isEmpty || series.allSatisfy({ $0.points.isEmpty }) {
            ResourceEmptyNote(text: range == .live ? "Ölçülüyor…" : ResourceEmptyText.collecting)
        } else {
            PerformanceChartView(series: series, range: range, anchor: anchor, span: span)
        }
    }

    private var chartSeries: [PerformanceChartSeries] {
        guard let window = range.window else {
            return PerformanceSeriesBuilder.live(metric: metric, history: live.history, interval: live.interval, anchor: anchor)
        }
        if metric == .network { return PerformanceSeriesBuilder.storedNetwork(networkHours) }
        return PerformanceSeriesBuilder.stored(metric: metric, totals: totals, window: window,
                                               cores: ProcessInfo.processInfo.activeProcessorCount,
                                               memoryTotal: Double(live.latest?.memory.totalBytes ?? 0))
    }

    private var legend: some View {
        HStack(spacing: 16) {
            ForEach(PerformanceSeriesBuilder.live(metric: metric, history: PerformanceHistory(), interval: 1, anchor: .now)) { s in
                Label { Text(s.name) } icon: { Circle().fill(s.color).frame(width: 8, height: 8) }
                    .font(.caption).foregroundStyle(.secondary)
            }
            if range != .live, metric == .memory {
                Text("Kayıtlı bellek: uygulamaların ayak izi toplamı").font(.caption).foregroundStyle(.secondary)
            }
            if range != .live, metric == .network {
                Text("Saatlik toplam (fiziksel arayüz)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(range == .live ? "Son \(Int(span)) sn · \(live.interval) sn aralık" : "Son \(range.title)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        switch metric {
        case .cpu: PerformanceDetailView.cpuName
        case .memory: live.latest.map { Format.gigabytes($0.memory.totalBytes) } ?? ""
        case .disk: "Data birimi"
        case .network: live.latest?.network.primaryInterface ?? ""
        case .gpu: "Apple GPU"
        }
    }

    static let cpuName: String = {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "İşlemci" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "İşlemci" }
        return String(cString: buffer)
    }()

    private func loadStored() async {
        guard let window = range.window else { return }
        while !Task.isCancelled {
            if metric == .network {
                let now = Int(Date.now.timeIntervalSince1970)
                networkHours = await model.store.hourlySeries(app: UsageStore.interfaceAppKey, from: now / 3_600 * 3_600 - window.seconds, to: now + 3_600)
            } else {
                totals = await model.store.resourceTotalSeries(window: window)
            }
            try? await Task.sleep(for: .seconds(60), tolerance: .seconds(10))
        }
    }
}

/// Windows Görev Yöneticisi'ndeki gibi başlık + büyük değer ızgarası.
struct PerformanceStatsGrid: View {
    let stats: [PerformanceStat]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16, alignment: .topLeading)], alignment: .leading, spacing: 14) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.title).font(.caption).foregroundStyle(.secondary)
                    Text(stat.value).font(.title3.weight(.medium)).monospacedDigit().lineLimit(2).minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
