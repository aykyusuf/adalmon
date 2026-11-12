import AppKit
import Foundation

/// Bir tarayıcı için onay bekleyen silme: onay penceresinde gösterilen dosyaların kendisi (onay açıkken yeniden tarama bunları değiştirmez).
struct PendingPrivacyDeletion: Equatable, Identifiable {
    var id: String { browser.rawValue }
    let browser: PrivacyBrowser
    let kinds: Set<PrivacyDataKind>
    let candidates: [DeletionCandidate]

    var bytes: UInt64 { candidates.reduce(0) { $0 + $1.bytes } }
}

/// Gizlilik bölümü: yalnızca istek üzerine tarar (zamanlayıcı yok), Çöp varsayılan, kalıcı silme işlem başına.
@MainActor @Observable
final class BrowserPrivacyViewModel {
    enum Phase: Equatable { case idle, scanning, deleting }

    let home: String
    let access: CleanupAccessMonitor
    private(set) var scans: [PrivacyBrowser: BrowserPrivacyScan] = [:]
    /// Tarayıcı başına seçili veri türleri.
    var selection: [PrivacyBrowser: Set<PrivacyDataKind>] = [:]
    private(set) var phase: Phase = .idle
    private(set) var hasScanned = false
    private(set) var lastResult: [CleanupResult]?
    private(set) var lastMode: DeleteMode = .trash
    /// Yalnızca sonraki işlem için; işlem bitince `.trash`a döner.
    var deleteMode: DeleteMode = .trash
    @ObservationIgnored private let runningBundleIDs: @Sendable () -> Set<String>
    @ObservationIgnored private let makeDeleter: @Sendable () -> CleanupDeleter
    @ObservationIgnored private let probe: PathProbe
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init(home: String = NSHomeDirectory(), probe: PathProbe = .live,
         runningBundleIDs: @escaping @Sendable () -> Set<String> = CleanupDeleter.liveRunningBundleIDs,
         makeDeleter: (@Sendable () -> CleanupDeleter)? = nil) {
        self.home = home
        self.probe = probe
        self.runningBundleIDs = runningBundleIDs
        self.makeDeleter = makeDeleter ?? { CleanupDeleter(home: home, runningBundleIDs: runningBundleIDs) }
        access = CleanupAccessMonitor(home: home, probe: probe)
        access.onUnblocked = { [weak self] _ in self?.scan() }
    }

    var isBusy: Bool { phase != .idle }

    func scan(for browser: PrivacyBrowser) -> BrowserPrivacyScan? { scans[browser] }

    func selected(_ browser: PrivacyBrowser) -> Set<PrivacyDataKind> { selection[browser] ?? [] }

    func toggle(_ kind: PrivacyDataKind, in browser: PrivacyBrowser) {
        var set = selected(browser)
        if set.contains(kind) { set.remove(kind) } else { set.insert(kind) }
        selection[browser] = set
    }

    /// Seçili türlerin toplam boyutu ve dosya sayısı.
    func selectedTotals(_ browser: PrivacyBrowser) -> (count: Int, bytes: UInt64) {
        guard let scan = scans[browser], scan.state == .scanned else { return (0, 0) }
        let files = scan.files.filter { selected(browser).contains($0.kind) }
        return (files.count, files.reduce(0) { $0 + $1.bytes })
    }

    // MARK: Tarama

    /// Tüm tarayıcıları tarar (arka planda, düşük öncelik). Açık tarayıcılar `.running` olur.
    func scan() {
        guard !isBusy else { return }
        phase = .scanning
        let home = home, probe = probe, running = runningBundleIDs()
        scanTask = Task.detached(priority: .utility) { [weak self] in
            let out = BrowserPrivacyRules.scanAll(home: home, running: running, probe: probe, isCancelled: { Task.isCancelled })
            let cancelled = Task.isCancelled
            await self?.apply(out, cancelled: cancelled)
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        if phase == .scanning { phase = .idle }
    }

    func apply(_ out: [BrowserPrivacyScan], cancelled: Bool = false) {
        guard !cancelled else { return }
        for scan in out {
            // Önceki engel kalktıysa erişim izleyicisinden çıkar; yeni engel varsa izle (yeniden denemeyi izleyici yapar).
            let oldBlocked = scans[scan.browser]?.blockedPath
            if let oldBlocked, oldBlocked != scan.blockedPath { access.setBlocked(oldBlocked, false) }
            if let blocked = scan.blockedPath { access.setBlocked(blocked, true) }
            scans[scan.browser] = scan
            // Seçim: yalnızca bulunan türler; yeni taramada eski seçimin geçerli kısmı korunur.
            selection[scan.browser] = selected(scan.browser).intersection(Set(PrivacyDataKind.allCases.filter { scan.has($0) }))
        }
        hasScanned = true
        phase = .idle
        scanTask = nil
    }

    // MARK: Silme

    /// Silme düğmesine basıldı: açık tarayıcı o an yeniden okunur; açıksa durum `.running`a çekilir ve nil döner.
    func requestDeletion(of browser: PrivacyBrowser) -> PendingPrivacyDeletion? {
        guard !isBusy, var scan = scans[browser] else { return nil }
        let running = runningBundleIDs()
        if running.contains(browser.bundleID) {
            scan.state = .running
            scan.files = []
            scans[browser] = scan
            return nil
        }
        let kinds = selected(browser)
        let candidates = BrowserPrivacyRules.candidates(for: scan, kinds: kinds, running: running)
        guard !candidates.isEmpty else { return nil }
        return PendingPrivacyDeletion(browser: browser, kinds: kinds, candidates: candidates)
    }

    /// Onaydan sonra. Yöntem onayda alınır; her aday silme anında `CleanupDeleter` ile yeniden doğrulanır (açık tarayıcı reddedilir).
    func perform(_ pending: PendingPrivacyDeletion, mode: DeleteMode) {
        guard !isBusy else {
            deleteMode = .trash
            return
        }
        phase = .deleting
        lastResult = nil
        let deleter = makeDeleter()
        let candidates = pending.candidates
        Task.detached(priority: .utility) { [weak self] in
            let results = deleter.delete(candidates, mode: mode)
            await self?.finish(results, mode: mode)
        }
    }

    private func finish(_ results: [CleanupResult], mode: DeleteMode) {
        lastResult = results
        lastMode = mode
        deleteMode = .trash
        phase = .idle
        scan()
    }

    func resetMode() { deleteMode = .trash }
}
