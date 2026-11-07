import CryptoKit
import Foundation

/// Ekran koruyucu paketinin (`AdalmonSaver.saver`) kurulumu: uygulamanın içindeki kopya -> `~/Library/Screen Savers/`
/// (kullanıcı düzeyi, yönetici gerekmez). `embeddedURL` ve `installDirectory` enjekte edilir: testler yalnızca geçici dizinde çalışır,
/// gerçek `~/Library/Screen Savers` testte ASLA kullanılmaz.
struct SaverInstaller: Sendable {
    /// Paket kimliği: sürüm numarası + çalıştırılabilir dosya özeti. (Sürüm numarası aynı kalsa bile kod değişince fark eder.)
    struct Fingerprint: Equatable, Sendable {
        var identifier: String
        var version: String
        var executableDigest: String

        var display: String { version }
    }

    enum Status: Equatable, Sendable {
        /// Uygulama paketinin içinde ekran koruyucu yok (bozuk derleme).
        case unavailable
        case notInstalled
        case installed(Fingerprint)
        /// Kurulu kopya uygulamadakinden farklı (sürüm ya da kod).
        case updateNeeded(installed: Fingerprint, available: Fingerprint)
        /// Aynı adlı, bize ait olmayan bir paket yolda; dokunmayız.
        case foreign
    }

    enum InstallError: LocalizedError, Equatable {
        case embeddedMissing, foreignBundle
        var errorDescription: String? {
            switch self {
            case .embeddedMissing: "Uygulamanın içinde ekran koruyucu paketi bulunamadı."
            case .foreignBundle: "~/Library/Screen Savers içinde aynı adlı başka bir paket var; üzerine yazılmadı."
            }
        }
    }

    var embeddedURL: URL?
    var installDirectory: URL

    static var defaultInstallDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Screen Savers", directoryHint: .isDirectory)
    }

    static var defaultEmbeddedURL: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Library/Screen Savers/\(SaverPaths.bundleName)", directoryHint: .isDirectory)
    }

    init(embeddedURL: URL? = Self.defaultEmbeddedURL, installDirectory: URL = Self.defaultInstallDirectory) {
        self.embeddedURL = embeddedURL
        self.installDirectory = installDirectory
    }

    var installedURL: URL { installDirectory.appending(path: SaverPaths.bundleName, directoryHint: .isDirectory) }

    // MARK: Durum

    func status() -> Status {
        guard let embedded = embeddedURL.flatMap(Self.fingerprint), embedded.identifier == SaverPaths.bundleIdentifier else { return .unavailable }
        guard FileManager.default.fileExists(atPath: installedURL.path) else { return .notInstalled }
        guard let installed = Self.fingerprint(of: installedURL), installed.identifier == SaverPaths.bundleIdentifier else { return .foreign }
        return installed == embedded ? .installed(installed) : .updateNeeded(installed: installed, available: embedded)
    }

    static func fingerprint(of bundle: URL) -> Fingerprint? {
        guard let info = NSDictionary(contentsOf: bundle.appending(path: "Contents/Info.plist")) as? [String: Any],
              let identifier = info["CFBundleIdentifier"] as? String else { return nil }
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let exeName = info["CFBundleExecutable"] as? String ?? ""
        let exe = bundle.appending(path: "Contents/MacOS/\(exeName)")
        let digest = (try? Data(contentsOf: exe, options: .mappedIfSafe)).map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? ""
        return Fingerprint(identifier: identifier, version: "\(short) (\(build))", executableDigest: digest)
    }

    // MARK: Kur / kaldır

    /// Kurar ya da günceller. Önce geçici bir kardeş dizine kopyalar, sonra atomik değiştirir (yarım paket kalmaz).
    func install() throws {
        guard let embeddedURL, case .some = Self.fingerprint(of: embeddedURL) else { throw InstallError.embeddedMissing }
        let fm = FileManager.default
        if fm.fileExists(atPath: installedURL.path), Self.fingerprint(of: installedURL)?.identifier != SaverPaths.bundleIdentifier {
            throw InstallError.foreignBundle
        }
        try fm.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        let temp = installDirectory.appending(path: ".AdalmonSaver-\(UUID().uuidString).tmp", directoryHint: .isDirectory)
        try fm.copyItem(at: embeddedURL, to: temp)
        do {
            if fm.fileExists(atPath: installedURL.path) {
                _ = try fm.replaceItemAt(installedURL, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: installedURL)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    /// Yalnızca bize ait paketi siler. Dönüş: bir şey silindi mi.
    @discardableResult
    func uninstall() throws -> Bool {
        guard FileManager.default.fileExists(atPath: installedURL.path) else { return false }
        guard Self.fingerprint(of: installedURL)?.identifier == SaverPaths.bundleIdentifier else { throw InstallError.foreignBundle }
        try FileManager.default.removeItem(at: installedURL)
        return true
    }
}
