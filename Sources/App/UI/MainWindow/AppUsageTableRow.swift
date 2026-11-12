import Foundation

/// "Ağ kullanımı" tablosunun bir satırı: `AppUsage` + engel/sınır durumu, sıralanabilir alanlarla.
struct AppUsageTableRow: Identifiable, Sendable {
    let id: String
    let name: String
    let domains: [String]
    let total: UInt64
    let mobile: UInt64
    let isBlocked: Bool
    let limit: AppLimit?

    /// Tablo sıralaması için: boş < sınırlı < engelli.
    var statusRank: Int { isBlocked ? 2 : (limit != nil ? 1 : 0) }
    var domainText: String { domains.prefix(2).joined(separator: ", ") }

    /// "↓ 1,0 MB/s · ↑ 500 KB/s" (yalnızca tanımlı yönler).
    var limitText: String? {
        guard let limit else { return nil }
        var parts: [String] = []
        // Menü ve rozetle aynı (1024 tabanlı) birim: 500 KB/s seçilen sınır "512 KB/s" görünmesin.
        if let d = limit.downBytesPerSec, d > 0 { parts.append("↓ \(AppModel.rateText(d))") }
        if let u = limit.upBytesPerSec, u > 0 { parts.append("↑ \(AppModel.rateText(u))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return name.localizedStandardContains(q) || domains.contains { $0.localizedStandardContains(q) }
    }
}

extension AppUsageTableRow {
    @MainActor
    init(usage: AppUsage, blocked: [String], limits: [String: AppLimit]) {
        self.init(id: usage.app, name: AppCatalog.shared.name(for: usage.app), domains: usage.domains.map(\.name),
                  total: usage.bytes, mobile: usage.mobileBytes, isBlocked: blocked.contains(usage.app),
                  limit: limits[usage.app].flatMap { $0.hasCap ? $0 : nil })
    }
}
