import Foundation

/// Temizlik kategorileri. Her kategorinin bir ya da daha fazla izinli kökü vardır; öğeler yalnızca kökün doğrudan çocuklarıdır.
enum CleanupCategory: String, CaseIterable, Identifiable, Sendable {
    case appCaches, derivedData, archives, deviceSupport, simCaches, pkgCaches, iosBackups, downloads, trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appCaches: "Uygulama önbellekleri"
        case .derivedData: "Xcode DerivedData"
        case .archives: "Xcode arşivleri"
        case .deviceSupport: "Cihaz destek dosyaları"
        case .simCaches: "Simülatör önbellekleri"
        case .pkgCaches: "Paket yöneticisi önbellekleri"
        case .iosBackups: "iOS yedekleri"
        case .downloads: "İndirilenler"
        case .trash: "Çöp Sepeti"
        }
    }

    var systemImage: String {
        switch self {
        case .appCaches: "archivebox"
        case .derivedData: "hammer"
        case .archives: "shippingbox"
        case .deviceSupport: "iphone.gen3"
        case .simCaches: "ipad.and.iphone"
        case .pkgCaches: "cube.box"
        case .iosBackups: "externaldrive.badge.timemachine"
        case .downloads: "arrow.down.circle"
        case .trash: "trash"
        }
    }

    /// Önizlemede kendiliğinden işaretli mi. Arşivler (dSYM), cihaz destek, yedekler ve İndirilenler yalnızca listelenir.
    var defaultSelected: Bool {
        switch self {
        case .appCaches, .derivedData, .simCaches, .pkgCaches: true
        case .archives, .deviceSupport, .iosBackups, .downloads, .trash: false
        }
    }

    /// İzin penceresi açabilecek konumlar: varsayılan "Tara"ya girmez, kendi düğmesiyle taranır.
    var needsExplicitScan: Bool { self == .downloads || self == .iosBackups || self == .trash }

    /// Varsayılan "Tara" ile taranan kategoriler.
    static let defaultScan: [CleanupCategory] = allCases.filter { !$0.needsExplicitScan }
}

struct CleanupRoot: Sendable, Equatable {
    let category: CleanupCategory
    let path: String
    var onlyNames: Set<String>?
    var skipNames: Set<String> = []
    var skipPrefixes: [String] = []

    func allows(_ name: String) -> Bool {
        if let onlyNames, !onlyNames.contains(name) { return false }
        if skipNames.contains(name) { return false }
        return !skipPrefixes.contains { name.hasPrefix($0) }
    }
}

struct CleanupItem: Identifiable, Sendable, Equatable {
    var id: String { path }
    let path: String
    let rootPath: String
    let category: CleanupCategory
    let bytes: UInt64
    let isDirectory: Bool
    let modified: Date?
    let dev: Int32
    let ino: UInt64
    /// "Açık": uygulaması çalışıyor, seçilemez ve taşırken yine atlanır.
    var blockedReason: String?

    var name: String { (path as NSString).lastPathComponent }
}

enum CleanupRootState: Sendable, Equatable {
    case missing, noAccess, scanned
}

enum CleanupCatalog {
    static let xcodeBundleID = "com.apple.dt.Xcode"
    static let simulatorBundleID = "com.apple.iphonesimulator"
    static let runningBadge = "Açık"
    /// Liste ve taşıma alt sınırı: daha küçükler gösterilmez, sayılmaz, taşınmaz.
    static let minItemBytes: UInt64 = 1 << 20
    /// İndirilenler: bu boyuttan büyükler ya da `downloadsStaleDays` gündür değişmeyenler listelenir.
    static let downloadsLargeBytes: UInt64 = 100 << 20
    static let downloadsStaleDays = 90

    /// Caches içinde paket yöneticisi önbelleklerine ait adlar (iki kategoriye girmesin).
    static let pkgCacheNames: Set<String> = ["Homebrew", "pip", "Yarn", "pnpm"]

    /// Tüm izinli kökler. `.trash` burada yoktur: Çöp Sepeti yalnızca boyut olarak gösterilir, öğesi taşınamaz.
    static func roots(home: String, ownBundleID: String? = Bundle.main.bundleIdentifier) -> [CleanupRoot] {
        let lib = home + "/Library"
        let caches = lib + "/Caches"
        let xcode = lib + "/Developer/Xcode"
        var cacheSkips = FolderWatchList.cachesSkipNames.union(pkgCacheNames)
        if let ownBundleID { cacheSkips.insert(ownBundleID) }
        var roots: [CleanupRoot] = [
            CleanupRoot(category: .appCaches, path: caches, skipNames: cacheSkips, skipPrefixes: ["com.apple."]),
            CleanupRoot(category: .derivedData, path: xcode + "/DerivedData"),
            CleanupRoot(category: .archives, path: xcode + "/Archives"),
        ]
        for platform in ["iOS", "watchOS", "tvOS", "visionOS", "macOS"] {
            roots.append(CleanupRoot(category: .deviceSupport, path: xcode + "/\(platform) DeviceSupport"))
        }
        roots += [
            CleanupRoot(category: .simCaches, path: lib + "/Developer/CoreSimulator/Caches"),
            CleanupRoot(category: .pkgCaches, path: home + "/.npm", onlyNames: ["_cacache"]),
            CleanupRoot(category: .pkgCaches, path: caches + "/Homebrew"),
            CleanupRoot(category: .pkgCaches, path: caches + "/pip"),
            CleanupRoot(category: .pkgCaches, path: caches + "/Yarn"),
            CleanupRoot(category: .pkgCaches, path: lib + "/pnpm/store"),
            CleanupRoot(category: .iosBackups, path: lib + "/Application Support/MobileSync/Backup"),
            CleanupRoot(category: .downloads, path: home + "/Downloads"),
        ]
        return roots
    }

    static func trashPath(home: String) -> String { home + "/.Trash" }

    /// Çalışan uygulamaya göre öğenin engel nedeni (yoksa nil).
    static func blockedReason(category: CleanupCategory, name: String, runningBundleIDs: Set<String>) -> String? {
        switch category {
        case .appCaches: runningBundleIDs.contains(name) ? runningBadge : nil
        case .derivedData: runningBundleIDs.contains(xcodeBundleID) ? runningBadge : nil
        // Simülatör önbelleklerini Xcode de kullanır.
        case .simCaches: runningBundleIDs.contains(simulatorBundleID) || runningBundleIDs.contains(xcodeBundleID) ? runningBadge : nil
        default: nil
        }
    }
}
