import SwiftUI

/// Genel bakış: son dakikalarda en çok CPU / bellek kullanan uygulamalar (dakikalık kayıttan; ek örnekleme yok).
/// Tam genişlikte kendi satırında; diğer kartların ızgarasını etkilemez.
struct OverviewResourceCard: View {
    let store: UsageStore
    let router: SettingsRouter
    @State private var cpu: [ResourceRank] = []
    @State private var memory: [ResourceRank] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("En çok kaynak kullanan", systemImage: "cpu").font(.headline).foregroundStyle(.secondary)
                Text("son 5 dk").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Süreçler") { router.selectedMainSection = .processes }
                    .buttonStyle(.link)
                    .font(.callout)
            }
            if cpu.isEmpty && memory.isEmpty {
                Text(loaded ? ResourceEmptyText.collecting : "Yükleniyor…")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                HStack(alignment: .top, spacing: 24) {
                    column("CPU", ranks: cpu, metric: .cpu)
                    column("Bellek", ranks: memory, metric: .memoryPeak)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
        .task { await refreshLoop() }
    }

    private func column(_ title: String, ranks: [ResourceRank], metric: ResourceMetric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            ForEach(ranks) { r in
                let text = ResourceFormat.rankText(metric: metric, value: r.value, coverage: 300)
                Button { router.selectedMainSection = .processes } label: {
                    HStack(spacing: 8) {
                        ResourceAppLabel(key: r.app, size: 20)
                        Spacer(minLength: 6)
                        Text(metric == .cpu ? (text.secondary ?? "").replacingOccurrences(of: "ort. ", with: "") : text.primary)
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            cpu = await store.recentTop(metric: .cpu, minutes: 5, limit: 3)
            memory = await store.recentTop(metric: .memoryPeak, minutes: 5, limit: 3)
            loaded = true
            try? await Task.sleep(for: .seconds(60), tolerance: .seconds(10))
        }
    }
}
