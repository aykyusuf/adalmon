import AppKit
import SwiftUI

/// Temizlik sekmesi: yalnızca istek üzerine tarar, önizleme + onay sonrası seçilenleri Çöp Sepeti'ne taşır (kalıcı silme yok).
@MainActor @Observable
final class CleanupViewModel {
    enum Phase: Equatable { case idle, scanning(CleanupCategory?), trashing }

    let home: String
    var items: [CleanupItem] = []
    var rootStates: [String: CleanupRootState] = [:]
    var selection: Set<String> = []
    var phase: Phase = .idle
    var lastResult: [CleanupResult]?
    var scannedCategories: Set<CleanupCategory> = []
    var trashState: (state: CleanupRootState, bytes: UInt64)?
    var log: [CleanupLogEntry] = []
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init(home: String = NSHomeDirectory()) { self.home = home }

    var isBusy: Bool { phase != .idle }

    var selectedItems: [CleanupItem] { items.filter { selection.contains($0.id) && $0.blockedReason == nil } }

    func items(in category: CleanupCategory) -> [CleanupItem] { items.filter { $0.category == category } }

    /// Kategorinin köklerinden türetilen durum (biri tarandıysa taranmış sayılır).
    func state(of category: CleanupCategory) -> CleanupRootState? {
        let states = CleanupCatalog.roots(home: home).filter { $0.category == category }.compactMap { rootStates[$0.path] }
        if states.isEmpty { return nil }
        if states.contains(.scanned) { return .scanned }
        if states.contains(.noAccess) { return .noAccess }
        return .missing
    }

    static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func scan(_ categories: [CleanupCategory]) {
        guard !isBusy else { return }
        let running = Self.runningBundleIDs()
        let home = home
        phase = .scanning(categories.first)
        lastResult = nil
        scanTask = Task.detached(priority: .utility) { [weak self] in
            let out = CleanupScanner.scan(categories: categories, home: home, runningBundleIDs: running,
                                          isCancelled: { Task.isCancelled },
                                          progress: { c in Task { @MainActor [weak self] in
                                              if case .scanning = self?.phase { self?.phase = .scanning(c) }
                                          } })
            await self?.apply(out, categories: categories)
        }
    }

    func measureTrash() {
        guard !isBusy else { return }
        let home = home
        phase = .scanning(.trash)
        scanTask = Task.detached(priority: .utility) { [weak self] in
            let result = CleanupScanner.trashSize(home: home, isCancelled: { Task.isCancelled })
            let cancelled = Task.isCancelled
            await MainActor.run { [weak self] in
                guard let self else { return }
                if !cancelled { trashState = result }
                phase = .idle
            }
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        if case .scanning = phase { phase = .idle }
    }

    private func apply(_ out: CleanupScanner.Output, categories: [CleanupCategory]) {
        let cats = Set(categories)
        let oldIDs = Set(items.filter { cats.contains($0.category) }.map(\.id))
        items.removeAll { cats.contains($0.category) }
        items += out.items
        rootStates.merge(out.states) { _, new in new }
        selection.subtract(oldIDs)
        selection.formUnion(out.items.filter { $0.category.defaultSelected && $0.blockedReason == nil }.map(\.id))
        scannedCategories.formUnion(cats)
        phase = .idle
        scanTask = nil
    }

    func toggle(_ item: CleanupItem) {
        guard item.blockedReason == nil else { return }
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func setCategory(_ category: CleanupCategory, selected: Bool) {
        let ids = items(in: category).filter { $0.blockedReason == nil }.map(\.id)
        if selected { selection.formUnion(ids) } else { selection.subtract(ids) }
    }

    /// Onaydan sonra: çalışan uygulamalar yeniden okunur, her öğe taşıma anında yeniden doğrulanır.
    func trashSelected() {
        let chosen = selectedItems
        guard !chosen.isEmpty, !isBusy else { return }
        let trasher = CleanupTrasher(roots: CleanupCatalog.roots(home: home), home: home, runningBundleIDs: Self.runningBundleIDs())
        phase = .trashing
        Task.detached(priority: .utility) { [weak self] in
            let results = trasher.trash(chosen)
            await MainActor.run { [weak self] in
                guard let self else { return }
                let moved = Set(results.filter(\.isMoved).map(\.item.id))
                items.removeAll { moved.contains($0.id) }
                selection.subtract(moved)
                lastResult = results
                phase = .idle
                reloadLog()
            }
        }
    }

    func reloadLog() { log = CleanupTrasher.readLog() }
}

struct CleanupView: View {
    @State private var vm = CleanupViewModel()
    @State private var confirming = false
    @State private var showDetails = false
    @State private var logExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    topRow
                    Text("Seçilenler Çöp Sepeti'ne taşınır, kalıcı silinmez. Yer, Çöp Sepeti boşaltılınca açılır.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let result = vm.lastResult { banner(result) }
                    if vm.scannedCategories.isDisjoint(with: CleanupCategory.defaultScan) {
                        ResourceEmptyNote(text: "Önbellekleri ve geliştirici artıklarını görmek için Tara'ya basın. Tarama yalnızca siz isteyince yapılır.")
                    }
                    ForEach(CleanupCategory.defaultScan) { category in
                        if vm.scannedCategories.contains(category), let state = vm.state(of: category), state != .missing,
                           state == .noAccess || !vm.items(in: category).isEmpty {
                            CleanupCategoryCard(vm: vm, category: category, state: state)
                        }
                    }
                    CleanupCategoryCard(vm: vm, category: .downloads, state: vm.state(of: .downloads))
                    CleanupCategoryCard(vm: vm, category: .iosBackups, state: vm.state(of: .iosBackups))
                    logCard
                }
                .padding(.bottom, 8)
            }
            Divider()
            bottomBar.padding(.vertical, 10)
        }
        .onDisappear { vm.cancel() }
        .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
            Button("Taşı", role: .destructive) { vm.trashSelected() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
    }

    private var topRow: some View {
        HStack(spacing: 10) {
            if case .scanning(let category) = vm.phase {
                ProgressView().controlSize(.small)
                Text("Taranıyor: \(category?.title ?? "")…").foregroundStyle(.secondary).lineLimit(1)
                Button("Durdur") { vm.cancel() }
            } else {
                Button("Tara", systemImage: "magnifyingglass") { vm.scan(CleanupCategory.defaultScan) }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isBusy)
            }
            Spacer(minLength: 8)
            trashSummary
            Button("Çöpü Finder'da aç", systemImage: "trash") {
                NSWorkspace.shared.open(URL(fileURLWithPath: CleanupCatalog.trashPath(home: vm.home)))
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var trashSummary: some View {
        switch vm.trashState?.state {
        case .scanned?:
            Text("Çöp Sepeti: \(Format.bytes(vm.trashState?.bytes ?? 0))").foregroundStyle(.secondary).monospacedDigit()
        case .noAccess?:
            Button("Çöp Sepeti: erişim yok") { CleanupCategoryCard.openFullDiskAccess() }
                .buttonStyle(.borderless).help("Tam Disk Erişimi gerekebilir")
        default:
            Button("Çöp Sepeti: Hesapla") { vm.measureTrash() }
                .controlSize(.small).disabled(vm.isBusy)
        }
    }

    private func banner(_ results: [CleanupResult]) -> some View {
        let moved = results.filter(\.isMoved)
        let skipped = results.filter { !$0.isMoved }
        let bytes = moved.reduce(UInt64(0)) { $0 + $1.item.bytes }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("\(moved.count) öğe taşındı (\(Format.bytes(bytes))). \(skipped.count) atlandı.", systemImage: "checkmark.circle")
                Spacer()
                if !skipped.isEmpty {
                    Button(showDetails ? "Gizle" : "Ayrıntılar") { showDetails.toggle() }.buttonStyle(.borderless)
                }
            }
            if showDetails {
                ForEach(skipped, id: \.item.id) { r in
                    HStack {
                        Text(FolderWatchList.displayPath(r.item.path, home: vm.home)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(r.reasonText ?? "").foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.10), in: .rect(cornerRadius: 12))
    }

    private var logCard: some View {
        ResourceCard(title: "Son işlemler", systemImage: "clock") {
            DisclosureGroup(isExpanded: $logExpanded) {
                if vm.log.isEmpty {
                    ResourceEmptyNote(text: "Henüz işlem yok.")
                } else {
                    ForEach(vm.log) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.result == "moved" ? "arrow.right.circle" : "minus.circle")
                                .foregroundStyle(.secondary).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(FolderWatchList.displayPath(entry.path, home: vm.home)).lineLimit(1).truncationMode(.middle)
                                Text([entry.date?.formatted(date: .abbreviated, time: .shortened), entry.reason].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(Format.bytes(entry.bytes)).monospacedDigit().foregroundStyle(.secondary)
                            if let to = entry.trashedTo {
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: to)])
                                } label: { Image(systemName: "magnifyingglass.circle") }
                                    .buttonStyle(.borderless)
                                    .help("Çöp Sepeti'nde göster")
                            }
                        }
                        .font(.callout)
                    }
                }
            } label: {
                Text("Son 20 işlem").foregroundStyle(.secondary)
            }
            .onChange(of: logExpanded) { if logExpanded { vm.reloadLog() } }
        }
    }

    private var bottomBar: some View {
        let selected = vm.selectedItems
        let bytes = selected.reduce(UInt64(0)) { $0 + $1.bytes }
        return HStack {
            Text("Seçili: \(selected.count) öğe · \(Format.bytes(bytes))").monospacedDigit().foregroundStyle(.secondary)
            Spacer()
            if vm.phase == .trashing { ProgressView().controlSize(.small) }
            Button("Çöp Sepeti'ne taşı…", systemImage: "trash") { confirming = true }
                .disabled(selected.isEmpty || vm.isBusy)
        }
    }

    private var confirmTitle: String {
        let selected = vm.selectedItems
        return "\(selected.count) öğe (\(Format.bytes(selected.reduce(UInt64(0)) { $0 + $1.bytes }))) Çöp Sepeti'ne taşınsın mı?"
    }

    private var confirmMessage: String {
        let selected = vm.selectedItems
        var lines = selected.prefix(5).map { FolderWatchList.displayPath($0.path, home: vm.home) }
        if selected.count > 5 { lines.append("…ve \(selected.count - 5) daha") }
        lines.append("")
        lines.append("Kalıcı silinmez; Çöp Sepeti'nden geri alabilirsiniz.")
        return lines.joined(separator: "\n")
    }
}
