import Foundation

/// Temizlik sayfasının alt bölümleri (sıra, sayfadaki liste sırasıdır).
enum CleanupSubsection: String, CaseIterable, Identifiable {
    case smartScan, junk, dev, uninstaller, largeOld, duplicates, privacy, spaceLens, startup, maintenance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartScan: "Akıllı tarama"
        case .junk: "Sistem çöpü"
        case .dev: "Geliştirici"
        case .uninstaller: "Kaldırıcı"
        case .largeOld: "Büyük & eski"
        case .duplicates: "Kopyalar"
        case .privacy: "Gizlilik"
        case .spaceLens: "Yer kaplayanlar"
        case .startup: "Başlangıç"
        case .maintenance: "Bakım"
        }
    }

    var symbol: String {
        switch self {
        case .smartScan: "wand.and.stars"
        case .junk: "trash"
        case .dev: "hammer"
        case .uninstaller: "app.badge.checkmark"
        case .largeOld: "doc.badge.clock"
        case .duplicates: "square.on.square"
        case .privacy: "hand.raised"
        case .spaceLens: "chart.pie"
        case .startup: "power"
        case .maintenance: "wrench.and.screwdriver"
        }
    }
}
