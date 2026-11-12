import AppKit
import SwiftUI

/// Temizlik sekmesi: yalnızca istek üzerine tarar, önizleme + onay sonrası seçilenleri Çöp Sepeti'ne taşır.
/// Kalıcı silme işlem başına seçilir (iki onay) ve her işlemden sonra Çöp'e döner; saklanmaz.
@MainActor @Observable
final class CleanupViewModel {
    enum Phase: Equatable { case idle, scanning(CleanupCategory?), deleting }

    let home: String
    var items: [CleanupItem] = []
    var rootStates: [String: CleanupRootState] = [:]
    var selection: Set<String> = []
    var phase: Phase = .idle
    var lastResult: [CleanupResult]?
    var lastMode: DeleteMode = .trash
    /// Yalnızca sonraki işlem için; işlem bitince `.trash`a döner.
    var deleteMode: DeleteMode = .trash
    let access: CleanupAccessMonitor
    var scannedCategories: Set<CleanupCategory> = []
    var trashState: (state: CleanupRootState, bytes: UInt64)?
    var log: [CleanupLogEntry] = []
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init(home: String = NSHomeDirectory(), probe: PathProbe = .live) {
        self.home = home
        access = CleanupAccessMonitor(home: home, probe: probe)
        access.onUnblocked = { [weak self] paths in self?.rescanUnblocked(paths) }
    }

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

    /// Erişimi açılan kökleri yeniden tarar (Çöp Sepeti için yeniden ölçüm).
    func rescanUnblocked(_ paths: [String]) {
        let freed = Set(paths)
        let categories = CleanupCatalog.roots(home: home).filter { freed.contains($0.path) }.map(\.category)
        var seen = Set<CleanupCategory>()
        let ordered = categories.filter { seen.insert($0).inserted }
        let trashFreed = freed.contains(CleanupCatalog.trashPath(home: home))
        if trashFreed { trashState = nil }
        if !ordered.isEmpty { scan(ordered) } else if trashFreed { measureTrash() }
    }

    /// Kategorinin erişilemeyen ilk kökünün nedeni.
    func accessReason(for category: CleanupCategory) -> AccessReason? {
        CleanupCatalog.roots(home: home).filter { $0.category == category }.lazy.compactMap { self.access.reason(for: $0.path) }.first
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
                if !cancelled {
                    trashState = result
                    access.setBlocked(CleanupCatalog.trashPath(home: home), result.state == .noAccess)
                }
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
        access.update(states: out.states)
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

    /// Onaydan sonra: her öğe silme anında yeniden doğrulanır (çalışan uygulamalar o an okunur).
    /// Yöntem onay anında alınır; işlem bitince `deleteMode` Çöp'e döner.
    /// `items`: onay penceresinde gösterilen öğeler (onay açıkken yeniden tarama seçimi değiştirse bile yalnızca bunlar silinir).
    func deleteSelected(mode: DeleteMode, items chosen: [CleanupItem]) {
        guard !chosen.isEmpty, !isBusy else {
            deleteMode = .trash
            return
        }
        let roots = CleanupCatalog.roots(home: home)
        let candidates = chosen.map { DeletionCandidate(item: $0, roots: roots) }
        let deleter = CleanupDeleter(home: home)
        phase = .deleting
        Task.detached(priority: .utility) { [weak self] in
            let results = deleter.delete(candidates, mode: mode)
            await MainActor.run { [weak self] in
                guard let self else { return }
                let removed = Set(results.filter(\.isRemoved).map(\.candidate.id))
                items.removeAll { removed.contains($0.id) }
                selection.subtract(removed)
                lastResult = results
                lastMode = mode
                deleteMode = .trash
                phase = .idle
                reloadLog()
            }
        }
    }

    func reloadLog() { log = CleanupAuditLog.read() }
}

struct CleanupView: View {
    @State private var vm = CleanupViewModel()
    @State private var confirmSummary: DeleteSummary?
    /// Onay penceresinde özetlenen öğelerin kendisi.
    @State private var confirmItems: [CleanupItem] = []
    @State private var helpReason: AccessReason?
    @State private var showDetails = false
    @State private var logExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    topRow
                    Text(vm.deleteMode == .trash
                         ? "Seçilenler Çöp Sepeti'ne taşınır, kalıcı silinmez. Yer, Çöp Sepeti boşaltılınca açılır."
                         : "Kalıcı silme seçili: seçilenler Çöp Sepeti'ne gitmez, geri alınamaz. İşlemden sonra Çöp'e taşımaya döner.")
                        .font(.caption).foregroundStyle(vm.deleteMode == .trash ? Color.secondary : Color.red)
                    if !vm.access.blocked.isEmpty { accessBanner }
                    if let result = vm.lastResult { banner(result) }
                    if vm.scannedCategories.isDisjoint(with: CleanupCategory.defaultScan) {
                        ResourceEmptyNote(text: "Önbellekleri ve geliştirici artıklarını görmek için Tara'ya basın. Tarama yalnızca siz isteyince yapılır.")
                    }
                    ForEach(CleanupCategory.defaultScan) { category in
                        if vm.scannedCategories.contains(category), let state = vm.state(of: category), state != .missing,
                           state == .noAccess || !vm.items(in: category).isEmpty {
                            CleanupCategoryCard(vm: vm, category: category, state: state, onHelp: { helpReason = $0 })
                        }
                    }
                    CleanupCategoryCard(vm: vm, category: .downloads, state: vm.state(of: .downloads), onHelp: { helpReason = $0 })
                    CleanupCategoryCard(vm: vm, category: .iosBackups, state: vm.state(of: .iosBackups), onHelp: { helpReason = $0 })
                    logCard
                }
                .padding(.bottom, 8)
            }
            Divider()
            bottomBar.padding(.vertical, 10)
        }
        .onAppear {
            vm.access.refreshFullDiskAccess()
            vm.access.resume()
        }
        .onDisappear {
            vm.cancel()
            vm.access.stop()
            vm.deleteMode = .trash
        }
        .sheet(isPresented: Binding(get: { confirmSummary != nil }, set: { if !$0 { confirmSummary = nil } })) {
            if let summary = confirmSummary {
                DeleteConfirmation(summary: summary, onConfirm: { mode in
                    let chosen = confirmItems
                    confirmSummary = nil
                    confirmItems = []
                    vm.deleteSelected(mode: mode, items: chosen)
                }, onCancel: {
                    confirmSummary = nil
                    confirmItems = []
                    vm.deleteMode = .trash
                })
            }
        }
        .sheet(item: $helpReason) { reason in
            AccessHelpSheet(reason: reason, monitor: vm.access) { helpReason = nil }
        }
    }

    /// Erişilemeyen kökler: neden başına bir satır, ilgili ayar düğmesi ve yardım.
    private var accessBanner: some View {
        let reasons = Array(Set(vm.access.blocked.values)).sorted { $0.title < $1.title }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(reasons) { reason in
                let paths = vm.access.blocked.filter { $0.value == reason }.keys.sorted()
                    .map { FolderWatchList.displayPath($0, home: vm.home) }
                HStack(spacing: 8) {
                    Image(systemName: "lock").foregroundStyle(.orange).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(reason.title)
                        Text(paths.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    if let button = reason.buttonTitle {
                        Button(button) { vm.access.openSettings(for: reason) }
                    }
                    Button("Nasıl?") { helpReason = reason }.buttonStyle(.borderless)
                }
            }
            if vm.access.suggestRestart {
                HStack(spacing: 8) {
                    Text("Ayarlardan döndünüz ama erişim hâlâ yok. macOS bazen izni yeniden açılışta uygular.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Adalmon'u yeniden başlat") { CleanupAccessMonitor.relaunch() }
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.10), in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var fullDiskAccessBadge: some View {
        if let granted = vm.access.fullDiskAccess {
            Button {
                if !granted { helpReason = .fullDiskAccess }
            } label: {
                Label("Tam Disk Erişimi: \(granted ? "açık" : "kapalı")", systemImage: granted ? "checkmark.shield" : "shield.slash")
                    .font(.caption)
                    .foregroundStyle(granted ? Color.secondary : Color.orange)
            }
            .buttonStyle(.borderless)
            .disabled(granted)
            .help(granted ? "Adalmon Tam Disk Erişimi'ne sahip" : "Tam Disk Erişimi nasıl açılır?")
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
            fullDiskAccessBadge
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
            Button("Çöp Sepeti: erişim yok") { helpReason = CleanupAccess.reason(for: CleanupCatalog.trashPath(home: vm.home), home: vm.home) }
                .buttonStyle(.borderless).help("Tam Disk Erişimi gerekiyor")
        default:
            Button("Çöp Sepeti: Hesapla") { vm.measureTrash() }
                .controlSize(.small).disabled(vm.isBusy)
        }
    }

    private func banner(_ results: [CleanupResult]) -> some View {
        let moved = results.filter(\.isRemoved)
        let skipped = results.filter { !$0.isRemoved }
        let bytes = moved.reduce(UInt64(0)) { $0 + $1.candidate.bytes }
        let verb = vm.lastMode == .trash ? "taşındı" : "kalıcı olarak silindi"
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("\(moved.count) öğe \(verb) (\(Format.bytes(bytes))). \(skipped.count) atlandı.", systemImage: "checkmark.circle")
                Spacer()
                if !skipped.isEmpty {
                    Button(showDetails ? "Gizle" : "Ayrıntılar") { showDetails.toggle() }.buttonStyle(.borderless)
                }
            }
            if showDetails {
                ForEach(skipped, id: \.candidate.id) { r in
                    HStack {
                        Text(FolderWatchList.displayPath(r.candidate.path, home: vm.home)).lineLimit(1).truncationMode(.middle)
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
                            Image(systemName: entry.result == "moved" ? "arrow.right.circle" : entry.result == "deleted" ? "xmark.circle" : "minus.circle")
                                .foregroundStyle(.secondary).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(FolderWatchList.displayPath(entry.path, home: vm.home)).lineLimit(1).truncationMode(.middle)
                                Text([entry.date?.formatted(date: .abbreviated, time: .shortened), entry.result == "deleted" ? "kalıcı silindi" : nil, entry.reason]
                                    .compactMap { $0 }.joined(separator: " · "))
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
            if vm.phase == .deleting { ProgressView().controlSize(.small) }
            Picker("Silme yöntemi", selection: $vm.deleteMode) {
                Text("Çöp'e taşı").tag(DeleteMode.trash)
                Text("Kalıcı sil").tag(DeleteMode.permanent)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(vm.isBusy)
            .help("Kalıcı silme yalnızca bu işlem içindir; sonra Çöp'e taşımaya döner.")
            Button(vm.deleteMode == .trash ? "Çöp Sepeti'ne taşı…" : "Kalıcı olarak sil…",
                   systemImage: vm.deleteMode == .trash ? "trash" : "xmark.bin") {
                confirmItems = selected
                confirmSummary = summary(for: selected)
            }
            .tint(vm.deleteMode == .trash ? nil : .red)
            .disabled(selected.isEmpty || vm.isBusy)
        }
    }

    private func summary(for selected: [CleanupItem]) -> DeleteSummary {
        DeleteSummary(
            count: selected.count, bytes: selected.reduce(UInt64(0)) { $0 + $1.bytes }, mode: vm.deleteMode,
            sample: selected.prefix(5).map { FolderWatchList.displayPath($0.path, home: vm.home) }
        )
    }
}
