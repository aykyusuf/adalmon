import SwiftUI

/// Performans sekmesinin sağ tarafı: başlık, aralık seçici, büyük etkileşimli grafik + ort/min/maks özeti, istatistik ızgarası.
/// Canlı aralık sistem geçmişi tamponundan (son 10 dk) anında çizilir; 1 sa / 24 sa kayıtlı toplamlardan.
struct PerformanceDetailView: View {
    /// Canlı aralığın gösterdiği süre (sn); tampon kapasitesiyle aynı sırada.
    static let liveSpan: TimeInterval = 600

    let metric: PerformanceMetric
    let model: AppModel
    let live: ProcessLiveModel
    @State private var range: PerformanceRange = .live
    @State private var totals: [ResourceWindow: [ResourceTotalPoint]] = [:]
    @State private var networkHours: [ResourceWindow: [UsageStore.HourPoint]] = [:]
    /// İmleç grafikteyken veri donar (değer imlecin altından kaymasın).
    @State private var frozen: FrozenChart?

    private struct FrozenChart {
        var series: [PerformanceChartSeries]
        var anchor: Date
    }

    private struct LoadKey: Hashable { var range: PerformanceRange; var isNetwork: Bool }

    private var availableRanges: [PerformanceRange] {
        metric == .network ? [.live, .hours24] : PerformanceRange.allCases
    }

    var body: some View {
        // Geçmiş tamponu yalnızca ana pencere görünürken değişir; tek gözlem noktası.
        let _ = model.systemHistory.revision
        let series = frozen?.series ?? chartSeries
        let anchor = frozen?.anchor ?? currentAnchor
        let snapshot = live.latest ?? model.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(metric.title).font(.title.weight(.semibold))
                    Text(subtitle(snapshot)).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 12)
                    Picker("Aralık", selection: $range) {
                        ForEach(availableRanges) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                chart(series, anchor: anchor)
                    .frame(minHeight: 220, idealHeight: 300, maxHeight: 360)
                    .padding(12)
                    .background(metric.color.opacity(0.06), in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(metric.color.opacity(0.35), lineWidth: 1))
                if let unit = series.first?.unit, series.contains(where: { !$0.points.isEmpty }) {
                    ChartSummaryStrip(lines: series.map(\.line)) { PerformanceSeriesBuilder.valueText($0, unit: unit) }
                }
                caption
                if let snapshot {
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
        .onChange(of: metric) {
            frozen = nil
            if !availableRanges.contains(range) { range = .live }
        }
        .onChange(of: range) { frozen = nil }
        .task(id: LoadKey(range: range, isNetwork: metric == .network)) { await loadStored() }
    }

    private var span: TimeInterval {
        range.window.map { TimeInterval($0.seconds) } ?? Self.liveSpan
    }

    private var currentAnchor: Date {
        range == .live ? (model.systemHistory.latestTime ?? .now) : .now
    }

    @ViewBuilder
    private func chart(_ series: [PerformanceChartSeries], anchor: Date) -> some View {
        if series.isEmpty || series.allSatisfy({ $0.points.isEmpty }) {
            ResourceEmptyNote(text: emptyText)
        } else {
            PerformanceChartView(series: series, range: range, anchor: anchor, span: span, onHoverChange: hoverChanged)
        }
    }

    private var emptyText: String {
        guard let window = range.window else { return "Ölçülüyor…" }
        let loaded = metric == .network ? networkHours[window] != nil : totals[window] != nil
        return loaded ? ResourceEmptyText.collecting : "Yükleniyor…"
    }

    private var chartSeries: [PerformanceChartSeries] {
        guard let window = range.window else {
            return PerformanceSeriesBuilder.live(metric: metric, samples: model.systemHistory.samples(window: Self.liveSpan))
        }
        if metric == .network { return PerformanceSeriesBuilder.storedNetwork(networkHours[window] ?? []) }
        return PerformanceSeriesBuilder.stored(metric: metric, totals: totals[window] ?? [], window: window,
                                               cores: ProcessInfo.processInfo.activeProcessorCount,
                                               memoryTotal: Double((live.latest ?? model.snapshot)?.memory.totalBytes ?? 0))
    }

    private func hoverChanged(_ hovering: Bool) {
        frozen = hovering ? FrozenChart(series: chartSeries, anchor: currentAnchor) : nil
    }

    private var caption: some View {
        HStack(spacing: 16) {
            if range != .live, metric == .memory {
                Text("Kayıtlı bellek: uygulamaların ayak izi toplamı").font(.caption).foregroundStyle(.secondary)
            }
            if range != .live, metric == .network {
                Text("Saatlik toplam (fiziksel arayüz)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(range == .live ? "Son \(Int(Self.liveSpan / 60)) dk · \(model.prefs.updateInterval) sn aralık" : "Son \(range.title)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func subtitle(_ snapshot: SystemSnapshot?) -> String {
        switch metric {
        case .cpu: PerformanceDetailView.cpuName
        case .memory: snapshot.map { Format.gigabytes($0.memory.totalBytes) } ?? ""
        case .disk: "Data birimi"
        case .network: snapshot?.network.primaryInterface ?? ""
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
                networkHours[window] = await model.store.hourlySeries(app: UsageStore.interfaceAppKey, from: now / 3_600 * 3_600 - window.seconds, to: now + 3_600)
            } else {
                totals[window] = await model.store.resourceTotalSeries(window: window)
            }
            try? await Task.sleep(for: .seconds(60), tolerance: .seconds(10))
        }
    }
}
