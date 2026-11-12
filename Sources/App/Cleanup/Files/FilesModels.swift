import Foundation

enum FilesPhase: Equatable {
    case idle, scanning, deleting
}

/// Büyük & eski ve Kopyalar'ın ortak silme yolu: her zaman `CleanupDeleter` (öncelik: yardımcı iş parçacığı, hata fırlatmaz).
enum FilesDeletion {
    static func run(_ candidates: [DeletionCandidate], mode: DeleteMode, home: String) async -> [CleanupResult] {
        let deleter = CleanupDeleter(home: home)
        return await Task.detached(priority: .utility) { deleter.delete(candidates, mode: mode) }.value
    }
}

/// İlerleme metnini seyrekleştirir (yoğun taramada ana iş parçacığını yormasın).
final class FilesProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast
    private let interval: TimeInterval

    init(interval: TimeInterval = 0.2) { self.interval = interval }

    func shouldEmit(now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard now.timeIntervalSince(last) >= interval else { return false }
        last = now
        return true
    }
}

@MainActor @Observable
final class LargeOldModel {
    static let sizeChoices: [UInt64] = [50 << 20, 100 << 20, 500 << 20, 1 << 30]
    static let ageChoices = [90, 180, 365, 730]

    let home: String
    let rootsStore: FileRootsStore
    let access: CleanupAccessMonitor
    var phase: FilesPhase = .idle
    var progressText = ""
    private(set) var items: [LargeOldItem] = []
    private(set) var hasScanned = false
    private(set) var unreadableDirs = 0
    private(set) var filesSeen = 0
    private(set) var rootStates: [String: CleanupRootState] = [:]
    /// Yalnızca yeniden tarama gerektirir (tarama eşiği).
    var minBytes: UInt64 = LargeOldScanner.defaultMinBytes
    var onlyOld = false
    var oldDays = LargeOldScanner.defaultOldDays
    var selection: Set<String> = []
    var lastResult: [CleanupResult]?
    var lastMode: DeleteMode = .trash
    /// Yalnızca sonraki işlem için; işlem bitince Çöp'e döner.
    var deleteMode: DeleteMode = .trash
    @ObservationIgnored private var scannedRoots: [String] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(home: String = NSHomeDirectory(), rootsStore: FileRootsStore? = nil, probe: PathProbe = .live) {
        self.home = home
        self.rootsStore = rootsStore ?? FileRootsStore.shared
        access = CleanupAccessMonitor(home: home, probe: probe)
        access.onUnblocked = { [weak self] _ in self?.scan() }
    }

    var isBusy: Bool { phase != .idle }

    var visibleItems: [LargeOldItem] { LargeOldScanner.filter(items, onlyOld: onlyOld, olderThanDays: oldDays) }
    var selectedItems: [LargeOldItem] { visibleItems.filter { selection.contains($0.id) } }
    var visibleBytes: UInt64 { visibleItems.reduce(0) { $0 + $1.bytes } }

    func scan() {
        guard !isBusy else { return }
        let roots = rootsStore.roots
        guard !roots.isEmpty else { return }
        scannedRoots = roots
        phase = .scanning
        generation += 1
        let id = generation
        progressText = "Başlıyor…"
        lastResult = nil
        let scanner = LargeOldScanner(minBytes: minBytes, skipPaths: FileWalker.defaultSkipPaths(home: home))
        let gate = FilesProgressGate()
        task = Task.detached(priority: .utility) { [weak self] in
            let result = scanner.scan(roots: roots, isCancelled: { Task.isCancelled }, progress: { p in
                guard gate.shouldEmit() else { return }
                let text = "\(p.files.formatted()) dosya · \(FolderWatchList.displayPath(p.directory))"
                Task { @MainActor [weak self] in
                    if self?.phase == .scanning { self?.progressText = text }
                }
            })
            await self?.apply(result, id: id)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase == .scanning { phase = .idle }
    }

    private func apply(_ result: LargeOldResult, id: Int) {
        guard phase == .scanning, id == generation else { return }
        task = nil
        phase = .idle
        if result.cancelled { return }
        items = result.items
        rootStates = result.rootStates
        unreadableDirs = result.unreadableDirs
        filesSeen = result.filesSeen
        hasScanned = true
        selection = selection.intersection(Set(result.items.map(\.id)))
        access.update(states: result.rootStates)
    }

    func toggle(_ item: LargeOldItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func selectAllVisible(_ on: Bool) {
        if on { selection.formUnion(visibleItems.map(\.id)) } else { selection.subtract(visibleItems.map(\.id)) }
    }

    /// `chosen`: onay penceresinde gösterilen öğeler; yalnızca bunlar silinir.
    func deleteSelected(mode: DeleteMode, items chosen: [LargeOldItem]) {
        guard !chosen.isEmpty, !isBusy else {
            deleteMode = .trash
            return
        }
        let candidates = chosen.map { $0.candidate(roots: scannedRoots) }
        phase = .deleting
        let home = home
        Task { [weak self] in
            let results = await FilesDeletion.run(candidates, mode: mode, home: home)
            guard let self else { return }
            let removed = Set(results.filter(\.isRemoved).map(\.candidate.id))
            items.removeAll { removed.contains($0.id) }
            selection.subtract(removed)
            lastResult = results
            lastMode = mode
            deleteMode = .trash
            phase = .idle
        }
    }
}

@MainActor @Observable
final class DuplicatesModel {
    let home: String
    let rootsStore: FileRootsStore
    let access: CleanupAccessMonitor
    var phase: FilesPhase = .idle
    var progressText = ""
    var progressFraction: Double?
    private(set) var groups: [DuplicateGroup] = []
    private(set) var selection = DuplicateSelection(groups: [])
    private(set) var hasScanned = false
    private(set) var unreadableDirs = 0
    private(set) var filesSeen = 0
    var minBytes: UInt64 = DuplicateFinder.defaultMinBytes
    var lastResult: [CleanupResult]?
    var lastMode: DeleteMode = .trash
    var deleteMode: DeleteMode = .trash
    @ObservationIgnored private var scannedRoots: [String] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(home: String = NSHomeDirectory(), rootsStore: FileRootsStore? = nil, probe: PathProbe = .live) {
        self.home = home
        self.rootsStore = rootsStore ?? FileRootsStore.shared
        access = CleanupAccessMonitor(home: home, probe: probe)
        access.onUnblocked = { [weak self] _ in self?.scan() }
    }

    var isBusy: Bool { phase != .idle }
    var selectedFiles: [DuplicateFile] { selection.selectedFiles(in: groups) }
    var reclaimableBytes: UInt64 { groups.reduce(0) { $0 + $1.reclaimableBytes } }

    func scan() {
        guard !isBusy else { return }
        let roots = rootsStore.roots
        guard !roots.isEmpty else { return }
        scannedRoots = roots
        phase = .scanning
        generation += 1
        let id = generation
        progressText = "Dosyalar listeleniyor…"
        progressFraction = nil
        lastResult = nil
        let finder = DuplicateFinder(minBytes: minBytes, skipPaths: FileWalker.defaultSkipPaths(home: home))
        let gate = FilesProgressGate()
        task = Task.detached(priority: .utility) { [weak self] in
            let result = finder.find(roots: roots, isCancelled: { Task.isCancelled }, progress: { p in
                guard gate.shouldEmit() else { return }
                let name = (p.detail as NSString).lastPathComponent
                let text: String
                var fraction: Double?
                switch p.phase {
                case .listing: text = "\(p.done.formatted()) dosya · \(FolderWatchList.displayPath(p.detail))"
                case .prefixHash:
                    text = "İlk bölümler karşılaştırılıyor (\(p.done)/\(p.total)) · \(name)"
                    fraction = p.total > 0 ? Double(p.done) / Double(p.total) : nil
                case .fullHash:
                    text = "Tam içerik karşılaştırılıyor (\(p.done)/\(p.total)) · \(name)"
                    fraction = p.total > 0 ? Double(p.done) / Double(p.total) : nil
                }
                Task { @MainActor [weak self] in
                    guard self?.phase == .scanning else { return }
                    self?.progressText = text
                    self?.progressFraction = fraction
                }
            })
            await self?.apply(result, id: id)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase == .scanning { phase = .idle }
    }

    private func apply(_ result: DuplicateResult, id: Int) {
        guard phase == .scanning, id == generation else { return }
        task = nil
        phase = .idle
        progressFraction = nil
        if result.cancelled { return }
        groups = result.groups
        selection = DuplicateSelection(groups: result.groups)
        unreadableDirs = result.unreadableDirs
        filesSeen = result.filesSeen
        hasScanned = true
        access.update(states: result.rootStates)
    }

    func toggle(_ file: DuplicateFile, in group: DuplicateGroup) { selection.toggle(file.path, in: group) }
    func setKeeper(_ file: DuplicateFile, in group: DuplicateGroup) { selection.setKeeper(file.path, in: group) }
    func selectAllButKeepers() { selection.selectAllButKeepers(in: groups) }
    func clearSelection() { selection.clear() }

    /// `chosen`: onay penceresinde gösterilen dosyalar. Silmeden önce korunan kopyalar ve silinecekler yeniden denetlenir.
    func deleteSelected(mode: DeleteMode, files chosen: [DuplicateFile]) {
        guard !chosen.isEmpty, !isBusy else {
            deleteMode = .trash
            return
        }
        let chosenPaths = Set(chosen.map(\.path))
        var scoped = selection
        scoped.restrict(to: chosenPaths)
        let verified = scoped.verifiedDeletions(in: groups)
        let candidates = verified.deletable.map { $0.candidate(roots: scannedRoots) }
        let refused = verified.refused.map {
            CleanupResult(candidate: $0.file.candidate(roots: scannedRoots), outcome: .failed($0.reason))
        }
        phase = .deleting
        let home = home
        Task { [weak self] in
            let results = await FilesDeletion.run(candidates, mode: mode, home: home) + refused
            guard let self else { return }
            let removed = Set(results.filter(\.isRemoved).map(\.candidate.path))
            applyRemoval(removed)
            lastResult = results
            lastMode = mode
            deleteMode = .trash
            phase = .idle
        }
    }

    private func applyRemoval(_ removed: Set<String>) {
        guard !removed.isEmpty else { return }
        let old = selection
        groups = groups.compactMap { group in
            let rest = group.files.filter { !removed.contains($0.path) }
            guard rest.count > 1 else { return nil }
            return DuplicateGroup(id: group.id, size: group.size, files: rest)
        }
        selection = DuplicateSelection(groups: groups)
        selection.restore(from: old, in: groups)
    }
}
