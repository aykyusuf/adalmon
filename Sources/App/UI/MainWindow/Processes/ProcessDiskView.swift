import AppKit
import SwiftUI

/// "Disk": boş alan eğilimi, en çok yazanlar (geçmişten) ve büyüyen klasörler (saatlik tarama).
struct ProcessDiskView: View {
    let model: AppModel
    @State private var window: ResourceWindow = .hours24
    @State private var free: [DiskFreePoint] = []
    @State private var writers: [ResourceRank] = []
    @State private var report = UsageStore.FolderGrowthReport()
    @State private var firstRecord: Int?
    @State private var loaded = false

    private var service: ResourceService { model.resources }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Picker("Pencere", selection: $window) {
                        ForEach(ResourceWindow.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 280)
                    Spacer()
                }
                freeCard
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) { writersCard.frame(minWidth: 380); foldersCard.frame(minWidth: 460) }
                    VStack(spacing: 14) { writersCard; foldersCard }
                }
            }
            .padding(.bottom, 8)
        }
        .task(id: window) { await refreshLoop() }
        .onChange(of: service.lastScanDate) { Task { await load() } }
    }

    private var freeCard: some View {
        ResourceCard(title: "Boş alan", systemImage: "internaldrive") {
            if free.count < 2 {
                ResourceEmptyNote(text: loaded && free.isEmpty ? ResourceEmptyText.collecting : "Eğilim için en az iki kayıt gerekir.")
            } else {
                let last = free.last?.freeBytes ?? 0
                let delta = Int64(clamping: last) - Int64(clamping: free.first?.freeBytes ?? 0)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Format.gigabytes(last)).font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                    Text("\(delta >= 0 ? "+" : "−")\(Format.gigabytes(UInt64(abs(delta)))) son \(window.title)")
                        .font(.callout)
                        .foregroundStyle(delta < 0 ? Color.orange : Color.secondary)
                        .monospacedDigit()
                }
                DiskFreeChart(points: free, window: window)
                    .frame(height: 150)
            }
        }
    }

    private var writersCard: some View {
        ResourceCard(title: "En çok yazanlar · son \(window.title)", systemImage: "square.and.pencil") {
            if writers.isEmpty {
                ResourceEmptyNote(text: loaded && firstRecord == nil ? ResourceEmptyText.collecting : "Bu pencerede kayıt yok.")
            } else {
                let peak = max(1, writers.first?.value ?? 1)
                let coverage = ResourceFormat.coverage(window: window, firstRecord: firstRecord)
                ForEach(writers.prefix(8)) { w in
                    ResourceRankRow(rank: w, fraction: w.value / peak, metric: .diskWrite, coverage: coverage, tint: .orange)
                }
                Text("Yazılan bayttır, net büyüme değildir: aynı dosyayı yeniden yazma ve silinen geçici dosyalar da dahil. Kopyalama (APFS klonu) neredeyse hiç yazma göstermez.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var foldersCard: some View {
        ResourceCard(title: "Büyüyen klasörler · son \(window.title)", systemImage: "folder.badge.plus") {
            HStack(spacing: 8) {
                Button {
                    Task { await service.scanNow() }
                } label: {
                    if service.isScanning {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Taranıyor…") }
                    } else {
                        Label("Tara", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(service.isScanning)
                Text(scanStatus).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
            }
            if report.latestTs == nil {
                ResourceEmptyNote(text: "Henüz klasör taraması yok — ilk tarama açılıştan ~2 dk sonra ya da \"Tara\" ile hemen.")
            } else if !report.hasComparison {
                ResourceEmptyNote(text: "İlk tarama kaydedildi; büyüme bir sonraki taramadan sonra görünür (saatte bir).")
            } else if report.items.isEmpty {
                ResourceEmptyNote(text: "İzlenen klasörlerde belirgin büyüme yok.")
            } else {
                ForEach(report.items) { item in FolderGrowthRow(item: item) }
                if let base = report.baseTs, let latest = report.latestTs {
                    Text("\(Date(timeIntervalSince1970: TimeInterval(base)).formatted(date: .omitted, time: .shortened)) → \(Date(timeIntervalSince1970: TimeInterval(latest)).formatted(date: .omitted, time: .shortened)) taramaları karşılaştırıldı. Yalnızca ≥ 10 MB klasörler izlenir; izin isteyen konumlar (Belgeler, İndirilenler, Containers, Mail…) taranmaz.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var scanStatus: String {
        if let note = service.lastScanNote { return note }
        guard let d = service.lastScanDate else { return "" }
        return "Son tarama: " + d.formatted(.relative(presentation: .named))
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(for: .seconds(60), tolerance: .seconds(10))
        }
    }

    private func load() async {
        let store = model.store
        free = await store.diskFreeSeries(window: window)
        writers = await store.topConsumers(metric: .diskWrite, window: window, limit: 8)
        report = await store.folderGrowth(window: window)
        firstRecord = await store.resourceTimeRange()?.first
        loaded = true
    }
}

private struct FolderGrowthRow: View {
    let item: FolderGrowth

    var body: some View {
        let shown = FolderWatchList.displayPath(item.path)
        HStack(spacing: 8) {
            Image(systemName: "folder.fill").foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text((shown as NSString).lastPathComponent).lineLimit(1)
                Text(shown).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text("+" + Format.bytes(UInt64(item.growthBytes))).foregroundStyle(.orange).monospacedDigit()
                Text(Format.bytes(item.currentBytes)).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            } label: {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.borderless)
            .help("Finder'da göster")
            .accessibilityLabel("Finder'da göster: \(shown)")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
