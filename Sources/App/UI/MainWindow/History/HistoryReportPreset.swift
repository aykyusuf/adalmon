import Foundation

/// Rapor kartındaki hızlı dönem seçimleri.
enum HistoryReportPreset: String, CaseIterable, Identifiable, Sendable {
    case yesterday, lastWeek, thisMonth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yesterday: "Dün"
        case .lastWeek: "Son 7 gün"
        case .thisMonth: "Bu ay"
        }
    }
}
