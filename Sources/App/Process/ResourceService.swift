import Foundation
import Observation
import os

/// Faz 3 kaynak geçmişinin sahibi: dakikalık arka plan örnekleyici, saatlik klasör taraması, canlı örnekleyici.
/// `AppModel.start()` yalnızca `start()` çağırır; UI `store` sorgularını ve `live`ı kullanır.
@MainActor @Observable
final class ResourceService {
    enum ScanOutcome: Equatable {
        case done(entries: Int)
        case skipped(reason: String)
        case busy
    }

    @ObservationIgnored let store: UsageStore
    @ObservationIgnored let live = LiveResourceSampler()
    private(set) var isScanning = false
    private(set) var lastScanDate: Date?
    /// Son otomatik taramanın atlanma nedeni (UI'da bilgi).
    private(set) var lastScanNote: String?

    @ObservationIgnored private var sampler: ResourceSampler?
    @ObservationIgnored private let writes = OSAllocatedUnfairLock(initialState: UInt64(0))
    @ObservationIgnored private var writesAtLastScan: UInt64 = 0
    @ObservationIgnored private var scanLoop: Task<Void, Never>?
    @ObservationIgnored private var started = false
    /// Kök başına son tarama zamanı (bellekte; açılışta son anlık görüntü tüm kökler için taranmış sayılır).
    @ObservationIgnored private var rootScannedAt: [String: Date] = [:]

    init(store: UsageStore) {
        self.store = store
    }

    /// Testlerde (uygulama host olarak açılır) zamanlayıcı kurulmaz.
    func start() {
        guard !started, !AppEnvironment.isRunningTests else { return }
        started = true
        let counter = writes
        let s = ResourceSampler(store: store, writeSink: { bytes in counter.withLock { $0 &+= bytes } })
        sampler = s
        s.start()
        scanLoop = Task { [weak self] in await self?.hourlyLoop() }
    }

    func stop() {
        sampler?.stop()
        scanLoop?.cancel()
        started = false
    }

    private func hourlyLoop() async {
        if let last = await store.lastFolderScan() {
            lastScanDate = Date(timeIntervalSince1970: TimeInterval(last))
            for r in FolderWatchList.roots() { rootScannedAt[r.path] = lastScanDate }
        }
        // İlk tarama açılıştan 2 dk sonra; yakın zamanda taranmışsa saatin dolmasını bekler.
        var wait: TimeInterval = 120
        if let last = lastScanDate { wait = max(120, last.addingTimeInterval(3_600).timeIntervalSinceNow) }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(wait), tolerance: .seconds(300))
            guard !Task.isCancelled else { return }
            _ = await scan(manual: false)
            wait = 3_600
        }
    }

    /// "Tara" düğmesi: pil / Düşük Güç / boşta denetimleri olmadan hemen tarar.
    @discardableResult
    func scanNow() async -> ScanOutcome { await scan(manual: true) }

    private func scan(manual: Bool) async -> ScanOutcome {
        guard !isScanning else { return .busy }
        if !manual {
            let power = PowerState.current()
            if let reason = ScanPolicy.skipReason(lowPowerMode: power.lowPowerMode, onBattery: power.onBattery,
                                                  batteryPercent: power.batteryPercent) {
                lastScanNote = "Saatlik tarama atlandı: \(reason)"
                return .skipped(reason: reason)
            }
            let total = writes.withLock { $0 }
            if let last = lastScanDate,
               ScanPolicy.canSkipAsIdle(bytesWrittenSinceScan: total &- writesAtLastScan, secondsSinceScan: -last.timeIntervalSinceNow) {
                lastScanNote = "Saatlik tarama atlandı: disk yazma etkinliği çok düşük"
                return .skipped(reason: "disk etkinliği düşük")
            }
        }
        isScanning = true
        defer { isScanning = false }
        let now = Date()
        let all = FolderWatchList.roots()
        // Seyrek kökler (everyHours > 1) vadesi gelmediyse atlanır, önceki değerleri anlık görüntüye taşınır.
        let due = manual ? all : all.filter { root in
            guard let last = rootScannedAt[root.path] else { return true }
            return now.timeIntervalSince(last) >= Double(root.everyHours) * 3_600 - 300
        }
        let skipped = all.filter { r in !due.contains(r) }
        var entries = await Task.detached(priority: .background) { Self.scanAll(due) }.value
        entries += await store.latestFolderEntries(underRoots: skipped.map { $0.path })
        await store.addFolderSnapshot(ts: Int(now.timeIntervalSince1970), entries: entries)
        for r in due { rootScannedAt[r.path] = now }
        lastScanDate = now
        lastScanNote = nil
        writesAtLastScan = writes.withLock { $0 }
        return .done(entries: entries.count)
    }

    /// Tüm kökleri tarar; G/Ç bu iş süresince kısılır (throttled) ve iş bitince iş parçacığının önceki ilkesi geri yüklenir
    /// (eş zamanlılık havuzundaki iş parçacığı sonraki işlere kısılmış G/Ç taşımasın). Kayıtlar yalnızca ≥ 10 MB alt klasörleri içerir.
    nonisolated static func scanAll(_ roots: [FolderScanRoot]) -> [FolderSnapshotEntry] {
        let previousPolicy = getiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_THREAD)
        _ = setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_THREAD, IOPOL_THROTTLE)
        defer { if previousPolicy >= 0 { _ = setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_THREAD, previousPolicy) } }
        var all: [FolderSnapshotEntry] = []
        for root in roots {
            guard !Task.isCancelled else { break }
            if let r = FolderScanner.scan(root: root, isCancelled: { Task.isCancelled }) { all.append(contentsOf: r.entries) }
        }
        return all
    }
}
