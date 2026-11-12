import Foundation

/// Kaldırma sonucu: öğe sonuçları + izin hatası alan yollar ve nedenleri.
struct AppRemovalReport: Sendable {
    var results: [CleanupResult]
    var accessFailures: [String: AccessReason]

    var removedPaths: Set<String> { Set(results.filter(\.isRemoved).map(\.candidate.path)) }
}

/// `trashItem` izin hatalarını (Cocoa 513/257, POSIX EPERM/EACCES; `NSUnderlyingErrorKey` dahil) yollarıyla kaydeder.
final class TrashPermissionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: Set<String> = []

    var all: Set<String> { lock.withLock { paths } }
    func add(_ path: String) { lock.withLock { _ = paths.insert(path) } }

    static func isPermissionError(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        while let ns = current {
            if ns.domain == NSCocoaErrorDomain, [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(ns.code) { return true }
            if ns.domain == NSPOSIXErrorDomain, [Int(EPERM), Int(EACCES)].contains(ns.code) { return true }
            current = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}

/// Kaldırma düzeni: önce uygulama paketi, ancak kaldırılırsa artıklar; LaunchAgent plist'i `StartupItemActions.remove` ile
/// (önce bootout). Tüm öğeler `CleanupDeleter` ile silme anında yeniden doğrulanır (çalışan uygulamalar o an okunur).
struct AppRemover: Sendable {
    typealias LaunchAgentRemoval = @Sendable (DeletionCandidate) async -> StartupItemActions.Outcome

    var home: String
    var runningBundleIDs: @Sendable () -> Set<String> = CleanupDeleter.liveRunningBundleIDs
    var logURL: URL = CleanupAuditLog.defaultURL
    var ownPaths: [String]?
    var trash: @Sendable (URL) throws -> URL? = CleanupDeleter.systemTrash
    var remove: @Sendable (URL) throws -> Void = CleanupDeleter.systemRemove
    var launchAgentRemoval: LaunchAgentRemoval?

    static func liveLaunchAgentRemoval(home: String) -> LaunchAgentRemoval {
        { candidate in
            guard let item = StartupItemScanner.parse(url: URL(filePath: candidate.path), scope: .user) else {
                return .failed("Plist okunamadı")
            }
            return await StartupItemActions(home: URL(filePath: home, directoryHint: .isDirectory)).remove(item)
        }
    }

    func deleter(permissionLog: TrashPermissionLog) -> CleanupDeleter {
        let base = trash
        return CleanupDeleter(home: home, runningBundleIDs: runningBundleIDs, logURL: logURL, ownPaths: ownPaths,
                              moveToTrash: { url in
                                  do { return try base(url) } catch {
                                      if TrashPermissionLog.isPermissionError(error) { permissionLog.add(url.path) }
                                      throw error
                                  }
                              },
                              removePermanently: remove)
    }

    /// - Parameters:
    ///   - app: bundle de kaldırılacaksa uygulama (yalnız artıklar için nil).
    ///   - leftovers: silinecek artıklar / yetim girdiler.
    func run(app: InstalledApp?, leftovers: [DeletionCandidate], mode: DeleteMode) async -> AppRemovalReport {
        let permissionLog = TrashPermissionLog()
        let deleter = deleter(permissionLog: permissionLog)
        var results: [CleanupResult] = []
        var bundleFailed = false

        if let app {
            if let block = app.removalBlock {
                results.append(CleanupResult(candidate: app.bundleCandidate, outcome: .failed(block.note)))
                bundleFailed = true
            } else {
                let outcome = deleter.delete([app.bundleCandidate], mode: mode)
                results += outcome
                bundleFailed = !(outcome.first?.isRemoved ?? false)
            }
        }

        if bundleFailed {
            for candidate in leftovers {
                results.append(CleanupResult(candidate: candidate, outcome: .failed("Uygulama kaldırılamadığı için dokunulmadı")))
            }
        } else {
            let agents = leftovers.filter { $0.kind == LeftoverLocation.launchAgents.kind }
            let others = leftovers.filter { $0.kind != LeftoverLocation.launchAgents.kind }
            results += deleter.delete(others, mode: mode)
            results += await removeLaunchAgents(agents, deleter: deleter)
        }

        var failures: [String: AccessReason] = [:]
        for path in permissionLog.all { failures[path] = CleanupAccess.reason(for: path, home: home) }
        return AppRemovalReport(results: results, accessFailures: failures)
    }

    /// LaunchAgent plist'leri: `StartupItemActions.remove` kayıt dışı silmez ve kimlik denetimi yapmaz, bu yüzden önce deleter ile
    /// doğrulanır. `remove` her zaman Çöp'e taşır (kalıcı modda bile); günlüğe `.trash` olarak yazılır.
    private func removeLaunchAgents(_ agents: [DeletionCandidate], deleter: CleanupDeleter) async -> [CleanupResult] {
        guard !agents.isEmpty else { return [] }
        let running = runningBundleIDs()
        var results: [CleanupResult] = []
        var logged: [CleanupResult] = []
        for candidate in agents {
            if let refusal = deleter.validate(candidate, running: running) {
                let skipped = CleanupResult(candidate: candidate, outcome: .skipped(refusal))
                results.append(skipped)
                logged.append(skipped)
                continue
            }
            guard let launchAgentRemoval else {
                results.append(CleanupResult(candidate: candidate, outcome: .failed("LaunchAgent kaldırıcı yok")))
                continue
            }
            let result: CleanupResult
            switch await launchAgentRemoval(candidate) {
            case .success: result = CleanupResult(candidate: candidate, outcome: .trashed(to: nil))
            case .denied(let message), .failed(let message): result = CleanupResult(candidate: candidate, outcome: .failed(message))
            }
            results.append(result)
            logged.append(result)
        }
        CleanupAuditLog.append(logged, mode: .trash, url: logURL)
        return results
    }
}
