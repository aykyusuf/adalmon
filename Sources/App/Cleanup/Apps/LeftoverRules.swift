import Darwin
import Foundation

/// Bir uygulamanın kullanıcı Library'sinde artık bırakabildiği konumlar. Eşleşme yalnızca TAM bundle kimliği
/// (ya da uygulamanın TAM adı) ile yapılır; bulanık eşleşme yoktur.
enum LeftoverLocation: String, CaseIterable, Sendable {
    case applicationSupport, caches, preferences, byHost, savedState, httpStorages, webKit
    case logs, cookies, launchAgents, applicationScripts, containers, groupContainers

    var relativePath: String {
        switch self {
        case .applicationSupport: "Library/Application Support"
        case .caches: "Library/Caches"
        case .preferences: "Library/Preferences"
        case .byHost: "Library/Preferences/ByHost"
        case .savedState: "Library/Saved Application State"
        case .httpStorages: "Library/HTTPStorages"
        case .webKit: "Library/WebKit"
        case .logs: "Library/Logs"
        case .cookies: "Library/Cookies"
        case .launchAgents: "Library/LaunchAgents"
        case .applicationScripts: "Library/Application Scripts"
        case .containers: "Library/Containers"
        case .groupContainers: "Library/Group Containers"
        }
    }

    var title: String {
        switch self {
        case .applicationSupport: "Uygulama verileri"
        case .caches: "Önbellek"
        case .preferences, .byHost: "Tercihler"
        case .savedState: "Kayıtlı pencere durumu"
        case .httpStorages: "Ağ depolaması"
        case .webKit: "Web verisi"
        case .logs: "Kayıtlar"
        case .cookies: "Çerezler"
        case .launchAgents: "Başlangıç ajanı"
        case .applicationScripts: "Uygulama betikleri"
        case .containers: "Kapsayıcı"
        case .groupContainers: "Grup kapsayıcısı"
        }
    }

    var kind: CleanupKind { CleanupKind("apps.leftover.\(rawValue)") }

    init?(kind: CleanupKind) {
        let prefix = "apps.leftover."
        guard kind.rawValue.hasPrefix(prefix), let value = Self(rawValue: String(kind.rawValue.dropFirst(prefix.count))) else { return nil }
        self = value
    }

    /// Ada göre eşleşebilen konumlar (klasör adı uygulamanın adıdır).
    var matchesByAppName: Bool { self == .applicationSupport || self == .logs }

    /// Girdi adındaki bundle kimliği (yoksa nil). `.logs` yalnızca ada göre eşleşir.
    func embeddedID(in entry: String) -> String? {
        switch self {
        case .applicationSupport, .caches, .applicationScripts, .containers, .webKit:
            return entry
        case .httpStorages:
            return entry.droppingSuffix(".binarycookies") ?? entry
        case .preferences, .launchAgents:
            return entry.droppingSuffix(".plist")
        case .byHost:
            guard let base = entry.droppingSuffix(".plist"), let dot = base.lastIndex(of: ".") else { return nil }
            let uuid = String(base[base.index(after: dot)...])
            guard LeftoverRules.isUUIDShaped(uuid) else { return nil }
            return String(base[..<dot])
        case .savedState:
            return entry.droppingSuffix(".savedState")
        case .cookies:
            return entry.droppingSuffix(".binarycookies")
        case .groupContainers:
            guard let dot = entry.firstIndex(of: ".") else { return nil }
            // "group.<id>" ya da "<TAKIM KİMLİĞİ>.<id>": önek tek bileşen, noktasız.
            let prefix = entry[..<dot]
            let isTeamID = prefix.count == 10 && prefix.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
            guard prefix == "group" || isTeamID else { return nil }
            return String(entry[entry.index(after: dot)...])
        case .logs:
            return nil
        }
    }
}

extension String {
    fileprivate func droppingSuffix(_ suffix: String) -> String? {
        hasSuffix(suffix) && count > suffix.count ? String(dropLast(suffix.count)) : nil
    }
}

/// Uygulamanın eşleştirme kimliği: bundle kimliği ve tam adlar.
struct AppMatchKey: Sendable, Equatable {
    var bundleID: String
    var names: Set<String>
}

/// Library klasörlerinin ad dizini (bir kez okunur; her uygulama bunun üzerinden eşleşir).
struct LibraryIndex: Sendable {
    var home: String
    var entries: [LeftoverLocation: [String]]

    static func load(home: String, listing: (String) -> [String]? = { try? FileManager.default.contentsOfDirectory(atPath: $0) }) -> LibraryIndex {
        var out: [LeftoverLocation: [String]] = [:]
        for location in LeftoverLocation.allCases {
            out[location] = (listing(home + "/" + location.relativePath) ?? []).sorted()
        }
        return LibraryIndex(home: home, entries: out)
    }

    func path(_ location: LeftoverLocation, _ entry: String) -> String {
        home + "/" + location.relativePath + "/" + entry
    }
}

enum LeftoverRules {
    /// En küçük "reverse-DNS biçimli" kimlik: en az üç bileşen, ilki harf, hepsi [A-Za-z0-9_-].
    static func isReverseDNS(_ id: String) -> Bool {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, let first = parts.first, first.first?.isLetter == true else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { s in
                (s.value < 128) && (CharacterSet.alphanumerics.contains(s) || s == "_" || s == "-")
            }
        }
    }

    static func isUUIDShaped(_ s: String) -> Bool {
        guard s.count == 36 else { return false }
        for (i, c) in s.enumerated() {
            if [8, 13, 18, 23].contains(i) { if c != "-" { return false } } else if !c.isHexDigit { return false }
        }
        return true
    }

    /// Dokunulmaz kimlikler: Apple ve Adalmon'un kendisi.
    static func isProtectedID(_ id: String, ownIDs: [String]) -> Bool {
        id.hasPrefix("com.apple.") || id == "com.apple" || ownIDs.contains { id == $0 || id.hasPrefix($0 + ".") }
    }

    /// `entry`, bu uygulamanın artığı mı? `otherIDs`: başka kurulu uygulamaların kimlikleri (daha uzun kimlik sahiplenir).
    /// `otherNames`: kurulu DİĞER uygulamaların adları. Ada göre eşleşme (Application Support/<ad>, Logs/<ad>) yalnızca belirsizlik
    /// yoksa geçerlidir: girdi başka bir kurulu uygulamanın adı ya da kimliği de ise atlanır (başka uygulamanın verisi silinmesin).
    static func matches(_ location: LeftoverLocation, entry: String, app: AppMatchKey, otherIDs: Set<String>,
                        otherNames: Set<String> = []) -> Bool {
        if location.matchesByAppName, app.names.contains(entry) {
            let claimedByOther = otherNames.contains(entry) || (entry != app.bundleID && otherIDs.contains(entry))
            if !claimedByOther { return true }
        }
        if location == .launchAgents {
            guard let label = location.embeddedID(in: entry) else { return false }
            if label == app.bundleID { return true }
            guard label.hasPrefix(app.bundleID + ".") else { return false }
            return !otherIDs.contains { $0.count > app.bundleID.count && (label == $0 || label.hasPrefix($0 + ".")) }
        }
        guard let id = location.embeddedID(in: entry) else { return false }
        return id == app.bundleID
    }

    /// Bu uygulamanın tüm artıkları (bulunanlar lstat ile doğrulanır; sembolik bağlar atlanır).
    /// Ada göre (bundle kimliğiyle değil) eşleşmiş artık mı? Bunlar varsayılan seçili gelmez.
    static func isNameMatch(_ candidate: DeletionCandidate, app: AppMatchKey) -> Bool {
        (LeftoverLocation(kind: candidate.kind)?.matchesByAppName ?? false) && candidate.displayName != app.bundleID
    }

    static func leftovers(for app: AppMatchKey, index: LibraryIndex, otherIDs: Set<String>, otherNames: Set<String> = [],
                          isCancelled: @escaping () -> Bool = { false }) -> [DeletionCandidate] {
        var out: [DeletionCandidate] = []
        for location in LeftoverLocation.allCases {
            if isCancelled() { break }
            for entry in index.entries[location] ?? [] where matches(location, entry: entry, app: app, otherIDs: otherIDs, otherNames: otherNames) {
                if let candidate = makeCandidate(location: location, entry: entry, index: index, blocking: [app.bundleID]) {
                    out.append(candidate)
                }
            }
        }
        return out
    }

    /// Bir Library girdisinden silme adayı: düz dosya `.exactFile`, klasör `.directChild` (yalnız bu ad).
    static func makeCandidate(location: LeftoverLocation, entry: String, index: LibraryIndex, blocking: Set<String>,
                              isCancelled: @escaping () -> Bool = { false }) -> DeletionCandidate? {
        let path = index.path(location, entry)
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        let scope: DeletionScope
        let bytes: UInt64
        switch st.st_mode & S_IFMT {
        case S_IFREG:
            scope = .exactFile(allowed: [path])
            bytes = UInt64(max(0, st.st_blocks)) * 512
        case S_IFDIR:
            let root = DeletionRoot(path: index.home + "/" + location.relativePath, names: NameRule(only: [entry]))
            scope = .directChild(roots: [root])
            bytes = FolderScanner.scan(root: FolderScanRoot(path: path, maxDepth: 0), isCancelled: isCancelled)?.totalBytes ?? 0
        default:
            return nil // sembolik bağ ve özel dosyalar listelenmez
        }
        return DeletionCandidate(path: path, dev: st.st_dev, ino: st.st_ino, bytes: bytes, kind: location.kind, scope: scope,
                                 blockingBundleIDs: blocking, displayName: entry)
    }
}
