import Foundation

/// Aynı bundle kimliğine ait, uygulaması bulunamayan Library girdileri.
struct OrphanGroup: Identifiable, Sendable, Equatable {
    let bundleID: String
    var items: [DeletionCandidate]

    var id: String { bundleID }
    var bytes: UInt64 { items.reduce(0) { $0 + $1.bytes } }
}

/// Yetim dosya bulucu. Bir girdi ancak şu koşulların hepsi sağlanırsa yetimdir:
/// kimliği reverse-DNS biçimli, `com.apple.*`/Adalmon değil, kurulu/çalışan bir uygulamaya ait değil,
/// kimliğin (noktalı) üst kimliklerinden biri de kurulu ya da `resolver` ile çözülebilir değil.
/// Küçük klasörler (< `minFolderBytes`) listelenmez; dosyalar listelenir. Hiçbiri varsayılan seçili değildir.
enum OrphanFinder {
    static let minFolderBytes: UInt64 = 1 << 20

    /// Bu konumlar yetim taramasına girmez: `logs` yalnızca ada göre eşleşir; `launchAgents` Homebrew vb. hizmet
    /// plist'lerini yanlış yetim sayardı (kırık ajanlar Başlangıç bölümünün işi).
    static let excludedLocations: Set<LeftoverLocation> = [.logs, .launchAgents]

    static func find(index: LibraryIndex, installedIDs: Set<String>, ownIDs: [String],
                     resolver: @Sendable (String) -> Bool, minFolderBytes: UInt64 = minFolderBytes,
                     isCancelled: @escaping () -> Bool = { false }) -> [OrphanGroup] {
        var resolved: [String: Bool] = [:]
        func known(_ id: String) -> Bool {
            if installedIDs.contains(id) { return true }
            if let cached = resolved[id] { return cached }
            let answer = resolver(id)
            resolved[id] = answer
            return answer
        }
        /// Kimliğin kendisi ya da en az üç bileşenli herhangi bir üst kimliği biliniyorsa sahipli sayılır.
        func isOwned(_ id: String) -> Bool {
            let parts = id.split(separator: ".").map(String.init)
            for length in stride(from: parts.count, through: 3, by: -1) where known(parts.prefix(length).joined(separator: ".")) {
                return true
            }
            return false
        }

        var groups: [String: [DeletionCandidate]] = [:]
        for location in LeftoverLocation.allCases where !excludedLocations.contains(location) {
            for entry in index.entries[location] ?? [] {
                if isCancelled() { return [] }
                guard let id = location.embeddedID(in: entry), LeftoverRules.isReverseDNS(id),
                      !LeftoverRules.isProtectedID(id, ownIDs: ownIDs), !isOwned(id) else { continue }
                guard let candidate = LeftoverRules.makeCandidate(location: location, entry: entry, index: index, blocking: [id],
                                                                  isCancelled: isCancelled) else { continue }
                if case .directChild = candidate.scope, candidate.bytes < minFolderBytes { continue }
                groups[id, default: []].append(candidate)
            }
        }
        return groups.map { OrphanGroup(bundleID: $0.key, items: $0.value.sorted { $0.path < $1.path }) }
            .sorted { ($0.bytes, $1.bundleID) > ($1.bytes, $0.bundleID) }
    }
}
