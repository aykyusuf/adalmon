import Darwin
import Foundation

/// Akıllı tarama adımları, çalışma sırasıyla. Temizlenebilir adımların öğeleri seçilebilir; `reviewOnly` adımlar yalnızca
/// sayı/boyut gösterir ve hiçbir zaman seçime girmez. Her adım tek başına taranır; iptal edilirse sonrakiler başlamaz.
enum SmartScanStep: String, CaseIterable, Identifiable, Sendable {
    case appCaches, logs, browserCaches, devCaches, projectArtifacts, trash, largeFiles, orphans

    var id: String { rawValue }

    /// Bu adımın `CleanupScanner` ile taradığı kategoriler (proje artıkları, çöp, büyük dosyalar ve yetimler kendi yolunu kullanır).
    var categories: [CleanupCategory] {
        switch self {
        case .appCaches: [.appCaches]
        case .logs: [.logs]
        case .browserCaches: [.browserCaches]
        case .devCaches: [.derivedData, .simCaches, .pkgCaches]
        case .projectArtifacts: [.projectArtifacts]
        case .trash: [.trash]
        case .largeFiles: [.downloads]
        case .orphans: []
        }
    }

    var title: String {
        switch self {
        case .appCaches: "Sistem ve uygulama önbellekleri"
        case .logs: "Günlükler"
        case .browserCaches: "Tarayıcı önbellekleri"
        case .devCaches: "Xcode ve paket önbellekleri"
        case .projectArtifacts: "Gereksiz build'ler ve proje artıkları"
        case .trash: "Çöp Sepeti"
        case .largeFiles: "Büyük dosyalar"
        case .orphans: "Silinmiş uygulama kalıntıları"
        }
    }

    var systemImage: String {
        switch self {
        case .appCaches: "archivebox"
        case .logs: "doc.text"
        case .browserCaches: "globe"
        case .devCaches: "hammer"
        case .projectArtifacts: "folder.badge.gearshape"
        case .trash: "trash"
        case .largeFiles: "doc.badge.clock"
        case .orphans: "questionmark.folder"
        }
    }

    var note: String {
        switch self {
        case .appCaches: "Uygulamaların yeniden üretebildiği önbellekler. Açık uygulamaların önbelleği atlanır."
        case .logs: "Uygulama günlükleri. Çökme raporları kalır; kendiliğinden seçilmez."
        case .browserCaches: "Chrome ve Edge önbellekleri. Yalnızca kapalı tarayıcılar temizlenir."
        case .devCaches: "Xcode DerivedData, simülatör ve paket yöneticisi önbellekleri. Gerektiğinde yeniden oluşur."
        case .projectArtifacts: "node_modules, .build, DerivedData, target, Pods ve build klasörleri. Derlemede/kurulumda yeniden oluşur."
        case .trash: "Yalnızca boyut gösterilir. Boşaltmak için Finder'ı kullanın."
        case .largeFiles: "İndirilenler'deki 100 MB ve üstü dosyalar. Siz bakmadan seçilmez."
        case .orphans: "Kurulu olmayan uygulamalardan kalan Library dosyaları. Liste tahmindir; kontrol etmeden silmeyin."
        }
    }

    /// "İncele" bağlantısının gideceği alt bölüm.
    var subsection: CleanupSubsection {
        switch self {
        case .appCaches, .logs, .browserCaches, .trash: .junk
        case .devCaches, .projectArtifacts: .dev
        case .largeFiles: .largeOld
        case .orphans: .uninstaller
        }
    }

    /// Temizle'ye girebilir mi (Çöp Sepeti, büyük dosyalar ve yetimler giremez).
    var isCleanable: Bool {
        switch self {
        case .trash, .largeFiles, .orphans: false
        default: true
        }
    }

    /// Yalnızca sayı/boyut gösterilen, "İncele →" ile başka bölüme giden adım.
    var isReviewOnly: Bool { self == .largeFiles || self == .orphans }
}

/// Taranmayan, hiçbir zaman seçilmeyen türler: yalnızca "İncele" kartı (sayı bile gösterilmez).
enum SmartScanReviewKind: String, CaseIterable, Identifiable, Sendable {
    case duplicates, privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duplicates: "Kopya dosyalar"
        case .privacy: "Gizlilik izleri"
        }
    }

    var systemImage: String {
        switch self {
        case .duplicates: "square.on.square"
        case .privacy: "hand.raised"
        }
    }

    var note: String {
        switch self {
        case .duplicates: "Aynı içeriğe sahip dosyalar. Tarama diski okur, uzun sürebilir; kendi bölümünde yapılır."
        case .privacy: "Tarayıcı geçmişi ve çerezler. Silmek oturumları kapatır."
        }
    }

    var subsection: CleanupSubsection {
        switch self {
        case .duplicates: .duplicates
        case .privacy: .privacy
        }
    }
}

/// Bir adımın sonucu.
struct SmartScanStepResult: Sendable, Equatable {
    var step: SmartScanStep
    var state: CleanupRootState
    var items: [CleanupItem] = []
    /// Çöp Sepeti adımında toplam boyut (öğe listelenmez).
    var trashBytes: UInt64 = 0
    /// Açık tarayıcı adları (tarayıcı adımında).
    var runningBrowsers: [String] = []
    /// Proje artıkları adımında aranan kökler ve durumları (erişim yok olanlar gösterilir).
    var rootStates: [String: CleanupRootState] = [:]
    /// Yalnızca-incele adımlarında sayı ve boyut (büyük dosyalar, yetimler).
    var reviewCount = 0
    var reviewBytes: UInt64 = 0

    /// Silinebilir (engelli olmayan) öğeler.
    var cleanableItems: [CleanupItem] { items.filter { $0.blockedReason == nil } }
    var cleanableBytes: UInt64 { cleanableItems.reduce(0) { $0 + $1.bytes } }
    var blockedItems: [CleanupItem] { items.filter { $0.blockedReason != nil } }
    var blockedBytes: UInt64 { blockedItems.reduce(0) { $0 + $1.bytes } }

    /// Erişimi reddedilen kökler (sıralı).
    var deniedRoots: [String] { rootStates.filter { $0.value == .noAccess }.map(\.key).sorted() }

    /// Satırda gösterilen boyut.
    var displayBytes: UInt64 {
        switch step {
        case .trash: trashBytes
        case .largeFiles, .orphans: reviewBytes
        default: cleanableBytes
        }
    }
}

struct SmartScanResult: Sendable, Equatable {
    var results: [SmartScanStep: SmartScanStepResult] = [:]
    /// Tamamlanma sırası.
    var completed: [SmartScanStep] = []
    var wasCancelled = false

    /// Hiç başlamamış ya da iptalle yarım kalmış adımlar.
    var notRun: [SmartScanStep] { SmartScanStep.allCases.filter { results[$0] == nil } }

    /// Temizlenebilir adımların engelli olmayan tüm öğeleri (seçimden bağımsız).
    var allCleanableItems: [CleanupItem] {
        SmartScanStep.allCases.filter(\.isCleanable).flatMap { results[$0]?.cleanableItems ?? [] }
    }

    func cleanableBytes(steps: Set<SmartScanStep>? = nil) -> UInt64 {
        results.values.filter { $0.step.isCleanable && (steps?.contains($0.step) ?? true) }.reduce(0) { $0 + $1.cleanableBytes }
    }

    func cleanableItems(steps: Set<SmartScanStep>? = nil) -> [CleanupItem] {
        SmartScanStep.allCases.filter { $0.isCleanable && (steps?.contains($0) ?? true) }
            .flatMap { results[$0]?.cleanableItems ?? [] }
    }

    /// Silme adayları: tek silme noktası (`CleanupDeleter`) kendi kapsam denetimini yine yapar.
    func deletionCandidates(steps: Set<SmartScanStep>? = nil, roots: [CleanupRoot]) -> [DeletionCandidate] {
        cleanableItems(steps: steps).map { DeletionCandidate(item: $0, roots: roots) }
    }
}

/// Varsayılan seçim kuralları (tek yer). Önbellekler `CleanupCategory.defaultSelected` kuralını izler; günlükler seçilmez;
/// proje artıkları yalnızca `staleDays` günden uzun süredir değişmediyse; engelli öğe asla.
enum SmartScanSelection {
    static let staleDays = 30

    static func isRecent(_ item: CleanupItem, now: Date) -> Bool {
        guard let modified = item.modified else { return true } // tarih yoksa yeni say: seçilmez
        return modified > now.addingTimeInterval(-Double(staleDays) * 86_400)
    }

    static func isSelectedByDefault(_ item: CleanupItem, now: Date) -> Bool {
        guard item.blockedReason == nil else { return false }
        if item.category == .projectArtifacts { return !isRecent(item, now: now) }
        return item.category.defaultSelected
    }

    static func defaultSelection(_ result: SmartScanResult, now: Date) -> Set<String> {
        Set(result.allCleanableItems.filter { isSelectedByDefault($0, now: now) }.map(\.id))
    }
}

/// Akıllı tarama: adımları sırayla çalıştırır. Bütün kural listelerini bilen tek yer burasıdır.
enum SmartScanAggregator {
    /// Proje klasörü seçilmemişse (ve her zaman ek olarak) aranan yaygın geliştirme kökleri (ev klasörüne göre).
    static let commonProjectRootNames = ["Developer", "Projects", "Documents", "Desktop", "Code", "src", "dev", "GitHub", "repos"]

    /// `CleanupScanner` ile taranan güvenli kategoriler.
    static var scannedCategories: Set<CleanupCategory> {
        Set(SmartScanStep.allCases.flatMap(\.categories))
    }

    /// Kullanıcının klasörleri + var olan gerçek (sembolik bağ olmayan) yaygın kökler; aynı klasör bir kez.
    static func projectSearchRoots(home: String, userFolders: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        let candidates = userFolders + commonProjectRootNames.map { home + "/" + $0 }
        for path in candidates {
            guard ProjectArtifactScanner.isRealDirectory(path) else { continue }
            let key = (CleanupDeleter.realPath(path) ?? path).lowercased()
            if seen.insert(key).inserted { out.append(path) }
        }
        return out
    }

    /// - Parameters:
    ///   - projectFolders: kullanıcının eklediği klasörler (`ProjectFoldersStore`); ortak köklere eklenir.
    ///   - appRoots: yetim bulmak için kurulu uygulama klasörleri (testlerde `[]`).
    ///   - orphanResolver: kimliğin kurulu bir uygulamaya çözülüp çözülmediği (testlerde `{ _ in false }`).
    ///   - isCancelled: her adımdan önce ve adım içinde denetlenir; true olunca sonraki adımlar başlamaz.
    ///   - stepStarted: bir adım başlarken çağrılır (ilerleme göstergesi).
    ///   - detail: adım içi ayrıntı (şu an aranan kök klasör adı).
    ///   - stepFinished: bir adım bittiğinde çağrılır (kısmi sonuç).
    static func run(home: String, runningBundleIDs: Set<String>, ownBundleID: String? = Bundle.main.bundleIdentifier,
                    steps: [SmartScanStep] = SmartScanStep.allCases, projectFolders: [String] = [],
                    appRoots: [AppRoot]? = nil, orphanResolver: @escaping @Sendable (String) -> Bool = InstalledAppScanner.liveResolver,
                    now: Date = Date(), probe: PathProbe = .live,
                    isCancelled: @escaping () -> Bool = { false },
                    stepStarted: (SmartScanStep) -> Void = { _ in },
                    detail: (String) -> Void = { _ in },
                    stepFinished: (SmartScanStepResult) -> Void = { _ in }) -> SmartScanResult {
        var out = SmartScanResult()
        for step in steps {
            if isCancelled() {
                out.wasCancelled = true
                break
            }
            stepStarted(step)
            let result: SmartScanStepResult?
            switch step {
            case .trash:
                result = trashStep(home: home, isCancelled: isCancelled)
            case .projectArtifacts:
                result = projectStep(home: home, userFolders: projectFolders, runningBundleIDs: runningBundleIDs, now: now,
                                     probe: probe, isCancelled: isCancelled, detail: detail)
            case .largeFiles:
                result = largeFilesStep(home: home, probe: probe, isCancelled: isCancelled)
            case .orphans:
                result = orphanStep(home: home, runningBundleIDs: runningBundleIDs, appRoots: appRoots ?? InstalledAppScanner.defaultRoots(home: home),
                                    resolver: orphanResolver, isCancelled: isCancelled)
            default:
                result = categoryStep(step, home: home, runningBundleIDs: runningBundleIDs, ownBundleID: ownBundleID,
                                      probe: probe, isCancelled: isCancelled)
            }
            guard let result else {
                // Adım içinde iptal: yarım toplam göstermemek için sonucu at.
                out.wasCancelled = true
                break
            }
            out.results[step] = result
            out.completed.append(step)
            stepFinished(result)
        }
        return out
    }

    // MARK: Adımlar

    private static func trashStep(home: String, isCancelled: @escaping () -> Bool) -> SmartScanStepResult? {
        let trash = CleanupScanner.trashSize(home: home, isCancelled: isCancelled)
        if isCancelled() { return nil }
        return SmartScanStepResult(step: .trash, state: trash.state, trashBytes: trash.bytes)
    }

    private static func categoryStep(_ step: SmartScanStep, home: String, runningBundleIDs: Set<String>, ownBundleID: String?,
                                     probe: PathProbe, isCancelled: @escaping () -> Bool) -> SmartScanStepResult? {
        let out = CleanupScanner.scan(categories: step.categories, home: home, runningBundleIDs: runningBundleIDs,
                                      ownBundleID: ownBundleID, probe: probe, isCancelled: isCancelled)
        if isCancelled() { return nil }
        // Savunma: katalog yanlışlıkla başka bir kategori döndürse bile adım dışına çıkanlar alınmaz.
        let allowed = Set(step.categories)
        let items = out.items.filter { allowed.contains($0.category) }
        let paths = Set(CleanupCatalog.roots(home: home, ownBundleID: ownBundleID).filter { allowed.contains($0.category) }.map(\.path))
        return SmartScanStepResult(
            step: step, state: combinedState(paths.compactMap { out.states[$0] }), items: items,
            runningBrowsers: step == .browserCaches ? JunkRules.runningBrowsers(runningBundleIDs) : []
        )
    }

    private static func combinedState(_ states: [CleanupRootState]) -> CleanupRootState {
        states.contains(.scanned) ? .scanned : states.contains(.noAccess) ? .noAccess : .missing
    }

    /// Proje artıkları: kök başına erişim denemesi (TCC reddi o kökü atlar), derinlik ≤ 6, sembolik bağ yok.
    private static func projectStep(home: String, userFolders: [String], runningBundleIDs: Set<String>, now: Date, probe: PathProbe,
                                    isCancelled: @escaping () -> Bool, detail: (String) -> Void) -> SmartScanStepResult? {
        var states: [String: CleanupRootState] = [:]
        var items: [CleanupItem] = []
        var seen = Set<String>()
        // Sembolik bağ ya da yok olan kökler `projectSearchRoots` içinde zaten elenir; reddedilen kökler listede kalıp "erişim yok" olur.
        for root in projectSearchRoots(home: home, userFolders: userFolders) {
            if isCancelled() { return nil }
            detail((root as NSString).lastPathComponent)
            switch CleanupScanner.probe(root, home: home, using: probe) {
            case .missing: states[root] = .missing
            case .noAccess: states[root] = .noAccess
            case .ok:
                guard let found = ProjectArtifactScanner.scan(root: root, runningBundleIDs: runningBundleIDs, skipPackages: true,
                                                              isCancelled: isCancelled) else {
                    states[root] = .missing
                    continue
                }
                if isCancelled() { return nil }
                states[root] = .scanned
                for item in found where seen.insert(item.path).inserted {
                    items.append(withActivity(item))
                }
            }
        }
        if isCancelled() { return nil }
        items.sort { $0.bytes > $1.bytes }
        let list = Array(states.values)
        return SmartScanStepResult(step: .projectArtifacts, state: list.isEmpty ? .missing : combinedState(list),
                                   items: items, rootStates: states)
    }

    /// "Son değişiklik": artığın, doğrudan çocuklarının, proje klasörünün ve onun doğrudan çocuklarının (.git dahil; artığın
    /// kendisi hariç) en yeni değişiklik zamanı. Dosya içeriği düzenlemeleri alt klasörleri saymaz; bu bilinçli bir yaklaşıklıktır.
    static func lastActivity(of item: CleanupItem) -> Date? {
        var newest = item.modified
        func consider(_ path: String) {
            var st = stat()
            guard lstat(path, &st) == 0 else { return }
            let date = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
            if newest == nil || date > newest! { newest = date }
        }
        func considerChildren(of dir: String, skipping: String? = nil, limit: Int = 4000) {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
            for name in names.prefix(limit) where dir + "/" + name != skipping { consider(dir + "/" + name) }
        }
        let project = (item.path as NSString).deletingLastPathComponent
        consider(item.path)
        considerChildren(of: item.path)
        consider(project)
        considerChildren(of: project, skipping: item.path)
        return newest
    }

    private static func withActivity(_ item: CleanupItem) -> CleanupItem {
        CleanupItem(path: item.path, rootPath: item.rootPath, category: item.category, bytes: item.bytes, isDirectory: item.isDirectory,
                    modified: lastActivity(of: item), dev: item.dev, ino: item.ino, blockedReason: item.blockedReason,
                    blockingBundleIDs: item.blockingBundleIDs)
    }

    /// İndirilenler'de 100 MB ve üstü: yalnızca sayı ve boyut.
    private static func largeFilesStep(home: String, probe: PathProbe, isCancelled: @escaping () -> Bool) -> SmartScanStepResult? {
        let out = CleanupScanner.scan(categories: [.downloads], home: home, runningBundleIDs: [], ownBundleID: nil, probe: probe,
                                      isCancelled: isCancelled)
        if isCancelled() { return nil }
        let big = out.items.filter { $0.bytes >= CleanupCatalog.downloadsLargeBytes }
        let path = CleanupCatalog.roots(home: home, ownBundleID: nil).first { $0.category == .downloads }?.path
        let state = path.flatMap { out.states[$0] } ?? .missing
        return SmartScanStepResult(step: .largeFiles, state: state, reviewCount: big.count,
                                   reviewBytes: big.reduce(0) { $0 + $1.bytes })
    }

    /// Kaldırıcı yetimleri: yalnızca Info.plist kimlikleri okunur (uygulama boyutu ölçülmez), yetim klasörlerin boyutu ölçülür.
    private static func orphanStep(home: String, runningBundleIDs: Set<String>, appRoots: [AppRoot],
                                   resolver: @escaping @Sendable (String) -> Bool, isCancelled: @escaping () -> Bool) -> SmartScanStepResult? {
        let ids = installedBundleIDs(roots: appRoots, isCancelled: isCancelled)
        if isCancelled() { return nil }
        let index = LibraryIndex.load(home: home)
        let groups = OrphanFinder.find(index: index, installedIDs: ids.union(runningBundleIDs), ownIDs: InstalledAppScanner.ownIDs(),
                                       resolver: resolver, isCancelled: isCancelled)
        if isCancelled() { return nil }
        return SmartScanStepResult(step: .orphans, state: .scanned, reviewCount: groups.count,
                                   reviewBytes: groups.reduce(0) { $0 + $1.bytes })
    }

    static func installedBundleIDs(roots: [AppRoot], isCancelled: () -> Bool) -> Set<String> {
        var ids = Set<String>()
        func readID(_ appPath: String) {
            let plist = NSDictionary(contentsOfFile: appPath + "/Contents/Info.plist")
            if let id = plist?["CFBundleIdentifier"] as? String, !id.isEmpty { ids.insert(id) }
        }
        func names(_ dir: String) -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] }
        for root in roots {
            for name in names(root.path) {
                if isCancelled() { return ids }
                let path = root.path + "/" + name
                if name.hasSuffix(".app") {
                    readID(path)
                } else if root.subfolders, ProjectArtifactScanner.isRealDirectory(path) {
                    for child in names(path) where child.hasSuffix(".app") { readID(path + "/" + child) }
                }
            }
        }
        return ids
    }
}
