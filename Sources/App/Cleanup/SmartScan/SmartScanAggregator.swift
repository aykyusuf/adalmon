import Foundation

/// Akıllı tarama adımları: yalnızca güvenli varsayılan türler. Her adım sırayla, tek başına taranır;
/// iptal edilirse sonraki adımlar hiç başlamaz. Riskli türler (`SmartScanReviewKind`) burada yoktur ve taranmaz.
enum SmartScanStep: String, CaseIterable, Identifiable, Sendable {
    case appCaches, browserCaches, devCaches, trash

    var id: String { rawValue }

    /// Bu adımın taradığı kategoriler. Hepsi `defaultSelected` olmalıdır (Çöp Sepeti hariç: yalnızca boyut).
    var categories: [CleanupCategory] {
        switch self {
        case .appCaches: [.appCaches]
        case .browserCaches: [.browserCaches]
        case .devCaches: [.derivedData, .simCaches, .pkgCaches]
        case .trash: [.trash]
        }
    }

    var title: String {
        switch self {
        case .appCaches: "Uygulama önbellekleri"
        case .browserCaches: "Tarayıcı önbellekleri"
        case .devCaches: "Geliştirici önbellekleri"
        case .trash: "Çöp Sepeti"
        }
    }

    var systemImage: String {
        switch self {
        case .appCaches: "archivebox"
        case .browserCaches: "globe"
        case .devCaches: "hammer"
        case .trash: "trash"
        }
    }

    var note: String {
        switch self {
        case .appCaches: "Uygulamaların yeniden üretebildiği önbellekler. Açık uygulamaların önbelleği atlanır."
        case .browserCaches: "Chrome ve Edge önbellekleri. Yalnızca kapalı tarayıcılar temizlenir."
        case .devCaches: "Xcode DerivedData, simülatör ve paket yöneticisi önbellekleri. Gerektiğinde yeniden oluşur."
        case .trash: "Yalnızca boyut gösterilir. Boşaltmak için Finder'ı kullanın."
        }
    }

    /// "İncele" bağlantısının gideceği alt bölüm.
    var subsection: CleanupSubsection {
        switch self {
        case .appCaches, .browserCaches, .trash: .junk
        case .devCaches: .dev
        }
    }

    /// Temizle'ye girebilir mi (Çöp Sepeti'nin öğesi taşınamaz).
    var isCleanable: Bool { self != .trash }
}

/// Otomatik taranmayan, hiçbir zaman seçilmeyen riskli türler: yalnızca "İncele" kartı.
enum SmartScanReviewKind: String, CaseIterable, Identifiable, Sendable {
    case orphans, largeOld, duplicates, privacy, projectArtifacts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .orphans: "Yetim dosyalar"
        case .largeOld: "Büyük ve eski dosyalar"
        case .duplicates: "Kopya dosyalar"
        case .privacy: "Gizlilik izleri"
        case .projectArtifacts: "Proje artıkları"
        }
    }

    var systemImage: String {
        switch self {
        case .orphans: "questionmark.folder"
        case .largeOld: "doc.badge.clock"
        case .duplicates: "square.on.square"
        case .privacy: "hand.raised"
        case .projectArtifacts: "folder.badge.gearshape"
        }
    }

    var note: String {
        switch self {
        case .orphans: "Kurulu olmayan uygulamalardan kalan Library dosyaları. Liste tahmindir; kontrol etmeden seçmeyin."
        case .largeOld: "Seçtiğiniz klasörlerdeki büyük ve uzun süredir açılmamış dosyalar."
        case .duplicates: "Aynı içeriğe sahip dosyalar. Tarama diski okur, uzun sürebilir."
        case .privacy: "Tarayıcı geçmişi ve çerezler. Silmek oturumları kapatır."
        case .projectArtifacts: "node_modules, .build, Pods gibi proje klasörleri. Geliştirici bölümünde ayrıca taranır."
        }
    }

    var subsection: CleanupSubsection {
        switch self {
        case .orphans: .uninstaller
        case .largeOld: .largeOld
        case .duplicates: .duplicates
        case .privacy: .privacy
        case .projectArtifacts: .dev
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

    /// Silinebilir (engelli olmayan) öğeler.
    var cleanableItems: [CleanupItem] { items.filter { $0.blockedReason == nil } }
    var cleanableBytes: UInt64 { cleanableItems.reduce(0) { $0 + $1.bytes } }
    var blockedItems: [CleanupItem] { items.filter { $0.blockedReason != nil } }
    var blockedBytes: UInt64 { blockedItems.reduce(0) { $0 + $1.bytes } }

    /// Satırda gösterilen boyut.
    var displayBytes: UInt64 { step == .trash ? trashBytes : cleanableBytes }
}

struct SmartScanResult: Sendable, Equatable {
    var results: [SmartScanStep: SmartScanStepResult] = [:]
    /// Tamamlanma sırası.
    var completed: [SmartScanStep] = []
    var wasCancelled = false

    /// Hiç başlamamış ya da iptalle yarım kalmış adımlar.
    var notRun: [SmartScanStep] { SmartScanStep.allCases.filter { results[$0] == nil } }

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

/// Akıllı tarama: güvenli adımları sırayla çalıştırır. Bütün kural listelerini bilen tek yer burasıdır.
enum SmartScanAggregator {
    /// Güvenli kategoriler: hepsi varsayılan seçili ve kendi düğmesi gerektirmeyen türlerdir.
    static var scannedCategories: Set<CleanupCategory> {
        Set(SmartScanStep.allCases.flatMap(\.categories))
    }

    /// - Parameters:
    ///   - isCancelled: her adımdan önce ve adım içinde denetlenir; true olunca sonraki adımlar başlamaz.
    ///   - stepStarted: bir adım başlarken çağrılır (ilerleme göstergesi).
    ///   - stepFinished: bir adım bittiğinde çağrılır (kısmi sonuç).
    static func run(home: String, runningBundleIDs: Set<String>, ownBundleID: String? = Bundle.main.bundleIdentifier,
                    steps: [SmartScanStep] = SmartScanStep.allCases, probe: PathProbe = .live,
                    isCancelled: @escaping () -> Bool = { false },
                    stepStarted: (SmartScanStep) -> Void = { _ in },
                    stepFinished: (SmartScanStepResult) -> Void = { _ in }) -> SmartScanResult {
        var out = SmartScanResult()
        for step in steps {
            if isCancelled() {
                out.wasCancelled = true
                break
            }
            stepStarted(step)
            guard let result = runStep(step, home: home, runningBundleIDs: runningBundleIDs, ownBundleID: ownBundleID,
                                       probe: probe, isCancelled: isCancelled) else {
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

    private static func runStep(_ step: SmartScanStep, home: String, runningBundleIDs: Set<String>, ownBundleID: String?,
                                probe: PathProbe, isCancelled: @escaping () -> Bool) -> SmartScanStepResult? {
        if step == .trash {
            let trash = CleanupScanner.trashSize(home: home, isCancelled: isCancelled)
            if isCancelled() { return nil }
            return SmartScanStepResult(step: .trash, state: trash.state, trashBytes: trash.bytes)
        }
        let out = CleanupScanner.scan(categories: step.categories, home: home, runningBundleIDs: runningBundleIDs,
                                      ownBundleID: ownBundleID, probe: probe, isCancelled: isCancelled)
        if isCancelled() { return nil }
        // Savunma: katalog yanlışlıkla riskli bir kategori döndürse bile adım dışına çıkanlar alınmaz.
        let allowed = Set(step.categories)
        let items = out.items.filter { allowed.contains($0.category) && $0.category.defaultSelected }
        let paths = Set(CleanupCatalog.roots(home: home, ownBundleID: ownBundleID).filter { allowed.contains($0.category) }.map(\.path))
        let states = paths.compactMap { out.states[$0] }
        let state: CleanupRootState = states.contains(.scanned) ? .scanned : states.contains(.noAccess) ? .noAccess : .missing
        return SmartScanStepResult(
            step: step, state: state, items: items,
            runningBrowsers: step == .browserCaches ? JunkRules.runningBrowsers(runningBundleIDs) : []
        )
    }
}
