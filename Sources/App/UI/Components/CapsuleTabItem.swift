import Foundation

/// `CapsuleTabBar` içinde gösterilen bir sekme: başlık ve SF Symbol simgesi.
protocol CapsuleTabItem: CaseIterable, Identifiable, Hashable {
    var title: String { get }
    var systemImage: String { get }
}

extension CapsuleTabItem {
    /// Sıradaki (+1) / önceki (-1) sekme; uçlarda yerinde kalır (←/→ ile gezinme).
    func neighbor(_ offset: Int) -> Self {
        let all = Array(Self.allCases)
        guard let index = all.firstIndex(of: self) else { return self }
        return all[min(max(index + offset, 0), all.count - 1)]
    }
}
