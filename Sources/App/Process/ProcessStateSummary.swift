import Foundation

/// Bir satırın süreçlerinin toplu durumu: hepsi askıda mı / hepsi verimlilik modunda mı. Saf mantık.
struct ProcessStateSummary: Equatable, Sendable {
    var isSuspended = false
    var isEfficient = false

    struct Item: Equatable, Sendable {
        var isOwned: Bool
        var isStopped: Bool
        var isEfficient: Bool
    }

    /// Yalnızca sahibi biz olan süreçler sayılır (başkalarının durumu okunamaz); hiç yoksa ikisi de false.
    init(items: [Item]) {
        let owned = items.filter(\.isOwned)
        guard !owned.isEmpty else { return }
        isSuspended = owned.allSatisfy(\.isStopped)
        isEfficient = owned.allSatisfy(\.isEfficient)
    }

    init() {}
}
