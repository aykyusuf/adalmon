import Foundation
import Observation

/// Birden çok tarayıcının bekleyen silmelerini sırayla çalıştırır. `BrowserPrivacyViewModel.perform` aynı anda yalnızca bir
/// işlem alır ve her bitişte yeniden tarar; bu yüzden her işlemden sonra model tamamen boşa düşene kadar beklenir (gözlem,
/// zamanlayıcı ya da yoklama yok). Onaylanan yöntem açıkça geçirilir (model her işlemden sonra `.trash`a döner).
@MainActor
enum PrivacyDeletionRun {
    /// Tüm işlemlerin sonuçları (sırayla). İptal edilirse ya da bir işlem başlamazsa kalanlar çalıştırılmaz.
    static func run(_ pendings: [PendingPrivacyDeletion], mode: DeleteMode, on vm: BrowserPrivacyViewModel) async -> [CleanupResult] {
        var collected: [CleanupResult] = []
        for pending in pendings {
            guard !Task.isCancelled else { break }
            await waitUntilIdle(vm)
            vm.perform(pending, mode: mode)
            // Meşgulken ya da başka nedenle başlamadıysa zincir durur (sessizce yanlış şey silinmez).
            guard vm.phase == .deleting else { break }
            await waitUntilIdle(vm)
            collected += vm.lastResult ?? []
        }
        return collected
    }

    static func waitUntilIdle(_ vm: BrowserPrivacyViewModel) async {
        while vm.phase != .idle, !Task.isCancelled {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                withObservationTracking { _ = vm.phase } onChange: { continuation.resume() }
            }
        }
    }
}

/// Bitti ekranı için silme özeti.
struct PrivacyFreed: Equatable {
    var count: Int
    var bytes: UInt64
    var skipped: [CleanupResult]
    var mode: DeleteMode

    init(count: Int, bytes: UInt64, skipped: [CleanupResult], mode: DeleteMode) {
        self.count = count
        self.bytes = bytes
        self.skipped = skipped
        self.mode = mode
    }

    init(results: [CleanupResult], mode: DeleteMode) {
        let removed = results.filter(\.isRemoved)
        self.init(count: removed.count, bytes: removed.reduce(UInt64(0)) { $0 + $1.candidate.bytes },
                  skipped: results.filter { !$0.isRemoved }, mode: mode)
    }
}
