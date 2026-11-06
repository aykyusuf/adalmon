import Foundation

/// Seçili saat/günde bir uygulamanın kullanımı.
struct HistoryAppBytes: Identifiable, Equatable, Sendable {
    var id: String { app }
    let app: String
    let bytes: UInt64
    let mobile: UInt64
}
