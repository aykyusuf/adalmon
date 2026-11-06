import Foundation

/// Genel bakıştaki "en çok kullananlar" satırı.
struct TopAppRow: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let bytes: UInt64
    let mobile: UInt64

    /// Bugünün en çok veri kullanan `limit` uygulaması.
    @MainActor
    static func top(_ today: [AppUsage], limit: Int = 5) -> [TopAppRow] {
        today.sorted { $0.bytes > $1.bytes }.prefix(limit).map {
            TopAppRow(id: $0.app, name: AppCatalog.shared.name(for: $0.app), bytes: $0.bytes, mobile: $0.mobileBytes)
        }
    }
}
