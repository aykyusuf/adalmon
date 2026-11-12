import Darwin
import Foundation

/// Gizlilik temizliğinin desteklediği tarayıcılar (yalnızca bunlar).
enum PrivacyBrowser: String, CaseIterable, Sendable, Identifiable {
    case chrome, edge, safari

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chrome: "Google Chrome"
        case .edge: "Microsoft Edge"
        case .safari: "Safari"
        }
    }

    /// Kısa ad (cümle içinde).
    var shortName: String {
        switch self {
        case .chrome: "Chrome"
        case .edge: "Edge"
        case .safari: "Safari"
        }
    }

    /// "-i hâli" (Türkçe belirtme durumu): "Önce Chrome'u kapatın".
    var accusative: String {
        switch self {
        case .chrome: "Chrome'u"
        case .edge: "Edge'i"
        case .safari: "Safari'yi"
        }
    }

    var bundleID: String {
        switch self {
        case .chrome: "com.google.Chrome"
        case .edge: "com.microsoft.edgemac"
        case .safari: "com.apple.Safari"
        }
    }

    var symbol: String {
        switch self {
        case .chrome, .edge: "globe"
        case .safari: "safari"
        }
    }
}

/// Silinebilen veri türü; kullanıcı ikisini ayrı seçer.
enum PrivacyDataKind: String, CaseIterable, Sendable, Identifiable, Hashable {
    case history, cookies

    var id: String { rawValue }
    var title: String { self == .history ? "Geçmiş" : "Çerezler" }
}

/// Tarama sırasında bulunan tek dosya (kimliğiyle birlikte).
struct PrivacyFile: Sendable, Equatable, Identifiable {
    var id: String { path }
    let path: String
    let kind: PrivacyDataKind
    /// Profil adı ("Default", "Profile 1"); Safari için "".
    let profile: String
    let bytes: UInt64
    let dev: Int32
    let ino: UInt64
}

enum BrowserPrivacyState: Sendable, Equatable {
    /// Tarayıcının verisi yok (klasör yok).
    case notFound
    /// Tarayıcı açık: tarama ve silme reddedilir.
    case running
    /// Klasör okunamıyor (Tam Disk Erişimi gerekir).
    case noAccess
    case scanned
}

struct BrowserPrivacyScan: Sendable, Equatable {
    var browser: PrivacyBrowser
    var state: BrowserPrivacyState
    var profileCount = 0
    var files: [PrivacyFile] = []
    /// `.noAccess` iken erişilemeyen klasör (yeniden deneme için izlenir).
    var blockedPath: String?

    func files(of kind: PrivacyDataKind) -> [PrivacyFile] { files.filter { $0.kind == kind } }
    func bytes(of kind: PrivacyDataKind) -> UInt64 { files(of: kind).reduce(0) { $0 + $1.bytes } }
    /// Tarayıcı veri türü başına dosya içeriyor mu.
    func has(_ kind: PrivacyDataKind) -> Bool { !files(of: kind).isEmpty }
}

enum BrowserPrivacyRules {
    // MARK: Kurallar

    /// Hiçbir koşulda aday olmayan dosya adları (ad ya da bu önekle başlayan). Tarama ve aday üretimi bunu ayrıca uygular.
    static let denyList: [String] = ["Bookmarks", "Login Data", "Preferences", "Secure Preferences", "Web Data"]

    static func isDenied(_ fileName: String) -> Bool {
        denyList.contains { fileName == $0 || fileName.hasPrefix($0) }
    }

    /// Chrome/Edge profil klasörüne göre dosyalar. Yeni Chrome sürümlerinde çerezler `Network/` altındadır; ikisi de desteklenir.
    static let chromiumFiles: [(kind: PrivacyDataKind, relative: String)] = [
        (.history, "History"), (.history, "History-journal"), (.history, "Visited Links"), (.history, "Top Sites"),
        (.cookies, "Cookies"), (.cookies, "Cookies-journal"),
        (.cookies, "Network/Cookies"), (.cookies, "Network/Cookies-journal"),
    ]

    /// Safari dosyaları (ev klasörüne göre).
    static let safariFiles: [(kind: PrivacyDataKind, relative: String)] = [
        (.history, "Library/Safari/History.db"), (.history, "Library/Safari/History.db-wal"), (.history, "Library/Safari/History.db-shm"),
        (.cookies, "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"),
        (.cookies, "Library/Cookies/Cookies.binarycookies"),
    ]

    /// Chrome/Edge veri klasörü (ev klasörüne göre).
    static func chromiumRoot(_ browser: PrivacyBrowser, home: String) -> String? {
        switch browser {
        case .chrome: home + "/Library/Application Support/Google/Chrome"
        case .edge: home + "/Library/Application Support/Microsoft Edge"
        case .safari: nil
        }
    }

    /// Profil klasörü adı: "Default" ya da "Profile <sayı>". ("System Profile", "Guest Profile" vb. hariç.)
    static func isProfileName(_ name: String) -> Bool {
        if name == "Default" { return true }
        guard name.hasPrefix("Profile ") else { return false }
        let rest = name.dropFirst("Profile ".count)
        return !rest.isEmpty && rest.allSatisfy(\.isASCII) && rest.allSatisfy(\.isNumber)
    }

    // MARK: Tarama

    /// Tek tarayıcıyı tarar. Açıksa hiçbir dosya listelenmez (`.running`). Salt okunur: yalnızca dizin listesi ve lstat.
    static func scan(_ browser: PrivacyBrowser, home: String, running: Set<String>, probe: PathProbe = .live,
                     isCancelled: () -> Bool = { false }) -> BrowserPrivacyScan {
        if running.contains(browser.bundleID) { return BrowserPrivacyScan(browser: browser, state: .running) }
        switch browser {
        case .chrome, .edge: return scanChromium(browser, home: home, probe: probe, isCancelled: isCancelled)
        case .safari: return scanSafari(home: home, probe: probe)
        }
    }

    static func scanAll(home: String, running: Set<String>, probe: PathProbe = .live,
                        isCancelled: () -> Bool = { false }) -> [BrowserPrivacyScan] {
        var out: [BrowserPrivacyScan] = []
        for browser in PrivacyBrowser.allCases {
            if isCancelled() { break }
            out.append(scan(browser, home: home, running: running, probe: probe, isCancelled: isCancelled))
        }
        return out
    }

    private static func scanChromium(_ browser: PrivacyBrowser, home: String, probe: PathProbe, isCancelled: () -> Bool) -> BrowserPrivacyScan {
        guard let root = chromiumRoot(browser, home: home) else { return BrowserPrivacyScan(browser: browser, state: .notFound) }
        switch probe.check(root) {
        case .missing: return BrowserPrivacyScan(browser: browser, state: .notFound)
        case .denied: return BrowserPrivacyScan(browser: browser, state: .noAccess, blockedPath: root)
        case .ok: break
        }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else {
            return BrowserPrivacyScan(browser: browser, state: .noAccess, blockedPath: root)
        }
        var scan = BrowserPrivacyScan(browser: browser, state: .scanned)
        for name in names.sorted() where isProfileName(name) {
            if isCancelled() { break }
            let dir = root + "/" + name
            guard isRealDirectory(dir) else { continue }
            scan.profileCount += 1
            for entry in chromiumFiles {
                if let file = regularFile(dir + "/" + entry.relative, kind: entry.kind, profile: name) { scan.files.append(file) }
            }
        }
        if scan.profileCount == 0 { scan.state = .notFound }
        return scan
    }

    private static func scanSafari(home: String, probe: PathProbe) -> BrowserPrivacyScan {
        // Safari'nin klasörleri Tam Disk Erişimi ister; önce klasör denenir (izin penceresi açmaz).
        var dirs: [String] = []
        for entry in safariFiles {
            let dir = ((home + "/" + entry.relative) as NSString).deletingLastPathComponent
            if !dirs.contains(dir) { dirs.append(dir) }
        }
        var anyPresent = false
        for dir in dirs {
            switch probe.check(dir) {
            case .denied: return BrowserPrivacyScan(browser: .safari, state: .noAccess, blockedPath: dir)
            case .ok: anyPresent = true
            case .missing: break
            }
        }
        guard anyPresent else { return BrowserPrivacyScan(browser: .safari, state: .notFound) }
        var scan = BrowserPrivacyScan(browser: .safari, state: .scanned, profileCount: 1)
        for entry in safariFiles {
            if let file = regularFile(home + "/" + entry.relative, kind: entry.kind, profile: "") { scan.files.append(file) }
        }
        return scan
    }

    /// Sembolik bağ olmayan gerçek klasör mü.
    private static func isRealDirectory(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    /// Yalnızca normal dosya (sembolik bağ ve klasör değil) ve yasak listede olmayan ad.
    private static func regularFile(_ path: String, kind: PrivacyDataKind, profile: String) -> PrivacyFile? {
        guard !isDenied((path as NSString).lastPathComponent) else { return nil }
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        return PrivacyFile(path: path, kind: kind, profile: profile, bytes: UInt64(max(0, st.st_size)), dev: st.st_dev, ino: UInt64(st.st_ino))
    }

    // MARK: Adaylar

    /// Seçilen veri türleri için silme adayları. Tarayıcı açıksa boş döner. Her aday yalnızca kendi yolunu içeren tam-dosya kapsamı taşır;
    /// engelleyen uygulama tarayıcının kendisidir (silme anında `CleanupDeleter` yeniden okur).
    static func candidates(for scan: BrowserPrivacyScan, kinds: Set<PrivacyDataKind>, running: Set<String>) -> [DeletionCandidate] {
        guard scan.state == .scanned, !running.contains(scan.browser.bundleID) else { return [] }
        return scan.files.compactMap { file in
            guard kinds.contains(file.kind), !isDenied((file.path as NSString).lastPathComponent) else { return nil }
            let profile = file.profile.isEmpty ? "" : " · \(file.profile)"
            return DeletionCandidate(
                path: file.path, dev: file.dev, ino: file.ino, bytes: file.bytes,
                kind: CleanupKind("privacy.\(scan.browser.rawValue).\(file.kind.rawValue)"),
                scope: .exactFile(allowed: [file.path]), blockingBundleIDs: [scan.browser.bundleID],
                displayName: "\(scan.browser.shortName)\(profile) · \(file.kind.title) · \((file.path as NSString).lastPathComponent)"
            )
        }
    }

    // MARK: Metinler

    /// Onay penceresinde, kullanıcının neyi kaybedeceği.
    static func lossLines(browser: PrivacyBrowser, kinds: Set<PrivacyDataKind>) -> [String] {
        var lines: [String] = []
        if kinds.contains(.history) {
            lines.append("\(browser.shortName) geçmişi silinir: ziyaret edilen sayfalar ve en çok gidilen siteler kaybolur.")
        }
        if kinds.contains(.cookies) {
            lines.append("Tüm sitelerden çıkış yapılır: \(browser.shortName)'daki oturumlar ve çerezler silinir, siteleri yeniden giriş yaparak açarsınız.")
        }
        return lines
    }

    static func closeFirstText(_ browser: PrivacyBrowser) -> String { "Önce \(browser.accusative) kapatın" }
}
