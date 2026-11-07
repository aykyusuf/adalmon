import Foundation

enum ProcessesTab: String, CaseIterable, Identifiable, Hashable {
    case processes, performance, history, startup, disk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .processes: "İşlemler"
        case .performance: "Performans"
        case .history: "Uygulama geçmişi"
        case .startup: "Başlangıç"
        case .disk: "Disk"
        }
    }

    var systemImage: String {
        switch self {
        case .processes: "list.bullet.rectangle"
        case .performance: "gauge.with.dots.needle.50percent"
        case .history: "clock.arrow.circlepath"
        case .startup: "power"
        case .disk: "internaldrive"
        }
    }

    var needsLiveSampling: Bool { self == .processes || self == .performance }

    /// Sıradaki (+1) / önceki (-1) sekme; uçlarda yerinde kalır (←/→ ile gezinme).
    func neighbor(_ offset: Int) -> ProcessesTab {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return self }
        return all[min(max(index + offset, 0), all.count - 1)]
    }
}
