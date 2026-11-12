import Foundation

/// Treemap'teki bir kutu: bir klasör, bir dosya ya da taranmayan korumalı bir klasör.
struct SpaceNode: Identifiable, Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case folder
        case file
        /// Erişim reddedildi (TCC); boyut bilinmez. Erişim akışı gösterilir.
        case locked(AccessReason)
        /// Bilerek taranmadı (başka uygulamaların verisi, iCloud/dosya sağlayıcıları).
        case skipped(AccessReason?)
    }

    var id: String { path }
    let path: String
    let kind: Kind
    let bytes: UInt64

    var name: String { (path as NSString).lastPathComponent }
    var isFolder: Bool { kind == .folder }
    /// Yerleşimde yer kaplar (boyutu bilinen).
    var isMeasured: Bool {
        switch kind {
        case .folder, .file: true
        case .locked, .skipped: false
        }
    }
}

struct SpaceLensScan: Sendable, Equatable {
    var nodes: [SpaceNode] = []
    var state: CleanupRootState = .scanned
    var cancelled = false
}

/// Bir klasörün doğrudan alt öğelerini ölçer. Klasör boyutları için mevcut `FolderScanner` kullanılır (her alt klasör ayrı:
/// böylece reddedilen/atlanan klasörler kutu olarak ayrılır ve ilerleme görünür). Salt okunurdur.
struct SpaceLensScanner: Sendable {
    /// `~/Library` altında başka uygulamaların verisi / dosya sağlayıcıları: açılmaz (izin penceresi çıkarmasın, iCloud inmesin).
    static let librarySkipNames: Set<String> = ["Containers", "Group Containers", "Mail", "Messages", "Safari", "Mobile Documents", "CloudStorage"]

    var home: String = NSHomeDirectory()
    var probe: PathProbe = .live
    var stat: StatProvider = .live

    /// Atlanan `~/Library` klasörü için erişim nedeni (iCloud/dosya sağlayıcıları için yok).
    static func skipReason(forName name: String) -> AccessReason? {
        switch name {
        case "Containers", "Group Containers": .appData
        case "Mail", "Messages", "Safari": .fullDiskAccess
        default: nil
        }
    }

    func isSkipped(_ path: String) -> Bool {
        let library = home + "/Library"
        return (path as NSString).deletingLastPathComponent == library && Self.librarySkipNames.contains((path as NSString).lastPathComponent)
    }

    func scan(path: String, isCancelled: @escaping () -> Bool = { false },
              progress: @escaping (_ done: Int, _ total: Int, _ name: String) -> Void = { _, _, _ in }) -> SpaceLensScan {
        let listing = FileWalker.listNames(path)
        if let error = listing.error {
            return SpaceLensScan(state: (error == EPERM || error == EACCES) ? .noAccess : .missing)
        }
        guard let dirStat = stat.lstat(path) else { return SpaceLensScan(state: .missing) }
        var nodes: [SpaceNode] = []
        let names = listing.names.sorted()
        for (index, name) in names.enumerated() {
            if isCancelled() { return SpaceLensScan(nodes: nodes, cancelled: true) }
            progress(index, names.count, name)
            let child = path + "/" + name
            guard let st = stat.lstat(child), !st.isSymlink, !st.isDataless else { continue }
            if st.isRegular {
                if st.allocated > 0 { nodes.append(SpaceNode(path: child, kind: .file, bytes: st.allocated)) }
            } else if st.isDirectory {
                if st.dev != dirStat.dev { continue }
                if isSkipped(child) {
                    nodes.append(SpaceNode(path: child, kind: .skipped(Self.skipReason(forName: name)), bytes: 0))
                    continue
                }
                switch probe.check(child) {
                case .missing: continue
                case .denied:
                    nodes.append(SpaceNode(path: child, kind: .locked(CleanupAccess.reason(for: child, home: home)), bytes: 0))
                case .ok:
                    var root = FolderScanRoot(path: child, maxDepth: 0)
                    if child == home + "/Library" { root.skipChildNames = Self.librarySkipNames }
                    guard let result = FolderScanner.scan(root: root, minRecordedBytes: .max, isCancelled: isCancelled) else { continue }
                    if isCancelled() { return SpaceLensScan(nodes: nodes, cancelled: true) }
                    nodes.append(SpaceNode(path: child, kind: .folder, bytes: result.totalBytes))
                }
            }
        }
        nodes.sort { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.path < $1.path }
        return SpaceLensScan(nodes: nodes)
    }
}
