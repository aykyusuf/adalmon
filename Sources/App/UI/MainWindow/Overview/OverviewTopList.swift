import SwiftUI

/// "En çok kullananlar" listesinin sekmesi.
enum OverviewListTab: String, CaseIterable, Identifiable, Sendable {
    case network, cpu, memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .network: "Ağ"
        case .cpu: "CPU"
        case .memory: "Bellek"
        }
    }
}

/// Liste yüksekliği hesabı: sayfa kaydırılmadan sığsın diye satır sayısı kalan yüksekliğe göre seçilir.
enum OverviewLayout {
    /// Kart iç boşluğu + başlık + "Tümü" bağlantısı + filtre uyarısı satırı için ayrılan yükseklik.
    static let listChrome: CGFloat = 96
    /// Kompakt satır + aralık.
    static let rowPitch: CGFloat = 30
    static let maxRows = 15

    static func listRows(height: CGFloat) -> Int {
        let fit = Int(((height - listChrome + 6) / rowPitch).rounded(.down))
        return min(maxRows, max(1, fit))
    }
}

/// Başlık + [Ağ | CPU | Bellek] seçici (her iki liste türünün başlığında aynı yerde durur).
struct OverviewListHeader: View {
    @Binding var tab: OverviewListTab

    var body: some View {
        HStack(spacing: 10) {
            Label("En çok kullananlar", systemImage: "list.number")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
            Picker("Liste", selection: $tab) {
                ForEach(OverviewListTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
        }
    }
}

/// CPU / Bellek sekmesi: dakikalık kaynak kaydından en çok kullananlar (Süreçler ile aynı kaynak; ek örnekleme yok).
/// Yalnızca bu sekme görünürken dakikada bir okunur.
struct OverviewResourceList: View {
    let store: UsageStore
    let metric: ResourceMetric
    let maxRows: Int
    let header: AnyView
    let router: SettingsRouter

    @State private var minutes: Int
    @State private var ranks: [ResourceRank]
    @State private var loaded: Bool

    static let ranges: [(minutes: Int, title: String)] = [(5, "5 dk"), (15, "15 dk"), (60, "1 sa")]

    init(store: UsageStore, metric: ResourceMetric, maxRows: Int, header: AnyView, router: SettingsRouter,
         initialMinutes: Int = 5, initialRanks: [ResourceRank] = []) {
        self.store = store
        self.metric = metric
        self.maxRows = maxRows
        self.header = header
        self.router = router
        _minutes = State(initialValue: initialMinutes)
        _ranks = State(initialValue: initialRanks)
        _loaded = State(initialValue: !initialRanks.isEmpty)
    }

    private struct RefreshKey: Hashable { var metric: ResourceMetric; var minutes: Int }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    header
                    Spacer(minLength: 8)
                    controls
                }
                VStack(alignment: .leading, spacing: 8) {
                    header
                    HStack(spacing: 10) { controls }
                }
            }
            if ranks.isEmpty {
                Text(loaded ? ResourceEmptyText.collecting : "Yükleniyor…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            } else {
                let visible = Array(ranks.prefix(maxRows))
                let peak = max(visible.first?.value ?? 1, 1e-9)
                VStack(spacing: 6) {
                    ForEach(visible) { rank in
                        row(rank, fraction: rank.value / peak)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
        .task(id: RefreshKey(metric: metric, minutes: minutes)) { await refreshWhileVisible() }
    }

    @ViewBuilder private var controls: some View {
        Picker("son:", selection: $minutes) {
            ForEach(Self.ranges, id: \.minutes) { Text($0.title).tag($0.minutes) }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .controlSize(.small)
        .help("Dakikalık kayıttan; Adalmon açıkken ölçülür")
        Button("Süreçler") { OverviewDestination(section: .processes, processesTab: .processes).open(router) }
            .buttonStyle(.link)
            .font(.caption)
    }

    private func row(_ rank: ResourceRank, fraction: Double) -> some View {
        let text = ResourceFormat.rankText(metric: metric, value: rank.value, coverage: Double(minutes * 60))
        let isCPU = metric == .cpu || metric == .gpu
        let value = isCPU ? (text.secondary ?? "").replacingOccurrences(of: "ort. ", with: "") : text.primary
        let caption = isCPU ? "ort." : (text.secondary ?? "")
        let tint: Color = isCPU ? .blue : .teal
        return Button { OverviewDestination(section: .processes, processesTab: .processes).open(router) } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    ResourceAppLabel(key: rank.app, size: 18)
                        .lineLimit(1)
                    UsageBar(fraction: fraction, tint: tint.opacity(0.7), height: 3)
                        .padding(.leading, 24)
                }
                .layoutPriority(1)
                Spacer(minLength: 6)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .frame(minWidth: 64, alignment: .trailing)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(isCPU ? "\(text.primary) işlemci süresi · \(text.secondary ?? "")" : "\(text.primary) \(text.secondary ?? "")")
    }

    private func refreshWhileVisible() async {
        while !Task.isCancelled {
            let next = await store.recentTop(metric: metric, minutes: minutes, limit: OverviewLayout.maxRows)
            if next != ranks { ranks = next }
            loaded = true
            try? await Task.sleep(for: .seconds(60), tolerance: .seconds(10))
        }
    }
}
