import Foundation

/// Yer kaplayanlar: bir klasörün alt ağacını bir kez tarar, treemap için düğüm listesini önbellekten verir. Salt okunurdur (silme yok).
/// Tarama yalnızca kullanıcı tıklayınca başlar; içine girme ve geri dönüş önbellekten anında gelir. Düğüm tavanı aşılan (tembel)
/// seviyeler tıklanınca taranır; görünürken bir sonraki seviye arka planda önceden hazırlanır (zamanlayıcı yok).
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
    private(set) var cache: [String: SpaceDir] = [:]
    private(set) var lastState: CleanupRootState = .scanned
    /// Görünür sayfa bir sonraki seviyeyi önceden hazırlayabilir (sayfa kapanınca kapatılır).
    private(set) var prefetchEnabled = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    @ObservationIgnored private var prefetchingPath: String?
    @ObservationIgnored private var prefetchGeneration = 0
    @ObservationIgnored private var prefetchAttempted = Set<String>()
    /// Önceden hazırlanan klasöre tıklandı: hazır olunca açılır.
    @ObservationIgnored private var pendingOpen: (path: String, pushing: Bool)?
    @ObservationIgnored private let scanner: any SpaceTreeScanning
    /// Önbellekteki toplam düğüm bunu aşarsa, geçerli yol dışındakiler atılır.
    @ObservationIgnored private let cacheNodeLimit: Int
    static let prefetchCount = 3

    init(home: String = NSHomeDirectory(), probe: PathProbe = .live, scanner: (any SpaceTreeScanning)? = nil,
         cacheNodeLimit: Int = SpaceLensScanner.defaultMaxStoredNodes * 2) {
        self.home = home
        self.scanner = scanner ?? SpaceLensScanner(home: home, probe: probe)
        self.cacheNodeLimit = cacheNodeLimit
        access = CleanupAccessMonitor(home: home, probe: probe)
        access.onUnblocked = { [weak self] _ in
            guard let self, let current else { return }
            invalidate(current)
            open(current, pushing: false)
        }
    }

    var isBusy: Bool { phase != .idle }
    var current: String? { trail.last }
    var currentDir: SpaceDir? { current.flatMap { cache[$0] } }
    var nodes: [SpaceNode] { currentDir?.nodes ?? [] }
    var canGoBack: Bool { trail.count > 1 }
    var totalBytes: UInt64 { currentDir?.totalBytes ?? 0 }
    /// Küçük olduğu için tek tek tutulmayan öğeler.
    var otherBytes: UInt64 { currentDir?.otherBytes ?? 0 }
    var otherCount: Int { currentDir?.otherCount ?? 0 }
    var hiddenNodes: [SpaceNode] { nodes.filter { !$0.isMeasured } }

    /// Kullanıcı "tara" dedi: kökten (taze) başlar; o köke ait önbellek atılır.
    func start(root: String) {
        guard !isBusy else { return }
        cancelPrefetch()
        invalidate(root)
        trail = []
        open(root, pushing: true)
    }

    /// Klasörün içine girer: önbellekte varsa anında; yoksa (tembel seviye) tarar.
    func open(_ path: String, pushing: Bool = true) {
        guard !isBusy else { return }
        if cache[path] != nil {
            if pushing { trail.append(path) }
            prefetch()
            return
        }
        if prefetchingPath == path {
            // Zaten hazırlanıyor: yeniden taramak yerine bitmesini bekle.
            pendingOpen = (path, pushing)
            phase = .scanning
            progressText = "\(FolderWatchList.displayPath(path, home: home)) · hazırlanıyor…"
            progressFraction = nil
            return
        }
        cancelPrefetch()
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
        cancelPrefetch()
        if phase == .scanning { phase = .idle }
    }

    /// Sayfa görünür/gizli: gizlenince önceden hazırlama durur.
    func setVisible(_ visible: Bool) {
        prefetchEnabled = visible
        if visible { prefetch() } else { cancelPrefetch() }
    }

    /// Tamamlanana kadar bekler (testler için).
    func waitUntilIdle() async {
        while let running = task ?? prefetchTask {
            await running.value
            if task == running { task = nil }
            if prefetchTask == running { prefetchTask = nil }
        }
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
        store(scan)
        if pushing { trail.append(path) } else { patchAncestors(of: path) }
        evictIfNeeded()
        prefetch()
    }

    func back() {
        guard canGoBack, !isBusy else { return }
        trail.removeLast()
        prefetch()
    }

    /// Breadcrumb: `index`teki klasöre döner.
    func go(to index: Int) {
        guard trail.indices.contains(index), !isBusy else { return }
        trail = Array(trail.prefix(index + 1))
        prefetch()
    }

    /// Önbelleği atıp geçerli klasörü (ve altını) yeniden tarar; üst klasörlerin boyutu yeni değere göre düzeltilir.
    func rescan() {
        guard let current, !isBusy else { return }
        cancelPrefetch()
        invalidate(current)
        open(current, pushing: false)
    }

    // MARK: Önbellek

    /// `path` ve altındaki tüm kayıtlar atılır.
    private func invalidate(_ path: String) {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        prefetchAttempted.removeAll()
        cache = cache.filter { $0.key != path && !$0.key.hasPrefix(prefix) }
    }

    private func store(_ scan: SpaceLensScan) {
        for (path, dir) in scan.dirs { cache[path] = dir }
    }

    /// Yeniden taranan klasörün yeni boyutunu üst klasörlerdeki düğümlere yansıtır.
    private func patchAncestors(of path: String) {
        guard let bytes = cache[path]?.totalBytes, let index = trail.firstIndex(of: path), index > 0 else { return }
        var child = path
        for parent in trail[..<index].reversed() {
            guard let updated = cache[parent]?.replacingFolder(child, bytes: bytes) else { return }
            cache[parent] = updated
            child = parent
        }
    }

    /// Bellek sınırı: tavan aşılırsa geçerli yoldaki klasörler kalır, geri kalanı atılır (gerektiğinde yeniden taranır).
    private func evictIfNeeded() {
        let count = cache.values.reduce(0) { $0 + $1.nodes.count }
        guard count > cacheNodeLimit else { return }
        let keep = Set(trail)
        cache = cache.filter { keep.contains($0.key) }
    }

    // MARK: Önceden hazırlama

    private func cancelPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchingPath = nil
        prefetchGeneration += 1
        if pendingOpen != nil {
            pendingOpen = nil
            if task == nil, phase == .scanning { phase = .idle }
        }
    }

    /// Geçerli klasörün önbellekte olmayan (tembel) en büyük alt klasörlerini arka planda sırayla tarar. Tavanı aşmayan
    /// ağaçlarda bu liste boştur ve hiçbir şey yapılmaz. Aynı klasör bir kez denenir (zamanlayıcı/yeniden deneme döngüsü yok).
    private func prefetch() {
        guard prefetchEnabled, !isBusy, prefetchTask == nil, let dir = currentDir else { return }
        let targets = dir.nodes.filter { $0.isFolder && cache[$0.path] == nil && !prefetchAttempted.contains($0.path) }
            .prefix(Self.prefetchCount).map(\.path)
        guard !targets.isEmpty else { return }
        prefetchGeneration += 1
        let id = prefetchGeneration
        let scanner = scanner
        prefetchTask = Task.detached(priority: .utility) { [weak self] in
            for path in targets {
                if Task.isCancelled { break }
                guard await self?.markPrefetching(path, id: id) == true else { break }
                let scan = scanner.scan(path: path, isCancelled: { Task.isCancelled }, progress: { _, _, _ in })
                if Task.isCancelled { break }
                await self?.finishPrefetch(scan, path: path, id: id)
            }
            await self?.prefetchEnded(id: id)
        }
    }

    private func markPrefetching(_ path: String, id: Int) -> Bool {
        guard id == prefetchGeneration else { return false }
        prefetchingPath = path
        prefetchAttempted.insert(path)
        return true
    }

    private func finishPrefetch(_ scan: SpaceLensScan, path: String, id: Int) {
        guard id == prefetchGeneration, prefetchingPath == path else { return }
        prefetchingPath = nil
        let wanted = pendingOpen?.path == path ? pendingOpen : nil
        let ok = scan.state == .scanned && !scan.cancelled
        if ok { store(scan) }
        guard let wanted else { return }
        pendingOpen = nil
        phase = .idle
        progressFraction = nil
        if ok {
            if wanted.pushing { trail.append(path) }
            evictIfNeeded()
        } else {
            // Erişilemeyen klasör: normal yoldan (erişim durumu bildirilir).
            open(path, pushing: wanted.pushing)
        }
    }

    private func prefetchEnded(id: Int) {
        guard id == prefetchGeneration else { return }
        prefetchTask = nil
        prefetchingPath = nil
        prefetch()
    }
}
