import AppKit
import Darwin
import Foundation

/// Dosyalar ve Klasörler izniyle açılan kullanıcı klasörleri.
enum ProtectedFolder: String, Sendable, Hashable, CaseIterable {
    case downloads = "Downloads", desktop = "Desktop", documents = "Documents"

    var title: String {
        switch self {
        case .downloads: "İndirilenler"
        case .desktop: "Masaüstü"
        case .documents: "Belgeler"
        }
    }
}

/// Bir klasöre neden erişilemediği ve kullanıcının hangi ayarı açması gerektiği.
/// İzin durumu hiçbir zaman sistem izin veritabanından okunmaz; yalnızca klasörün kendisi denenir (probe).
enum AccessReason: Sendable, Hashable {
    /// İndirilenler / Masaüstü / Belgeler: Gizlilik ve Güvenlik › Dosyalar ve Klasörler.
    case filesAndFolders(ProtectedFolder)
    /// Çöp Sepeti, iOS yedekleri (MobileSync), Safari, Mail, Mesajlar: Tam Disk Erişimi.
    case fullDiskAccess
    /// Başka uygulamaların kapsayıcıları (Containers / Group Containers). Varsayım: yeni macOS "diğer uygulamaların verileri" iznini sorar.
    case appData
    /// Başka uygulamaların paketlerini silmek: Uygulama Yönetimi. Varsayım; ayar bağlantısı canlı doğrulanmadı.
    case appManagement
    /// Sistem Bütünlük Koruması: hiçbir ayar açmaz, düğme yok.
    case systemProtected

    /// Gizlilik ve Güvenlik altındaki bölmenin adı (yoksa nil).
    var paneName: String? {
        switch self {
        case .filesAndFolders: "Dosyalar ve Klasörler"
        case .fullDiskAccess, .appData: "Tam Disk Erişimi"
        case .appManagement: "Uygulama Yönetimi"
        case .systemProtected: nil
        }
    }

    var settingsURL: URL? {
        let anchor: String
        switch self {
        case .filesAndFolders: anchor = "Privacy_FilesAndFolders"
        case .fullDiskAccess, .appData: anchor = "Privacy_AllFiles"
        case .appManagement: anchor = "Privacy_AppBundles"
        case .systemProtected: return nil
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    /// Kısa durum metni (kart ve şerit için).
    var title: String {
        switch self {
        case .filesAndFolders(let folder): "\(folder.title) klasörüne erişim yok"
        case .fullDiskAccess: "Tam Disk Erişimi gerekiyor"
        case .appData: "Diğer uygulamaların verilerine erişim yok"
        case .appManagement: "Uygulama Yönetimi izni gerekiyor"
        case .systemProtected: "macOS tarafından korunuyor"
        }
    }

    var explanation: String {
        switch self {
        case .filesAndFolders(let folder):
            "Adalmon'un \(folder.title) klasörünü okuyabilmesi için Gizlilik ve Güvenlik › Dosyalar ve Klasörler'de Adalmon altında \(folder.title) anahtarını açın."
        case .fullDiskAccess:
            "Bu konum yalnızca Tam Disk Erişimi verilen uygulamalara açık. Gizlilik ve Güvenlik › Tam Disk Erişimi'nde Adalmon'u ekleyin ya da anahtarını açın."
        case .appData:
            "Bu klasör başka bir uygulamanın kapsayıcısı. macOS buna yalnızca Tam Disk Erişimi olan uygulamaların erişmesine izin veriyor."
        case .appManagement:
            "Başka uygulamaları silmek için Gizlilik ve Güvenlik › Uygulama Yönetimi'nde Adalmon'un açık olması gerekiyor."
        case .systemProtected:
            "Sistem Bütünlük Koruması altındaki bu konuma hiçbir uygulama dokunamaz. Yapılacak bir şey yok."
        }
    }

    var buttonTitle: String? {
        switch self {
        case .filesAndFolders: "Dosyalar ve Klasörler'i aç"
        case .fullDiskAccess, .appData: "Tam Disk Erişimi'ni aç"
        case .appManagement: "Uygulama Yönetimi'ni aç"
        case .systemProtected: nil
        }
    }

    /// Yardım penceresindeki üç adım.
    var steps: [String] {
        guard let pane = paneName else { return [] }
        let item: String
        if case .filesAndFolders(let folder) = self {
            item = "Listede Adalmon'u bulun ve \(folder.title) anahtarını açın. Adalmon listede yoksa + ile ekleyin."
        } else {
            item = "Listede Adalmon yoksa + düğmesine basın, Uygulamalar'dan Adalmon'u seçip ekleyin; varsa anahtarını açın."
        }
        return [
            "Aşağıdaki düğmeyle Sistem Ayarları › Gizlilik ve Güvenlik › \(pane) bölümünü açın.",
            item,
            "Adalmon'a geri dönün; erişim kendiliğinden yeniden denenir. Olmazsa \"Tekrar dene\"ye basın.",
        ]
    }
}

/// Bir klasörü açmayı deneyen işlev; testlerde sahtesi verilir.
struct PathProbe: Sendable {
    enum Raw: Sendable, Equatable { case ok, missing, denied }

    var check: @Sendable (String) -> Raw

    /// Gerçek deneme: klasörü salt okunur açar (sembolik bağı izlemez). İzin reddi EPERM/EACCES.
    static let live = PathProbe { path in
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd >= 0 {
            close(fd)
            return .ok
        }
        switch errno {
        case EPERM, EACCES: return .denied
        default: return .missing // ENOENT, ENOTDIR, ELOOP (kök sembolik bağ): gizlenir
        }
    }
}

enum CleanupAccess {
    /// Tam Disk Erişimi göstergesi için denenen klasör (izin yoksa EPERM döner, izin penceresi açmaz; varsayım).
    static let fullDiskAccessCanary = "Library/Safari"

    /// Saf tablo: erişilemeyen bir yolun nedeni. Bilinmeyen kullanıcı konumlarında Tam Disk Erişimi önerilir (her şeyi kapsar).
    static func reason(for path: String, home: String) -> AccessReason {
        let parts = CleanupDeleter.components(path)
        let homeParts = CleanupDeleter.components(home)
        func under(_ rel: String) -> Bool {
            let p = homeParts + rel.split(separator: "/").map(String.init)
            return parts == p || CleanupDeleter.isStrictDescendant(parts, of: p)
        }
        for folder in ProtectedFolder.allCases where under(folder.rawValue) { return .filesAndFolders(folder) }
        for rel in [".Trash", "Library/Application Support/MobileSync", "Library/Safari", "Library/Mail", "Library/Messages"] where under(rel) {
            return .fullDiskAccess
        }
        for rel in ["Library/Containers", "Library/Group Containers"] {
            let p = homeParts + rel.split(separator: "/").map(String.init)
            if CleanupDeleter.isStrictDescendant(parts, of: p) { return .appData }
        }
        let apps = ["/", "Applications"]
        if CleanupDeleter.isStrictDescendant(parts, of: apps) || CleanupDeleter.isStrictDescendant(parts, of: homeParts + ["Applications"]) {
            return .appManagement
        }
        if CleanupDeleter.isUnderSystemTree(parts) { return .systemProtected }
        return .fullDiskAccess
    }

    /// Tam Disk Erişimi açık mı: `~/Library/Safari` denenir. Klasör yoksa bilinmez (nil).
    static func fullDiskAccessGranted(home: String, probe: PathProbe = .live) -> Bool? {
        switch probe.check(home + "/" + fullDiskAccessCanary) {
        case .ok: true
        case .denied: false
        case .missing: nil
        }
    }
}

/// Erişim reddedilen kökleri izler. Yalnızca en az bir kök engelliyken uygulama öne gelince (didBecomeActive) yeniden dener;
/// hiçbir zamanlayıcı yoktur ve engel kalmayınca gözlemci kaldırılır.
@MainActor @Observable
final class CleanupAccessMonitor {
    let home: String
    @ObservationIgnored let probe: PathProbe
    /// Kök yolu → neden.
    private(set) var blocked: [String: AccessReason] = [:]
    private(set) var fullDiskAccess: Bool?
    /// Ayarlar açılıp dönüldüğü hâlde engel sürüyorsa: "Adalmon'u yeniden başlat" önerisi.
    private(set) var suggestRestart = false
    /// Yeniden denemede erişilebilir olan kökler (VM bunları yeniden tarar).
    @ObservationIgnored var onUnblocked: (([String]) -> Void)?
    /// Ayar bağlantısını açar (testlerde sahtesi verilir).
    @ObservationIgnored var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    @ObservationIgnored private var openedSettings = false
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(home: String = NSHomeDirectory(), probe: PathProbe = .live) {
        self.home = home
        self.probe = probe
    }

    var isObserving: Bool { observer != nil }

    func reason(for path: String) -> AccessReason? { blocked[path] }

    /// Tarama sonucundaki kök durumlarını işler: `.noAccess` engellenir, diğerleri serbest kalır.
    func update(states: [String: CleanupRootState]) {
        for (path, state) in states {
            setBlocked(path, state == .noAccess)
        }
    }

    func setBlocked(_ path: String, _ isBlocked: Bool) {
        if isBlocked {
            if blocked[path] == nil { blocked[path] = CleanupAccess.reason(for: path, home: home) }
        } else if blocked[path] != nil {
            blocked[path] = nil
        }
        if blocked.isEmpty { suggestRestart = false; openedSettings = false }
        syncObserver()
    }

    func refreshFullDiskAccess() {
        fullDiskAccess = CleanupAccess.fullDiskAccessGranted(home: home, probe: probe)
    }

    func openSettings(for reason: AccessReason) {
        guard let url = reason.settingsURL else { return }
        openedSettings = true
        openURL(url)
    }

    /// Engelli kökleri yeniden dener; erişilebilir olanları döndürür (ve `onUnblocked`a verir).
    @discardableResult
    func reprobe() -> [String] {
        var freed: [String] = []
        for path in blocked.keys.sorted() {
            switch probe.check(path) {
            case .ok: freed.append(path); blocked[path] = nil
            case .missing: blocked[path] = nil
            case .denied: break
            }
        }
        refreshFullDiskAccess()
        if blocked.isEmpty {
            suggestRestart = false
            openedSettings = false
        } else if openedSettings {
            suggestRestart = true
        }
        syncObserver()
        if !freed.isEmpty { onUnblocked?(freed) }
        return freed
    }

    /// Görünüm yeniden açılınca: hâlâ engel varsa gözlemciyi geri kurar.
    func resume() { syncObserver() }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func syncObserver() {
        if blocked.isEmpty {
            stop()
        } else if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.reprobe() }
            }
        }
    }

    /// Bu süreç bittikten sonra Adalmon'u yeniden açar (tek kopya koruması yeni kopyanın eskisine yol vermesine yol açmasın diye
    /// önce bu sürecin çıkması beklenir).
    static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // En çok ~10 sn beklenir; süreç hâlâ yaşıyorsa (çıkış iptal edildi) yeniden açılmaz.
        let script = "i=0; while /bin/kill -0 \(pid) 2>/dev/null && [ $i -lt 50 ]; do /bin/sleep 0.2; i=$((i+1)); done; "
            + "/bin/kill -0 \(pid) 2>/dev/null || /usr/bin/open \"$0\""
        task.arguments = ["-c", script, Bundle.main.bundlePath]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            return
        }
    }
}
