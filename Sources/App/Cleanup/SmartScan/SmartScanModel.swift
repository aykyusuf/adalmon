import AppKit
import Foundation

/// Akıllı tarama modeli. Temizlik sayfasının (yönlendiricinin) ömrü boyunca yaşar: alt bölüm değişince sonuçlar kaybolmaz.
/// Tarama yalnızca `scan()` ile başlar, `Task.detached(.utility)` içinde çalışır ve iptal edilebilir; zamanlayıcı yoktur.
@MainActor @Observable
final class SmartScanModel {
    enum Phase: Equatable { case idle, scanning, deleting }

    let home: String
    var phase: Phase = .idle
    var result = SmartScanResult()
    var hasScanned = false
    var scannedAt: Date?
    /// Şu an taranan adım ve adım içi ayrıntı (proje kökü adı).
    var currentStep: SmartScanStep?
    var currentDetail: String?
    /// Seçili öğelerin yolları (yalnızca temizlenebilir adımların öğeleri).
    var selection: Set<String> = []
    var expanded: Set<SmartScanStep> = []
    var deleteMode: DeleteMode = .trash
    var lastResult: [CleanupResult]?
    var lastMode: DeleteMode = .trash
    @ObservationIgnored let folderStore: ProjectFoldersStore
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    /// Geç gelen eski tarama bildirimlerini yok saymak için.
    @ObservationIgnored private var scanID = UUID()

    init(home: String = NSHomeDirectory(), folderStore: ProjectFoldersStore? = nil) {
        self.home = home
        self.folderStore = folderStore ?? ProjectFoldersStore(home: home)
    }

    var isBusy: Bool { phase != .idle }
    var isScanning: Bool { phase == .scanning }

    /// Seçilebilir (engelli olmayan) tüm öğeler ve seçili olanlar.
    var allItems: [CleanupItem] { result.allCleanableItems }
    var selectedItems: [CleanupItem] { allItems.filter { selection.contains($0.id) } }
    var selectedBytes: UInt64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    var foundBytes: UInt64 { result.cleanableBytes() }

    func items(for step: SmartScanStep) -> [CleanupItem] { result.results[step]?.cleanableItems ?? [] }

    /// Adımdaki seçili öğe sayısı (onay kutusunun üç durumu için).
    func selectedCount(for step: SmartScanStep) -> Int { items(for: step).filter { selection.contains($0.id) }.count }

    func isSelected(_ item: CleanupItem) -> Bool { selection.contains(item.id) }

    func toggle(_ item: CleanupItem) {
        guard item.blockedReason == nil else { return }
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    /// Adımın hepsini seç / bırak (hepsi seçiliyse bırakır).
    func toggleAll(_ step: SmartScanStep) {
        let ids = Set(items(for: step).map(\.id))
        if ids.isSubset(of: selection) { selection.subtract(ids) } else { selection.formUnion(ids) }
    }

    // MARK: Tarama

    func scan(now: Date = Date()) {
        guard !isBusy else { return }
        let running = CleanupViewModel.runningBundleIDs()
        let home = home
        let folders = folderStore.folders
        phase = .scanning
        currentStep = nil
        currentDetail = nil
        lastResult = nil
        result = SmartScanResult()
        selection = []
        let id = UUID()
        scanID = id
        scanTask = Task.detached(priority: .utility) { [weak self] in
            let out = SmartScanAggregator.run(
                home: home, runningBundleIDs: running, projectFolders: folders, now: now, isCancelled: { Task.isCancelled },
                stepStarted: { step in Task { @MainActor [weak self] in
                    guard self?.scanID == id else { return }
                    self?.currentStep = step
                    self?.currentDetail = nil
                } },
                detail: { text in Task { @MainActor [weak self] in
                    if self?.scanID == id { self?.currentDetail = text }
                } },
                stepFinished: { partial in Task { @MainActor [weak self] in
                    guard self?.scanID == id else { return }
                    self?.result.results[partial.step] = partial
                    self?.result.completed.append(partial.step)
                } }
            )
            await self?.finish(out, id: id, now: now)
        }
    }

    /// Çalışan taramayı durdurur; tamamlanan adımlar korunur. Silme sürerken bir şey yapmaz.
    func cancel() {
        guard phase == .scanning else { return }
        scanTask?.cancel()
        scanTask = nil
        scanID = UUID()
        result.wasCancelled = true
        adopt(result, now: Date())
    }

    func finish(_ out: SmartScanResult, id: UUID, now: Date) {
        guard scanID == id, phase == .scanning else { return }
        scanTask = nil
        adopt(out, now: now)
    }

    /// Bitmiş (ya da yarım kalmış) sonucu benimser: varsayılan seçimi kurar.
    func adopt(_ out: SmartScanResult, now: Date) {
        result = out
        selection = SmartScanSelection.defaultSelection(out, now: now)
        hasScanned = true
        scannedAt = now
        currentStep = nil
        currentDetail = nil
        phase = .idle
    }

    // MARK: Silme

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
                self?.deleteFinished(results, mode: mode)
            }
        }
    }

    func deleteFinished(_ results: [CleanupResult], mode: DeleteMode) {
        let removed = Set(results.filter(\.isRemoved).map(\.candidate.id))
        for (step, var stepResult) in result.results {
            stepResult.items.removeAll { removed.contains($0.id) }
            result.results[step] = stepResult
        }
        selection.subtract(removed)
        lastResult = results
        lastMode = mode
        deleteMode = .trash
        phase = .idle
    }

    /// Son temizlikte kaldırılan öğe sayısı ve boyutu.
    var lastFreed: (count: Int, bytes: UInt64, skipped: Int)? {
        guard let lastResult else { return nil }
        let moved = lastResult.filter(\.isRemoved)
        return (moved.count, moved.reduce(UInt64(0)) { $0 + $1.candidate.bytes }, lastResult.count - moved.count)
    }
}
