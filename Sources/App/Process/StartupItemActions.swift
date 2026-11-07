import Foundation

/// Kullanıcı LaunchAgent'larını devre dışı bırakma / etkinleştirme / kaldırma. Tüm yetki denetimleri burada yapılır;
/// çalıştırıcı ve Çöp Kutusu soyutlamaları enjekte edilir (testte sahte).
struct StartupItemActions: Sendable {
    enum Outcome: Equatable, Sendable {
        case success
        case denied(String)
        case failed(String)
    }

    var launchctl: any LaunchctlRunning = SystemLaunchctl()
    var trasher: any FileTrashing = WorkspaceTrasher()
    var uid: uid_t = getuid()
    var home: URL = FileManager.default.homeDirectoryForCurrentUser

    /// Durdurur (bootout) ve yeniden oturum açmada da kapalı kalması için `disable` yazar.
    func disable(_ item: StartupItem) async -> Outcome {
        if let denied = gate(item) { return denied }
        let domain = LaunchctlDomain.gui(uid: uid)
        _ = await launchctl.run(.bootout(domain, label: item.label)) // yüklü değilse hata verir; sorun değil
        let result = await launchctl.run(.disable(domain, label: item.label))
        return result.succeeded ? .success : .failed(Self.message(result))
    }

    /// Geri alma: `enable` + `bootstrap` (zaten yüklüyse bootstrap hatası yok sayılır).
    func enable(_ item: StartupItem) async -> Outcome {
        if let denied = gate(item) { return denied }
        let domain = LaunchctlDomain.gui(uid: uid)
        let result = await launchctl.run(.enable(domain, label: item.label))
        guard result.succeeded else { return .failed(Self.message(result)) }
        _ = await launchctl.run(.bootstrap(domain, plistPath: item.plistPath))
        return .success
    }

    /// Durdurur ve plist'i Çöp Kutusu'na taşır (Çöp Kutusu'ndan geri konabilir).
    func remove(_ item: StartupItem) async -> Outcome {
        if let denied = gate(item) { return denied }
        guard Self.isInUserLaunchAgents(path: item.plistPath, home: home) else {
            return .denied(StartupItemPermissions.adminReason)
        }
        _ = await launchctl.run(.bootout(.gui(uid: uid), label: item.label))
        do {
            try await trasher.trash(URL(filePath: item.plistPath))
            return .success
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func gate(_ item: StartupItem) -> Outcome? {
        let permissions = StartupItemPermissions.evaluate(item)
        return permissions.canModify ? nil : .denied(permissions.reason ?? StartupItemPermissions.adminReason)
    }

    /// `~/Library/LaunchAgents` içindeki (alt klasörsüz, `..`siz) bir dosya mı?
    static func isInUserLaunchAgents(path: String, home: URL) -> Bool {
        let dir = home.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory).standardizedFileURL.path
        let url = URL(filePath: path).standardizedFileURL
        return url.deletingLastPathComponent().path == dir && url.pathExtension == "plist"
    }

    private static func message(_ result: CommandResult) -> String {
        let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "launchctl \(result.status) koduyla bitti" : text
    }
}
