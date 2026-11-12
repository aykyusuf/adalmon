import Foundation

/// Yer kaplayanlar: bir klasörün alt öğelerini tarar, treemap için düğüm listesi tutar. Salt okunurdur (silme yok).
/// Tarama yalnızca tıklayınca başlar; her klasör bir kez ölçülür ve geri dönüşte önbellekten gelir.
@MainActor @Observable
final class SpaceLensModel {
    enum Phase: Equatable { case idle, scanning }

    let home: String
    let access: CleanupAccessMonitor
    var phase: Phase = .idle
    var progressText = ""
    var progressFraction: Double?
    /// Kökten geçerli klasöre yollar.
    private(set) var trail: [String] = []
    private(set) var cache: [String: [SpaceNode]] = [:]
    private(set) var lastState: CleanupRootState = .scanned
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let scanner: SpaceLensScanner

    init(home: String = NSHomeDirectory(), probe: PathProbe = .live) {
        self.home = home
        scanner = SpaceLensScanner(home: home, probe: probe)
        access = CleanupAccessMonitor(home: home, probe: probe)
        access.onUnblocked = { [weak self] _ in
            guard let self, let current else { return }
            cache[current] = nil
            open(current, pushing: false)
        }
    }

    var isBusy: Bool { phase != .idle }
    var current: String? { trail.last }
    var nodes: [SpaceNode] { current.flatMap { cache[$0] } ?? [] }
    var canGoBack: Bool { trail.count > 1 }
    var totalBytes: UInt64 { nodes.reduce(0) { $0 + $1.bytes } }
    var hiddenNodes: [SpaceNode] { nodes.filter { !$0.isMeasured } }

    /// Yeni kökten başlar (önbellek korunur).
    func start(root: String) {
        guard !isBusy else { return }
        trail = []
        open(root, pushing: true)
    }

    /// Klasörün içine girer: önbellekte yoksa tarar.
    func open(_ path: String, pushing: Bool = true) {
        guard !isBusy else { return }
        if cache[path] != nil {
            if pushing { trail.append(path) }
            return
        }
        phase = .scanning
        generation += 1
        let id = generation
        progressText = "Taranıyor…"
        progressFraction = nil
        let scanner = scanner
        let gate = FilesProgressGate()
        task = Task.detached(priority: .utility) { [weak self] in
            let scan = scanner.scan(path: path, isCancelled: { Task.isCancelled }, progress: { done, total, name in
                guard gate.shouldEmit() else { return }
                Task { @MainActor [weak self] in
                    guard self?.phase == .scanning else { return }
                    self?.progressText = "\(FolderWatchList.displayPath(path)) · \(name)"
                    self?.progressFraction = total > 0 ? Double(done) / Double(total) : nil
                }
            })
            await self?.finish(scan, path: path, pushing: pushing, id: id)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase == .scanning { phase = .idle }
    }

    private func finish(_ scan: SpaceLensScan, path: String, pushing: Bool, id: Int) {
        guard phase == .scanning, id == generation else { return }
        task = nil
        phase = .idle
        progressFraction = nil
        if scan.cancelled { return }
        lastState = scan.state
        access.setBlocked(path, scan.state == .noAccess)
        guard scan.state == .scanned else {
            if trail.isEmpty { trail = [path] }
            return
        }
        cache[path] = scan.nodes
        if pushing { trail.append(path) }
    }

    func back() {
        guard canGoBack, !isBusy else { return }
        trail.removeLast()
    }

    /// Breadcrumb: `index`teki klasöre döner.
    func go(to index: Int) {
        guard trail.indices.contains(index), !isBusy else { return }
        trail = Array(trail.prefix(index + 1))
    }

    /// Önbelleği atıp geçerli klasörü yeniden tarar.
    func rescan() {
        guard let current, !isBusy else { return }
        cache[current] = nil
        open(current, pushing: false)
    }
}
