import SwiftUI

/// "Performans": solda kaynak kutucukları (CPU, Bellek, Disk, Ağ, GPU), sağda büyük grafik + istatistikler.
struct PerformanceView: View {
    let model: AppModel
    let live: ProcessLiveModel
    @State private var metric: PerformanceMetric = .cpu

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(PerformanceMetric.allCases) { m in
                        PerformanceTile(metric: m,
                                        values: PerformanceSeriesBuilder.normalized(live.history.values(m), metric: m),
                                        headline: headline(m), detail: detail(m), isSelected: m == metric) { metric = m }
                    }
                }
                .padding(12)
            }
            .frame(width: 244)
            Divider()
            PerformanceDetailView(metric: metric, model: model, live: live)
        }
    }

    private func headline(_ m: PerformanceMetric) -> String {
        guard let s = live.latest else { return "…" }
        switch m {
        case .cpu: return Format.percent(s.cpu.total)
        case .memory: return "\(Format.gigabytes(s.memory.usedBytes)) / \(Format.gigabytes(s.memory.totalBytes))"
        case .disk: return "Okuma \(Format.rate(s.disk.readBytesPerSecond))"
        case .network: return "↓ \(Format.rate(s.network.downloadBytesPerSecond))"
        case .gpu: return Format.percent(s.gpu?.displayLoad ?? 0)
        }
    }

    private func detail(_ m: PerformanceMetric) -> String {
        guard let s = live.latest else { return "" }
        switch m {
        case .cpu: return "\(s.cpu.performanceCores)P + \(s.cpu.efficiencyCores)E"
        case .memory: return Format.percent(s.memory.usedFraction)
        case .disk: return "Yazma \(Format.rate(s.disk.writeBytesPerSecond))"
        case .network: return "↑ \(Format.rate(s.network.uploadBytesPerSecond))"
        case .gpu: return s.gpu?.frequencyMHz.map { Format.gigahertz($0) } ?? "—"
        }
    }
}
