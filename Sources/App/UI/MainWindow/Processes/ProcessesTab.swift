import Foundation

enum ProcessesTab: String, CapsuleTabItem {
    case processes, performance, browsers, history, startup, disk, cleanup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .processes: "İşlemler"
        case .performance: "Performans"
        case .browsers: "Tarayıcılar"
        case .history: "Uygulama geçmişi"
        case .startup: "Başlangıç"
        case .disk: "Disk"
        case .cleanup: "Temizlik"
        }
    }

    var systemImage: String {
        switch self {
        case .processes: "list.bullet.rectangle"
        case .performance: "gauge.with.dots.needle.50percent"
        case .browsers: "safari"
        case .history: "clock.arrow.circlepath"
        case .startup: "power"
        case .disk: "internaldrive"
        case .cleanup: "sparkles"
        }
    }

    var needsLiveSampling: Bool { self == .processes || self == .performance }
}
