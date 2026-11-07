import Foundation

/// Süreçler sayfasının sekmeleri (Görev Yöneticisi'nin sol gezinmesinin karşılığı).
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

    /// Canlı örnekleme (yalnızca bu sekmelerde çalışır; pil).
    var needsLiveSampling: Bool { self == .processes || self == .performance }
}
