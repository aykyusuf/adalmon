import Foundation

enum ProcessesTab: String, CapsuleTabItem {
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
}
