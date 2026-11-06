import Foundation

/// Bir uygulamanın alan adı grubu ve baytı.
struct HistoryDomainBytes: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let bytes: UInt64
}
