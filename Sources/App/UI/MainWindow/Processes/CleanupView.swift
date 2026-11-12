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
    /// Kullanıcının seçtiği proje klasörleri (`.projectArtifacts` kökleri).
    private(set) var projectFolders: [String] = []
    @ObservationIgnored let folderStore: ProjectFoldersStore
    var scannedCategories: Set<CleanupCategory> = []
    var trashState: (state: CleanupRootState, bytes: UInt64)?
    var log: [CleanupLogEntry] = []
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init(home: String = NSHomeDirectory(), probe: PathProbe = .live, folderStore: ProjectFoldersStore? = nil) {
        self.home = home
        self.folderStore = folderStore ?? ProjectFoldersStore(home: home)
        access = CleanupAccessMonitor(home: home, probe: probe)
        projectFolders = self.folderStore.folders
        access.onUnblocked = { [weak self] paths in self?.rescanUnblocked(paths) }
    }

    var isBusy: Bool { phase != .idle }

    var selectedItems: [CleanupItem] { items.filter { selection.contains($0.id) && $0.blockedReason == nil } }

    func items(in category: CleanupCategory) -> [CleanupItem] { items.filter { $0.category == category } }

    /// Kategorinin kök yolları (proje artıklarında kullanıcının seçtiği klasörler).
    func rootPaths(for category: CleanupCategory) -> [String] {
        category == .projectArtifacts ? projectFolders : CleanupCatalog.roots(home: home).filter { $0.category == category }.map(\.path)
    }

    /// Kategorinin köklerinden türetilen durum (biri tarandıysa taranmış sayılır).
    func state(of category: CleanupCategory) -> CleanupRootState? {
        let states = rootPaths(for: category).compactMap { rootStates[$0] }
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
        let projects = projectFolders
        phase = .scanning(categories.first)
        lastResult = nil
        scanTask = Task.detached(priority: .utility) { [weak self] in
            let out = CleanupScanner.scan(categories: categories, home: home, runningBundleIDs: running, projectRoots: projects,
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
        var categories = CleanupCatalog.roots(home: home).filter { freed.contains($0.path) }.map(\.category)
        if projectFolders.contains(where: freed.contains) { categories.append(.projectArtifacts) }
        var seen = Set<CleanupCategory>()
        let ordered = categories.filter { seen.insert($0).inserted }
        let trashFreed = freed.contains(CleanupCatalog.trashPath(home: home))
        if trashFreed { trashState = nil }
        if !ordered.isEmpty { scan(ordered) } else if trashFreed { measureTrash() }
    }

    /// Kategorinin erişilemeyen ilk kökünün nedeni.
    func accessReason(for category: CleanupCategory) -> AccessReason? {
        rootPaths(for: category).lazy.compactMap { self.access.reason(for: $0) }.first
    }

    /// Proje klasörü ekler (örn. NSOpenPanel seçimi); reddedilirse kullanıcıya gösterilecek metin döner.
    @discardableResult
    func addProjectFolder(_ path: String) -> String? {
        if let error = folderStore.add(path) { return error.message }
        projectFolders = folderStore.folders
        return nil
    }

    func removeProjectFolder(_ path: String) {
        folderStore.remove(path)
        projectFolders = folderStore.folders
        let removedIDs = Set(items.filter { $0.category == .projectArtifacts && $0.rootPath == path }.map(\.id))
        items.removeAll { removedIDs.contains($0.id) }
        selection.subtract(removedIDs)
        rootStates[path] = nil
        access.setBlocked(path, false)
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

/// Sistem çöpü ve Geliştirici bölümlerinin sihirbazı: karşılama → tarama → sonuç → bitti.
/// Mantık `CleanupViewModel`dedir (varsayılan seçimler, açık tarayıcı engeli, erişim akışı); burası yalnızca görünümdür.
/// Silme yalnızca `CleanupViewModel.deleteSelected` (CleanupDeleter) ve `DeleteConfirmation` üzerinden yapılır.
struct CleanupView: View {
    let group: CleanupGroup
    @State private var vm = CleanupViewModel()
    @State private var confirmSummary: DeleteSummary?
    /// Onay penceresinde özetlenen öğelerin kendisi.
    @State private var confirmItems: [CleanupItem] = []
    @State private var helpReason: AccessReason?
    @State private var showDone = false
    /// Karşılamadaki "Tara" ile başlayan tarama (tam ekran ilerleme). Kart içi taramalar satır içinde kalır.
    @State private var wizardScan = false
    @State private var reachedStep = 0
    private let toolModels: [ToolCommandModel]?

    init(group: CleanupGroup = .junk) {
        self.group = group
        toolModels = nil
    }

    /// Önizleme testleri için: hazır model, başlangıç adımı (kutlama) ve hazır araç modelleri.
    init(group: CleanupGroup, model: CleanupViewModel, startDone: Bool = false, toolModels: [ToolCommandModel]? = nil) {
        self.group = group
        _vm = State(initialValue: model)
        _showDone = State(initialValue: startDone)
        self.toolModels = toolModels
    }

    private var subsection: CleanupSubsection { group == .junk ? .junk : .dev }
    private var accent: CleanupAccent { subsection.accent }
    private var hasScanned: Bool { !vm.scannedCategories.isDisjoint(with: group.scanCategories) }

    private var isScanning: Bool {
        if case .scanning = vm.phase { return true }
        return false
    }

    private var phaseCategory: CleanupCategory? {
        if case .scanning(let category) = vm.phase { return category }
        return nil
    }

    private var step: CleanupWizardStep {
        if isScanning, wizardScan || !hasScanned { return .scanning }
        if !hasScanned { return .welcome }
        return showDone ? .done : .result
    }

    var body: some View {
        CleanupWizard(step: step) {
            welcome
        } scanning: {
            scanning
        } result: {
            result
        } done: {
            done
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
        .onChange(of: vm.phase) { old, new in
            switch new {
            case .idle:
                wizardScan = false
                if old == .deleting, (vm.lastResult ?? []).contains(where: \.isRemoved) { showDone = true }
            case .scanning(let category):
                showDone = false
                if let category, let index = group.scanCategories.firstIndex(of: category) { reachedStep = max(reachedStep, index) }
            case .deleting:
                break
            }
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

    private func startScan() {
        reachedStep = 0
        wizardScan = true
        vm.scan(group.scanCategories)
    }

    // MARK: 1. Karşılama

    private var welcome: some View {
        CleanupHero3D(
            symbol: subsection.symbol, accent: accent, badgeSymbol: group == .junk ? "sparkles" : "terminal",
            title: subsection.title,
            subtitle: group == .junk
                ? "Uygulama ve tarayıcı önbelleklerini ile günlükleri bulur. Siz onaylamadan hiçbir şey silinmez; seçilenler Çöp Sepeti'ne taşınır."
                : "Xcode, simülatör ve paket yöneticisi önbelleklerini bulur; proje artıkları ve Homebrew / Docker temizliği sonuç ekranındadır. Siz onaylamadan hiçbir şey silinmez.",
            primaryTitle: "Tara", primarySymbol: "magnifyingglass", action: { startScan() },
            accessory: { CleanupFullDiskBadge(vm: vm) { helpReason = $0 } }
        )
    }

    // MARK: 2. Tarama

    private var scanning: some View {
        let categories = group.scanCategories
        let phaseIndex = phaseCategory.flatMap { categories.firstIndex(of: $0) } ?? 0
        let reached = max(reachedStep, phaseIndex)
        let steps = categories.enumerated().map { index, category in
            CleanupScanStepInfo(id: category.rawValue, title: category.title,
                                state: index < reached ? .done : (index == reached ? .active : .pending))
        }
        return CleanupScanProgress(
            accent: accent, symbol: categories.indices.contains(reached) ? categories[reached].systemImage : subsection.symbol,
            fraction: Double(reached) / Double(max(1, categories.count)),
            title: "Taranıyor: \(categories.indices.contains(reached) ? categories[reached].title : "")…", steps: steps
        ) { vm.cancel() }
    }

    // MARK: 3. Sonuç

    private var visibleCategories: [CleanupCategory] {
        group.categories.filter { category in
            if category.needsExplicitScan { return true }
            guard vm.scannedCategories.contains(category), let state = vm.state(of: category), state != .missing else { return false }
            return state == .noAccess || !vm.items(in: category).isEmpty
        }
    }

    private var result: some View {
        let allItems = group.categories.flatMap { vm.items(in: $0) }
        let found = allItems.filter { $0.blockedReason == nil }.reduce(UInt64(0)) { $0 + $1.bytes }
        let nothing = allItems.isEmpty && vm.access.blocked.isEmpty
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if nothing {
                        CleanupAllCleanView(accent: accent, subtitle: "Temizlenecek bir şey bulunamadı.",
                                            primaryTitle: "Yeniden tara", onPrimary: { startScan() }, compact: true)
                    } else {
                        CleanupResultHeader(bytes: found, caption: "bulundu", accent: accent, notes: [headerNote])
                    }
                    CleanupFullDiskBadge(vm: vm) { helpReason = $0 }.frame(maxWidth: .infinity)
                    if !vm.access.blocked.isEmpty { CleanupAccessBanner(vm: vm) { helpReason = $0 } }
                    if let results = vm.lastResult {
                        CleanupDeletionBanner(results: results, mode: vm.lastMode, home: vm.home)
                    }
                    ForEach(visibleCategories) { category in
                        CleanupCategoryCard(vm: vm, category: category, state: vm.state(of: category), accent: accent,
                                            onHelp: { helpReason = $0 })
                    }
                    if group == .junk { CleanupTrashCard(vm: vm, accent: accent) { helpReason = $0 } }
                    if group == .dev { ToolCommandCards(accent: accent, models: toolModels) }
                    CleanupLogCard(vm: vm, accent: accent)
                }
                .padding(.bottom, 10)
            }
            if found > 0 { actionBar.padding(.top, 8).padding(.bottom, 4) }
        }
    }

    private var headerNote: String {
        switch group {
        case .junk: "Önbellekler işaretli gelir. Günlükler, iOS yedekleri ve İndirilenler yalnızca listelenir; siz seçersiniz."
        case .dev: "Önbellekler işaretli gelir. Arşivler, cihaz destek dosyaları ve proje artıkları yalnızca listelenir; siz seçersiniz."
        }
    }

    private var actionBar: some View {
        let selected = vm.selectedItems
        let bytes = selected.reduce(UInt64(0)) { $0 + $1.bytes }
        return CleanupActionBar(
            countText: "\(selected.count) öğe seçili", bytes: bytes, mode: $vm.deleteMode,
            isEnabled: !selected.isEmpty && !vm.isBusy, isBusy: vm.phase == .deleting, accent: accent
        ) {
            confirmItems = selected
            confirmSummary = DeleteSummary(
                count: selected.count, bytes: bytes, mode: vm.deleteMode,
                sample: selected.prefix(5).map { FolderWatchList.displayPath($0.path, home: vm.home) }
            )
        } leading: {
            Button { startScan() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).disabled(vm.isBusy).help("Yeniden tara").accessibilityLabel("Yeniden tara")
        }
    }

    // MARK: 4. Bitti

    private var done: some View {
        let results = vm.lastResult ?? []
        let moved = results.filter(\.isRemoved)
        let skipped = results.count - moved.count
        let bytes = moved.reduce(UInt64(0)) { $0 + $1.candidate.bytes }
        let trashed = vm.lastMode == .trash
        var detail = "\(moved.count) öğe \(trashed ? "taşındı" : "kalıcı olarak silindi")"
        detail += skipped > 0 ? ", \(skipped) atlandı." : "."
        if trashed { detail += " Disk alanı, Çöp Sepeti'ni boşaltınca açılır." }
        return CleanupDoneView(
            accent: accent, bytes: bytes, headline: trashed ? "Çöp Sepeti'ne taşındı" : "boşaltıldı", detail: detail,
            secondaryTitle: "Sonuçlara dön", onSecondary: { showDone = false }
        ) { startScan() }
    }
}
