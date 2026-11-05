import Foundation
import Observation

/// Bir uygulamanın (ve alan adlarının) kullanım özeti.
struct AppUsage: Identifiable, Sendable, Equatable {
    var id: String { app }
    var app: String
    var bytes: UInt64
    var mobileBytes: UInt64
    /// Grup adı → byte, büyükten küçüğe.
    var domains: [(name: String, bytes: UInt64)]

    static func == (a: AppUsage, b: AppUsage) -> Bool {
        a.app == b.app && a.bytes == b.bytes && a.mobileBytes == b.mobileBytes && a.domains.map(\.name) == b.domains.map(\.name)
    }
}

/// Filtreden gelen kovaları toplar: son 60 sn, bugün (uygulama × alan adı), mobil/Wi-Fi ayrımı.
@MainActor @Observable
final class UsageEngine {
    /// Son 60 saniyede en çok harcayanlar.
    private(set) var last60: [AppUsage] = []
    /// Bugün en çok harcayanlar.
    private(set) var today: [AppUsage] = []
    /// Bugün uygulamalara yazılan mobil trafik.
    private(set) var attributedMobileToday: UInt64 = 0
    /// Proxy'nin (SpoofDPI) bugünkü dış trafiği — kontrol amaçlı.
    private(set) var proxyEgressToday: UInt64 = 0

    private struct Totals { var bytes: UInt64 = 0; var mobile: UInt64 = 0; var hosts: [String: UInt64] = [:] }

    /// Saniye başına kova halkası: her eleman app → (byte, host → byte).
    private var ring: [[String: Totals]] = Array(repeating: [:], count: 60)
    private var ringIndex = 0
    private var todayTotals: [String: Totals] = [:]
    private var dayKey = UsageStore.dayKey()
    private var pending: [String: UsageStore.Row] = [:]
    private let store: UsageStore

    init(store: UsageStore) {
        self.store = store
    }

    func loadToday() async {
        let rows = await store.rows(day: dayKey)
        var totals: [String: Totals] = [:]
        var mobile: UInt64 = 0
        for r in rows {
            let b = r.bytesIn + r.bytesOut
            totals[r.app, default: Totals()].bytes += b
            if r.mobile { totals[r.app, default: Totals()].mobile += b; mobile += b }
            totals[r.app, default: Totals()].hosts[DomainGrouper.group(r.host), default: 0] += b
        }
        todayTotals = totals
        attributedMobileToday = mobile
        today = Self.summaries(totals, limit: 30)
    }

    /// Her saniye çağrılır; çekilen kovalar o saniyenin trafiği sayılır.
    /// - Parameter seconds: Son çağrıdan beri geçen saniye; halka o kadar kaydırılır, pencere hep 60 sn kalır.
    func ingest(_ buckets: [UsageBucket], seconds: Int = 1) {
        rollDayIfNeeded()
        for _ in 0..<min(max(1, seconds), ring.count) {
            ringIndex = (ringIndex + 1) % ring.count
            ring[ringIndex] = [:]
        }

        for b in buckets {
            let bytes = b.bytesIn + b.bytesOut
            if b.kind == .proxyEgress { proxyEgressToday += bytes; continue }
            let host = DomainGrouper.group(b.host)

            ring[ringIndex][b.app, default: Totals()].bytes += bytes
            ring[ringIndex][b.app, default: Totals()].hosts[host, default: 0] += bytes

            todayTotals[b.app, default: Totals()].bytes += bytes
            todayTotals[b.app, default: Totals()].hosts[host, default: 0] += bytes
            if b.expensive {
                todayTotals[b.app, default: Totals()].mobile += bytes
                attributedMobileToday += bytes
            }

            let key = "\(b.app)\u{1F}\(b.host)\u{1F}\(b.expensive)"
            var row = pending[key] ?? UsageStore.Row(app: b.app, host: b.host, mobile: b.expensive, bytesIn: 0, bytesOut: 0)
            row.bytesIn += b.bytesIn
            row.bytesOut += b.bytesOut
            pending[key] = row
        }

        var window: [String: Totals] = [:]
        for second in ring {
            for (app, t) in second {
                window[app, default: Totals()].bytes += t.bytes
                for (h, v) in t.hosts { window[app, default: Totals()].hosts[h, default: 0] += v }
            }
        }
        last60 = Self.summaries(window, limit: 6)
        if !buckets.isEmpty { today = Self.summaries(todayTotals, limit: 30) }
    }

    /// Bekleyen satırları diske yazar (birkaç saniyede bir).
    func flush() async {
        guard !pending.isEmpty else { return }
        let rows = Array(pending.values)
        pending.removeAll(keepingCapacity: true)
        await store.add(day: dayKey, rows: rows)
    }

    private func rollDayIfNeeded() {
        let now = UsageStore.dayKey()
        guard now != dayKey else { return }
        let rows = Array(pending.values)
        let oldDay = dayKey
        pending.removeAll()
        Task { [store] in await store.add(day: oldDay, rows: rows) }
        dayKey = now
        todayTotals = [:]
        attributedMobileToday = 0
        proxyEgressToday = 0
        today = []
    }

    private static func summaries(_ totals: [String: Totals], limit: Int) -> [AppUsage] {
        totals.filter { $0.value.bytes > 0 }
            .sorted { $0.value.bytes > $1.value.bytes }
            .prefix(limit)
            .map { app, t in
                let doms = t.hosts.sorted { $0.value > $1.value }.prefix(5).map { (name: $0.key, bytes: $0.value) }
                return AppUsage(app: app, bytes: t.bytes, mobileBytes: t.mobile, domains: Array(doms))
            }
    }
}
