import Foundation

/// Seçili çubuğun (saat ya da gün) en çok kullanan uygulamalarını ve bir uygulamanın alan adlarını okur.
struct HistoryDetailLoader: Sendable {
    let store: UsageStore
    let target: HistoryBar.Target

    func topApps(limit: Int = 8) async -> [HistoryAppBytes] {
        switch target {
        case .hour(let hour):
            return await store.topApps(hour: hour, limit: limit).map { HistoryAppBytes(app: $0.app, bytes: $0.bytes, mobile: $0.mobileBytes) }
        case .day(let day):
            var byApp: [String: (bytes: UInt64, mobile: UInt64)] = [:]
            for row in await store.rows(day: day) {
                let b = row.bytesIn + row.bytesOut
                byApp[row.app, default: (0, 0)].bytes += b
                if row.mobile { byApp[row.app, default: (0, 0)].mobile += b }
            }
            return byApp.sorted { $0.value.bytes != $1.value.bytes ? $0.value.bytes > $1.value.bytes : $0.key < $1.key }
                .prefix(limit).map { HistoryAppBytes(app: $0.key, bytes: $0.value.bytes, mobile: $0.value.mobile) }
        case .days(let from, let to):
            return await store.topApps(fromDay: from, toDay: to, limit: limit).map { HistoryAppBytes(app: $0.app, bytes: $0.bytes, mobile: $0.mobileBytes) }
        }
    }

    func domains(app: String, limit: Int = 6) async -> [HistoryDomainBytes] {
        switch target {
        case .hour(let hour):
            let rows = await store.hourlyDomains(app: app, hour: hour)
            return rows.prefix(limit).map { HistoryDomainBytes(name: $0.domain ?? "Diğer", bytes: $0.bytes) }
        case .day(let day):
            return await store.topDomains(app: app, fromDay: day, toDay: day, limit: limit).map { HistoryDomainBytes(name: $0.name, bytes: $0.bytes) }
        case .days(let from, let to):
            return await store.topDomains(app: app, fromDay: from, toDay: to, limit: limit).map { HistoryDomainBytes(name: $0.name, bytes: $0.bytes) }
        }
    }
}
