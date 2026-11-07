import CryptoKit
import Foundation

/// Kurulu kayıtların durumu (Adalmon tarafında saklanır).
struct AerialInstallState: Codable, Equatable, Sendable {
    var assetIDs: [String]
    /// Yazdığımız entries.json'ın SHA-256'sı: Apple dosyayı yenilemediyse yedeği birebir geri yükleriz.
    var writtenSHA256: String
    var backupFile: String
    var installedAt: Date
    var osVersion: String
    var copiedFiles: [String]
}

enum AerialCompatibility: Equatable, Sendable {
    /// Güvenle yazılabilir görünüyor.
    case supported
    /// Yazılabilir ama uyarı gösterilmeli (macOS 27: Apple biçimi değiştirdi).
    case warning(String)
    /// Yazma. Sebep kullanıcıya gösterilir.
    case unsupported(String)

    var canInstall: Bool { if case .unsupported = self { false } else { true } }
    var message: String? {
        switch self {
        case .supported: nil
        case .warning(let m), .unsupported(let m): m
        }
    }
}

enum AerialStatus: Equatable, Sendable {
    case notInstalled
    case installed(count: Int)
    /// Kayıt durumumuz var ama manifest'te yok: Apple dosyayı yenilemiş.
    case drifted
}

/// Aerial kurulumu. `root` ve `supportDirectory` enjekte edilir: testler yalnızca geçici kopya üzerinde çalışır,
/// gerçek `~/Library/Application Support/com.apple.wallpaper` testte ASLA kullanılmaz.
struct AerialInstaller: Sendable {
    var root: URL
    var supportDirectory: URL
    var osMajor: Int
    var osVersionString: String

    static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/com.apple.wallpaper/aerials", directoryHint: .isDirectory)

    init(root: URL = Self.defaultRoot, supportDirectory: URL, osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) {
        self.root = root
        self.supportDirectory = supportDirectory
        osMajor = osVersion.majorVersion
        osVersionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
    }

    var manifestURL: URL { root.appending(path: "manifest/entries.json") }
    var videosDirectory: URL { root.appending(path: "videos", directoryHint: .isDirectory) }
    var thumbnailsDirectory: URL { root.appending(path: "thumbnails", directoryHint: .isDirectory) }
    var backupDirectory: URL { supportDirectory.appending(path: "AerialBackup", directoryHint: .isDirectory) }
    var stateURL: URL { supportDirectory.appending(path: "aerial-install.json") }

    // MARK: Uyumluluk

    func compatibility() -> AerialCompatibility {
        guard (26...27).contains(osMajor) else {
            return .unsupported("macOS \(osVersionString) için Aerial biçimi doğrulanmadı. Hiçbir şey yazılmayacak.")
        }
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: manifestURL), let root = try? AerialManifest.parse(data) else {
            return .unsupported("Sistem Aerial listesi bulunamadı ya da okunamadı. Önce Sistem Ayarları > Duvar Kâğıdı'nda bir Aerial indirin.")
        }
        let problems = AerialManifest.problems(in: root)
        guard problems.isEmpty else {
            return .unsupported("Apple biçimi değişmiş görünüyor (\(problems.joined(separator: "; "))). Hiçbir şey yazılmayacak.")
        }
        guard fm.isWritableFile(atPath: manifestURL.path), fm.fileExists(atPath: videosDirectory.path), fm.fileExists(atPath: thumbnailsDirectory.path) else {
            return .unsupported("Aerial klasörlerine yazılamıyor.")
        }
        if osMajor >= 27 {
            return .warning("macOS 27'de Apple kurulum biçimini değiştirdi (Wallper 1.9.0 notu): kayıt listede görünebilir ama kilit ekranında oynamayabilir. Deneyseldir.")
        }
        return .supported
    }

    func status() -> AerialStatus {
        guard let state = loadState() else { return .notInstalled }
        guard let data = try? Data(contentsOf: manifestURL), let root = try? AerialManifest.parse(data) else { return .drifted }
        let present = Set(AerialManifest.ourAssetIDs(in: root))
        return Set(state.assetIDs).isSubset(of: present) && !present.isEmpty ? .installed(count: present.count) : .drifted
    }

    // MARK: Kurulum

    struct Item: Sendable {
        var name: String
        var videoFile: URL
        var thumbnailFile: URL
    }

    /// Videoları + küçük resimleri Aerial klasörlerine kopyalar ve manifest'e ekler. Yedek alır, atomik yazar.
    @discardableResult
    func install(_ items: [Item], now: Date = .now) throws -> AerialInstallState {
        let compat = compatibility()
        if case .unsupported(let why) = compat { throw AerialManifest.ManifestError.unsupported(why) }
        guard !items.isEmpty else { throw AerialManifest.ManifestError.unsupported("Eklenecek video yok.") }
        let fm = FileManager.default
        // Önceki kurulumumuz varsa önce temiz geri al: yedek hiçbir zaman eski kayıtlarımızı içermesin.
        if loadState() != nil { try uninstall() }
        let originalData = try Data(contentsOf: manifestURL)
        let original = try AerialManifest.parse(originalData)

        // 1) Yedek: ilk hiç değişmemiş kopya bir kez; her kurulumdan önce zaman damgalı kopya.
        try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let pristine = backupDirectory.appending(path: "entries.original.json")
        if !fm.fileExists(atPath: pristine.path), AerialManifest.ourAssetIDs(in: original).isEmpty {
            try originalData.write(to: pristine, options: .atomic)
        }
        let stamp = Int(now.timeIntervalSince1970)
        let backup = backupDirectory.appending(path: "entries-\(stamp).json")
        try originalData.write(to: backup, options: .atomic)

        // 2) Dosyaları kopyala (hata olursa geri sil).
        var copied: [URL] = []
        var entries: [AerialManifest.Entry] = []
        do {
            for item in items {
                let id = AerialManifest.newAssetID()
                let video = videosDirectory.appending(path: "\(id).mov")
                let thumb = thumbnailsDirectory.appending(path: "\(id).png")
                try fm.copyItem(at: item.videoFile, to: video); copied.append(video)
                try fm.copyItem(at: item.thumbnailFile, to: thumb); copied.append(thumb)
                entries.append(.init(assetID: id, name: item.name, videoURL: video, thumbnailURL: thumb))
            }
            // 3) Manifest: değişmezler doğrulanmadan yazılmaz; yazıdan sonra yeniden okunup doğrulanır.
            let modified = try AerialManifest.inserting(entries, into: original)
            let data = try AerialManifest.serialize(modified)
            guard (try? AerialManifest.parse(data)) != nil else { throw AerialManifest.ManifestError.invariantViolated("Üretilen JSON geçersiz.") }
            try data.write(to: manifestURL, options: .atomic)
            let state = AerialInstallState(assetIDs: entries.map(\.assetID), writtenSHA256: Self.sha256(data), backupFile: backup.lastPathComponent,
                                           installedAt: now, osVersion: osVersionString, copiedFiles: copied.map(\.path))
            try saveState(state)
            return state
        } catch {
            for url in copied { try? fm.removeItem(at: url) }
            throw error
        }
    }

    // MARK: Geri alma

    enum UninstallMethod: Equatable, Sendable { case restoredBackup, removedOurEntries, nothingToDo }

    /// "Geri al": manifest hâlâ yazdığımızla birebir aynıysa yedek aynen geri yüklenir; Apple dosyayı yenilemişse yalnızca
    /// bizim kayıtlarımız çıkarılır (Apple'ınkilere dokunulmaz). Kopyaladığımız video / küçük resimler silinir.
    @discardableResult
    func uninstall() throws -> UninstallMethod {
        let fm = FileManager.default
        guard let state = loadState() else {
            // Durum dosyası yoksa bile manifest'te önekli kayıt varsa çıkar.
            guard let data = try? Data(contentsOf: manifestURL), let root = try? AerialManifest.parse(data),
                  !AerialManifest.ourAssetIDs(in: root).isEmpty else { return .nothingToDo }
            try writeRemoving(from: root)
            return .removedOurEntries
        }
        var method = UninstallMethod.removedOurEntries
        let currentData = try? Data(contentsOf: manifestURL)
        let backupURL = backupDirectory.appending(path: state.backupFile)
        if let currentData, Self.sha256(currentData) == state.writtenSHA256, let backupData = try? Data(contentsOf: backupURL),
           (try? AerialManifest.parse(backupData)) != nil {
            try backupData.write(to: manifestURL, options: .atomic)
            method = .restoredBackup
        } else if let currentData, let root = try? AerialManifest.parse(currentData) {
            try writeRemoving(from: root)
        } else if let backupData = try? Data(contentsOf: backupURL), (try? AerialManifest.parse(backupData)) != nil {
            // Mevcut manifest okunamıyor: bozuk dosya yerine yedek.
            try backupData.write(to: manifestURL, options: .atomic)
            method = .restoredBackup
        }
        for path in state.copiedFiles { try? fm.removeItem(atPath: path) }
        // Asset kimliğinden türeyen dosyalar (durum dosyası eksik kopya listesiyle) için de süpür.
        for dir in [videosDirectory, thumbnailsDirectory] {
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasPrefix(AerialManifest.idPrefix) {
                try? fm.removeItem(at: dir.appending(path: name))
            }
        }
        try? fm.removeItem(at: stateURL)
        return method
    }

    private func writeRemoving(from root: [String: Any]) throws {
        let cleaned = AerialManifest.removing(from: root)
        try AerialManifest.verifyApplePreserved(original: root, modified: cleaned)
        try AerialManifest.serialize(cleaned).write(to: manifestURL, options: .atomic)
    }

    // MARK: Durum dosyası

    func loadState() -> AerialInstallState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(AerialInstallState.self, from: data)
    }

    private func saveState(_ state: AerialInstallState) throws {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try enc.encode(state).write(to: stateURL, options: .atomic)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Wallpaper ajanını yeniden başlatma: yalnızca kullanıcı onayıyla, uygulama tarafından çağrılır (testte/geliştirmede ASLA).
enum WallpaperAgentRestarter {
    /// `killall WallpaperAgent` (launchd yeniden doğurur). Süreç adı macOS 27.2'de doğrulandı: `WallpaperAgent` (pgrep).
    static func restart() throws {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/killall")
        p.arguments = ["WallpaperAgent"]
        try p.run()
        p.waitUntilExit()
    }
}
