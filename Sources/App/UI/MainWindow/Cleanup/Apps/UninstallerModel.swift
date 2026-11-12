import AppKit
import SwiftUI

/// Onay penceresinde özetlenen, silinecek öğeler (onay açıkken seçim değişse bile yalnız bunlar silinir).
struct PendingRemoval: Equatable {
    var app: InstalledApp?
    var leftovers: [DeletionCandidate]

    var candidates: [DeletionCandidate] { (app.map { [$0.bundleCandidate] } ?? []) + leftovers }
    var bytes: UInt64 { candidates.reduce(0) { $0 + $1.bytes } }
}

/// Kaldırıcı: yalnızca kullanıcı "Tara"ya basınca tarar (zamanlayıcı yok), `.utility` önceliğinde ve iptal edilebilir.
@MainActor @Observable
final class UninstallerModel {
    enum Phase: Equatable { case idle, scanning(done: Int, total: Int), deleting }
    enum Tab: String, CaseIterable, Identifiable {
        case apps, orphans
        var id: String { rawValue }
        var title: String { self == .apps ? "Uygulamalar" : "Yetim dosyalar" }
    }
    enum Sort: String, CaseIterable, Identifiable {
        case size, leftovers, name
        var id: String { rawValue }
        var title: String {
            switch self {
            case .size: "Boyut"
            case .leftovers: "Artık"
            case .name: "Ad"
            }
        }
    }

    let home: String
    var tab: Tab = .apps
    private(set) var phase: Phase = .idle
    private(set) var hasScanned = false
    private(set) var apps: [InstalledApp] = []
    private(set) var orphans: [OrphanGroup] = []
    var search = ""
    var sort: Sort = .size
    private(set) var selectedAppID: String?
    var leftoverSelection: Set<String> = []
    var includeBundle = true
    var orphanSelection: Set<String> = []
    /// Yalnızca sonraki işlem için; işlem bitince `.trash`a döner.
    var deleteMode: DeleteMode = .trash
    private(set) var report: AppRemovalReport?
    private(set) var lastMode: DeleteMode = .trash
    private(set) var runningIDs: Set<String> = []
    var accessIssue: AccessReason?
    let access: CleanupAccessMonitor
    @ObservationIgnored var remover: AppRemover
    @ObservationIgnored var runningProvider: @Sendable () -> Set<String> = CleanupDeleter.liveRunningBundleIDs
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init(home: String = NSHomeDirectory(), probe: PathProbe = .live, remover: AppRemover? = nil) {
        self.home = home
        access = CleanupAccessMonitor(home: home, probe: probe)
        self.remover = remover ?? AppRemover(home: home, launchAgentRemoval: AppRemover.liveLaunchAgentRemoval(home: home))
    }

    var isBusy: Bool { phase != .idle }

    // MARK: Liste

    var visibleApps: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query)
        }
        switch sort {
        case .size: return filtered.sorted { $0.bytes > $1.bytes }
        case .leftovers: return filtered.sorted { $0.leftoverBytes > $1.leftoverBytes }
        case .name: return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    var visibleOrphans: [OrphanGroup] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? orphans : orphans.filter { $0.bundleID.localizedCaseInsensitiveContains(query) }
    }

    var selectedApp: InstalledApp? { apps.first { $0.id == selectedAppID } }

    func isRunning(_ app: InstalledApp) -> Bool { runningIDs.contains(app.bundleID) }

    func refreshRunning() { runningIDs = runningProvider() }

    func select(_ app: InstalledApp?) {
        selectedAppID = app?.id
        // Ada göre eşleşen artıklar (Application Support/<ad>, Logs/<ad>) varsayılan seçili gelmez; yalnız bundle kimliğiyle tam eşleşenler.
        leftoverSelection = Set(app.map { app in app.leftovers.filter { !LeftoverRules.isNameMatch($0, app: app.identity) }.map(\.path) } ?? [])
        includeBundle = app?.removalBlock == nil
        refreshRunning()
    }

    // MARK: Silinecekler

    /// Uygulamalar sekmesinde: seçili uygulama (paket dahil ya da yalnız artıklar).
    var appsPending: PendingRemoval? {
        guard let app = selectedApp else { return nil }
        let bundle = includeBundle && app.removalBlock == nil ? app : nil
        let chosen = app.leftovers.filter { leftoverSelection.contains($0.path) }
        let pending = PendingRemoval(app: bundle, leftovers: chosen)
        return pending.candidates.isEmpty ? nil : pending
    }

    var orphansPending: PendingRemoval? {
        let chosen = orphans.flatMap(\.items).filter { orphanSelection.contains($0.path) }
        return chosen.isEmpty ? nil : PendingRemoval(app: nil, leftovers: chosen)
    }

    var pending: PendingRemoval? { tab == .apps ? appsPending : orphansPending }

    /// Seçili uygulama çalışıyorsa kaldırma düğmesi kapalıdır (silme anında tekrar kontrol edilir).
    var selectedAppRunning: Bool { tab == .apps && (selectedApp.map(isRunning) ?? false) }

    func setGroup(_ group: OrphanGroup, selected: Bool) {
        let paths = group.items.map(\.path)
        if selected { orphanSelection.formUnion(paths) } else { orphanSelection.subtract(paths) }
    }

    // MARK: Tarama

    func scan() {
        guard !isBusy else { return }
        refreshRunning()
        let running = runningIDs
        let home = home
        phase = .scanning(done: 0, total: 0)
        report = nil
        scanTask = Task.detached(priority: .utility) { [weak self] in
            let out = InstalledAppScanner.scan(home: home, running: running, isCancelled: { Task.isCancelled },
                                               progress: { done, total in
                                                   Task { @MainActor [weak self] in
                                                       if case .scanning = self?.phase { self?.phase = .scanning(done: done, total: total) }
                                                   }
                                               })
            let cancelled = Task.isCancelled
            await MainActor.run { [weak self] in
                guard let self else { return }
                if cancelled { phase = .idle } else { apply(out) }
                scanTask = nil
            }
        }
    }

    /// Yalnızca önizleme / test: tarama ekranını verilen ilerlemeyle gösterir (gerçek tarama başlatmaz).
    func showScanningForPreview(done: Int, total: Int) {
        phase = .scanning(done: done, total: total)
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        if case .scanning = phase { phase = .idle }
    }

    /// Tarama sonucunu uygular. Yetimler hiçbir zaman varsayılan seçili değildir.
    func apply(_ output: AppScanOutput) {
        apps = output.apps
        orphans = output.orphans
        orphanSelection = []
        hasScanned = true
        phase = .idle
        select(apps.first { $0.id == selectedAppID } ?? visibleApps.first)
    }

    // MARK: Silme

    /// Onaydan sonra çağrılır. Yöntem onay anında alınır; işlem bitince `deleteMode` Çöp'e döner.
    func remove(_ pending: PendingRemoval, mode: DeleteMode) {
        guard !isBusy, !pending.candidates.isEmpty else {
            deleteMode = .trash
            return
        }
        phase = .deleting
        let remover = remover
        Task.detached(priority: .utility) { [weak self] in
            let report = await remover.run(app: pending.app, leftovers: pending.leftovers, mode: mode)
            await MainActor.run { [weak self] in self?.finish(report, pending: pending, mode: mode) }
        }
    }

    func finish(_ report: AppRemovalReport, pending: PendingRemoval, mode: DeleteMode) {
        let removed = report.removedPaths
        if let app = pending.app, removed.contains(app.path) {
            apps.removeAll { $0.id == app.id }
            if selectedAppID == app.id { select(visibleApps.first) }
        }
        for i in apps.indices {
            apps[i].leftovers.removeAll { removed.contains($0.path) }
        }
        leftoverSelection.subtract(removed)
        orphanSelection.subtract(removed)
        orphans = orphans.compactMap { group in
            var copy = group
            copy.items.removeAll { removed.contains($0.path) }
            return copy.items.isEmpty ? nil : copy
        }
        self.report = report
        lastMode = mode
        deleteMode = .trash
        accessIssue = Self.mainIssue(report.accessFailures)
        phase = .idle
    }

    /// Birden çok nedenden en bilgilendirici olanı (Uygulama Yönetimi önce).
    nonisolated static func mainIssue(_ failures: [String: AccessReason]) -> AccessReason? {
        let reasons = Set(failures.values)
        if reasons.contains(.appManagement) { return .appManagement }
        return reasons.sorted { $0.title < $1.title }.first
    }

    func dismissReport() {
        report = nil
        accessIssue = nil
    }
}
