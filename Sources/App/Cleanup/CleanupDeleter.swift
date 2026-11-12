import AppKit
import Darwin
import Foundation

struct CleanupResult: Sendable, Equatable {
    enum Outcome: Sendable, Equatable {
        /// Çöp Sepeti'ne taşındı (geri alınabilir).
        case trashed(to: URL?)
        /// Kalıcı olarak silindi.
        case deleted
        case skipped(CleanupDeleter.Refusal)
        case failed(String)
    }

    let candidate: DeletionCandidate
    let outcome: Outcome

    /// Öğe yerinden kalktı mı (Çöp'e ya da kalıcı).
    var isRemoved: Bool {
        switch outcome {
        case .trashed, .deleted: true
        case .skipped, .failed: false
        }
    }

    var reasonText: String? {
        switch outcome {
        case .trashed, .deleted: nil
        case .skipped(let r): r.message
        case .failed(let message): message
        }
    }
}

/// Tek silme noktası. Her aday, kendi kapsamına (`DeletionScope`) ve ortak denetimlere göre işlemden hemen önce yeniden doğrulanır;
/// dosya kimliği (dev/ino) silme çağrısından hemen önce bir kez daha denetlenir. Varsayılan Çöp Sepeti'dir; kalıcı silme yalnızca
/// `.permanent` ile, işlem başına. Her aday günlüğe bir satır yazar. Kalıcı silme çağrısı yalnızca bu dosyadadır.
struct CleanupDeleter: Sendable {
    enum Refusal: Error, Equatable, Sendable {
        case notAbsolute, symlink, missing, changed, notUnderAllowedRoot, isRoot, notDirectChild, nameNotAllowed, protectedPath, appRunning
        case rootNotAllowed, notAppBundle, appleApp, notListedFile, notRegularFile, ownData

        var message: String {
            switch self {
            case .notAbsolute: "Geçersiz yol"
            case .symlink: "Sembolik bağ"
            case .missing: "Artık yok"
            case .changed: "Taramadan sonra değişmiş"
            case .notUnderAllowedRoot: "İzinli klasörde değil"
            case .isRoot: "Kök klasörün kendisi"
            case .notDirectChild: "Doğrudan alt öğe değil"
            case .nameNotAllowed: "Korunan ad"
            case .protectedPath: "Korunan konum"
            case .appRunning: "Uygulama açık"
            case .rootNotAllowed: "Bu klasör seçilemez"
            case .notAppBundle: "Uygulama paketi değil"
            case .appleApp: "Apple uygulaması"
            case .notListedFile: "Listede olmayan dosya"
            case .notRegularFile: "Normal dosya değil"
            case .ownData: "Adalmon'un kendi dosyası"
            }
        }
    }

    static let systemTrash: @Sendable (URL) throws -> URL? = { url in
        var out: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &out)
        return out as URL?
    }

    static let systemRemove: @Sendable (URL) throws -> Void = { url in
        try FileManager.default.removeItem(at: url)
    }

    static let liveRunningBundleIDs: @Sendable () -> Set<String> = {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    /// Adalmon'un kendi paketi, destek klasörü ve önbelleği: bunlara (ve atalarına) asla dokunulmaz.
    static func defaultOwnPaths(home: String) -> [String] {
        var paths = [Bundle.main.bundlePath, AppEnvironment.supportDirectory.path]
        if let id = Bundle.main.bundleIdentifier { paths.append(home + "/Library/Caches/" + id) }
        return paths
    }

    var home: String
    /// Silme anında okunur (işlem başına bir kez).
    var runningBundleIDs: @Sendable () -> Set<String>
    var logURL: URL
    var ownPaths: [String]
    var moveToTrash: @Sendable (URL) throws -> URL?
    var removePermanently: @Sendable (URL) throws -> Void
    /// Test kancası: doğrulamadan sonra, son kimlik denetiminden önce çağrılır (yarış benzetimi için).
    var afterValidation: (@Sendable (DeletionCandidate) -> Void)?

    init(home: String = NSHomeDirectory(),
         runningBundleIDs: @escaping @Sendable () -> Set<String> = CleanupDeleter.liveRunningBundleIDs,
         logURL: URL = CleanupAuditLog.defaultURL,
         ownPaths: [String]? = nil,
         moveToTrash: @escaping @Sendable (URL) throws -> URL? = CleanupDeleter.systemTrash,
         removePermanently: @escaping @Sendable (URL) throws -> Void = CleanupDeleter.systemRemove,
         afterValidation: (@Sendable (DeletionCandidate) -> Void)? = nil) {
        self.home = home
        self.runningBundleIDs = runningBundleIDs
        self.logURL = logURL
        self.ownPaths = ownPaths ?? Self.defaultOwnPaths(home: home)
        self.moveToTrash = moveToTrash
        self.removePermanently = removePermanently
        self.afterValidation = afterValidation
    }

    // MARK: Doğrulama

    func validate(_ candidate: DeletionCandidate) -> Refusal? {
        validate(candidate, running: runningBundleIDs())
    }

    func validate(_ candidate: DeletionCandidate, running: Set<String>) -> Refusal? {
        let path = candidate.path
        // 1. Mutlak, temiz yol.
        guard path.hasPrefix("/"), path.count > 1 else { return .notAbsolute }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        if parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) { return .notAbsolute }
        // 2-4. Var, sembolik bağ değil, taramadaki nesneyle aynı.
        var st = stat()
        guard lstat(path, &st) == 0 else { return .missing }
        if (st.st_mode & S_IFMT) == S_IFLNK { return .symlink }
        guard st.st_dev == candidate.dev, st.st_ino == candidate.ino else { return .changed }
        // 5. Kanonik yol: ebeveynin gerçek yolu + ad (yol üzerindeki bağlar çözülür, yaprak bağ zaten reddedildi).
        let name = (path as NSString).lastPathComponent
        guard let parent = Self.realPath((path as NSString).deletingLastPathComponent),
              let canonHome = Self.realPath(home) else { return .notUnderAllowedRoot }
        let canonical = Self.components(parent) + [name]
        let homeParts = Self.components(canonHome)
        // 6. Kapsam.
        if let refusal = checkScope(candidate.scope, canonical: canonical, homeParts: homeParts, fileType: st.st_mode & S_IFMT) {
            return refusal
        }
        // 7. Sistem ağaçları ve korunan konumlar (kendisi ya da atası).
        if Self.isUnderSystemTree(canonical) { return .protectedPath }
        if Self.isProtected(canonical, homeParts: homeParts) { return .protectedPath }
        // 8. Adalmon'un kendisi.
        for own in ownPaths {
            let ownParts = Self.canonicalComponents(own)
            if canonical == ownParts || Self.isStrictDescendant(canonical, of: ownParts) || Self.isStrictDescendant(ownParts, of: canonical) {
                return .ownData
            }
        }
        // 9. Engelleyen uygulama açık.
        if !candidate.blockingBundleIDs.isDisjoint(with: running) { return .appRunning }
        return nil
    }

    private func checkScope(_ scope: DeletionScope, canonical: [String], homeParts: [String], fileType: mode_t) -> Refusal? {
        let name = canonical.last ?? ""
        switch scope {
        case .directChild(let roots):
            var matched: DeletionRoot?
            var sawRoot = false, sawDeeper = false
            for root in roots {
                guard let canonRoot = Self.realPath(root.path) else { continue }
                let rootParts = Self.components(canonRoot)
                guard Self.isStrictDescendant(rootParts, of: homeParts) else { continue }
                if canonical == rootParts { sawRoot = true }
                else if Array(canonical.dropLast()) == rootParts { matched = root; break }
                else if Self.isStrictDescendant(canonical, of: rootParts) { sawDeeper = true }
            }
            guard let root = matched else {
                if sawRoot { return .isRoot }
                if sawDeeper { return .notDirectChild }
                return .notUnderAllowedRoot
            }
            return root.names.allows(name) ? nil : .nameNotAllowed

        case .descendant(let roots, let allowlist):
            var matched = false, sawRoot = false, sawBadRoot = false
            for root in roots {
                guard let canonRoot = Self.realPath(root) else { continue }
                let rootParts = Self.components(canonRoot)
                if canonical == rootParts { sawRoot = true; continue }
                guard Self.isStrictDescendant(canonical, of: rootParts) else { continue }
                guard Self.isAllowedDescendantRoot(rootParts, homeParts: homeParts) else { sawBadRoot = true; continue }
                matched = true
                break
            }
            guard matched else {
                if sawRoot { return .isRoot }
                if sawBadRoot { return .rootNotAllowed }
                return .notUnderAllowedRoot
            }
            if let allowlist, !allowlist.contains(name) { return .nameNotAllowed }
            return nil

        case .appBundle:
            guard name.hasSuffix(".app"), name.count > 4, fileType == S_IFDIR else { return .notAppBundle }
            guard Self.isAllowedAppParent(Array(canonical.dropLast()), homeParts: homeParts) else { return .notUnderAllowedRoot }
            let plist = NSDictionary(contentsOfFile: Self.joined(canonical) + "/Contents/Info.plist")
            if let id = plist?["CFBundleIdentifier"] as? String, id.hasPrefix("com.apple.") { return .appleApp }
            return nil

        case .exactFile(let allowed):
            guard fileType == S_IFREG else { return .notRegularFile }
            let allowedParts = allowed.map { Self.canonicalComponents($0) }
            return allowedParts.contains(canonical) ? nil : .notListedFile
        }
    }

    // MARK: Silme

    /// Her adayı doğrular; geçerse kimliği son kez denetleyip seçilen yöntemle siler ve günlüğe yazar. Hata fırlatmaz.
    func delete(_ candidates: [DeletionCandidate], mode: DeleteMode) -> [CleanupResult] {
        guard !candidates.isEmpty else { return [] }
        let running = runningBundleIDs()
        var results: [CleanupResult] = []
        for candidate in candidates {
            if let refusal = validate(candidate, running: running) {
                results.append(CleanupResult(candidate: candidate, outcome: .skipped(refusal)))
                continue
            }
            afterValidation?(candidate)
            // Son kimlik denetimi: silme çağrısından hemen önce.
            if let refusal = Self.identityRefusal(candidate) {
                results.append(CleanupResult(candidate: candidate, outcome: .skipped(refusal)))
                continue
            }
            let url = URL(fileURLWithPath: candidate.path)
            do {
                switch mode {
                case .trash:
                    let to = try moveToTrash(url)
                    results.append(CleanupResult(candidate: candidate, outcome: .trashed(to: to)))
                case .permanent:
                    try removePermanently(url)
                    results.append(CleanupResult(candidate: candidate, outcome: .deleted))
                }
            } catch {
                results.append(CleanupResult(candidate: candidate, outcome: .failed((error as NSError).localizedDescription)))
            }
        }
        CleanupAuditLog.append(results, mode: mode, url: logURL)
        return results
    }

    static func identityRefusal(_ candidate: DeletionCandidate) -> Refusal? {
        var st = stat()
        guard lstat(candidate.path, &st) == 0 else { return .missing }
        if (st.st_mode & S_IFMT) == S_IFLNK { return .symlink }
        guard st.st_dev == candidate.dev, st.st_ino == candidate.ino else { return .changed }
        return nil
    }

    // MARK: Yol yardımcıları

    static func realPath(_ path: String) -> String? {
        guard let p = Darwin.realpath(path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }

    static func components(_ path: String) -> [String] {
        URL(fileURLWithPath: path).standardizedFileURL.pathComponents
    }

    static func joined(_ parts: [String]) -> String {
        parts.count <= 1 ? "/" : "/" + parts.dropFirst().joined(separator: "/")
    }

    /// Ebeveynin gerçek yolu + ad; ebeveyn yoksa yol olduğu gibi.
    static func canonicalComponents(_ path: String) -> [String] {
        let name = (path as NSString).lastPathComponent
        guard let parent = realPath((path as NSString).deletingLastPathComponent) else { return components(path) }
        return components(parent) + [name]
    }

    /// `path`, `ancestor`ın kesin alt yolu mu (bileşen bileşen; "Caches2" "Caches"in altı sayılmaz).
    static func isStrictDescendant(_ path: [String], of ancestor: [String]) -> Bool {
        path.count > ancestor.count && Array(path.prefix(ancestor.count)) == ancestor
    }

    /// Altındaki hiçbir şeye dokunulmayan sistem ağaçları.
    static let systemTrees: [[String]] = ["/System", "/usr", "/bin", "/sbin"].map(components)

    static func isUnderSystemTree(_ canonical: [String]) -> Bool {
        systemTrees.contains { canonical == $0 || isStrictDescendant(canonical, of: $0) }
    }

    /// Kendisi ya da atası silinemeyen konumlar.
    static func protectedPaths(homeParts: [String]) -> [[String]] {
        let system = ["/", "/System", "/Library", "/Applications", "/Users", "/usr", "/bin", "/sbin", "/private", "/opt", "/opt/homebrew", "/Volumes"]
            .map(components)
        let homeRelative = [
            "", "Library", "Library/Caches", "Library/Application Support", "Library/Developer",
            "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Applications",
            "Library/Mobile Documents", "Library/Containers", "Library/Group Containers", ".Trash",
        ]
        return system + homeRelative.map { rel in homeParts + rel.split(separator: "/").map(String.init) }
    }

    /// Korunan listedeki bir yol, `~/Library/<herhangi>` kök klasörü ya da `/Volumes/<birim>` (veya bunların atası) mı.
    static func isProtected(_ canonical: [String], homeParts: [String]) -> Bool {
        for protected in protectedPaths(homeParts: homeParts) where canonical == protected || isStrictDescendant(protected, of: canonical) {
            return true
        }
        let library = homeParts + ["Library"]
        if canonical.count == library.count + 1, isStrictDescendant(canonical, of: library) { return true }
        if canonical.count == 3, canonical[0] == "/", canonical[1] == "Volumes" { return true }
        return false
    }

    /// `.descendant` kökü: ev klasörü ya da altı (`~/Library`ın kendisi hariç) veya `/Volumes/<birim>` ya da altı.
    static func isAllowedDescendantRoot(_ rootParts: [String], homeParts: [String]) -> Bool {
        if rootParts == homeParts + ["Library"] { return false }
        if rootParts == homeParts || isStrictDescendant(rootParts, of: homeParts) { return true }
        return rootParts.count >= 3 && rootParts[0] == "/" && rootParts[1] == "Volumes"
    }

    /// `.app` paketinin üst klasörü: tam olarak `/Applications`, `/Applications/<tek alt klasör>` ya da `~/Applications`.
    static func isAllowedAppParent(_ parent: [String], homeParts: [String]) -> Bool {
        let apps = ["/", "Applications"]
        if parent == apps || parent == homeParts + ["Applications"] { return true }
        return parent.count == 3 && Array(parent.prefix(2)) == apps && !parent[2].hasSuffix(".app")
    }
}
