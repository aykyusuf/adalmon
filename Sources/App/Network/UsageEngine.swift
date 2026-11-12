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
    /// Son 60 saniyede uygulama başına toplam byte (sınırsız; Süreçler tablosunun "Ağ" sütunu için).
    private(set) var last60Bytes: [String: UInt64] = [:]
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
    private let calendar: Calendar
    private var dayKey: String
    private var pending: [String: UsageStore.Row] = [:]
    /// Saatlik tablo için bekleyen satırlar (saat başı × uygulama × gruplanmış alan adı × mobil).
    private var pendingHourly: [HourlyKey: UsageStore.HourlyRow] = [:]
    private struct HourlyKey: Hashable { var hour: Int; var app: String; var domain: String; var mobile: Bool }
    private let store: UsageStore
    /// Canlı liste (60 sn … 1 sa) için bellek içi geçmiş; gözlem bildirmez, görünüm görünürken `liveRows` ile okunur.
    @ObservationIgnored private var live = LiveUsageHistory()

    init(store: UsageStore, calendar: Calendar = UsageStore.keyCalendar) {
        self.store = store
        self.calendar = calendar
        self.dayKey = UsageStore.dayKey(calendar: calendar)
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
    func ingest(_ buckets: [UsageBucket], seconds: Int = 1, now: Date = .now) {
        rollDayIfNeeded(now: now)
        let hour = Int(now.timeIntervalSince1970) / 3600 * 3600
        for _ in 0..<min(max(1, seconds), ring.count) {
            ringIndex = (ringIndex + 1) % ring.count
            ring[ringIndex] = [:]
        }
        live.advance(seconds: seconds)
        live.prune(nowMinute: Int(now.timeIntervalSince1970) / 60)

        for b in buckets {
            let bytes = b.bytesIn + b.bytesOut
            if b.kind == .proxyEgress { proxyEgressToday += bytes; continue }
            let host = DomainGrouper.group(b.host)
            live.record(app: b.app, bytesIn: b.bytesIn, bytesOut: b.bytesOut, mobile: b.expensive, minute: b.minute)

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

            let domain = b.host.isEmpty ? "" : host
            let hk = HourlyKey(hour: hour, app: b.app, domain: domain, mobile: b.expensive)
            var hr = pendingHourly[hk] ?? UsageStore.HourlyRow(hour: hour, app: b.app, domain: domain.isEmpty ? nil : domain,
                                                               mobile: b.expensive, bytesIn: 0, bytesOut: 0)
            hr.bytesIn += b.bytesIn
            hr.bytesOut += b.bytesOut
            pendingHourly[hk] = hr
        }

        // Boşta (kova yok, halka boş) 60 sn'lik pencereyi yeniden toplamanın anlamı yok.
        if buckets.isEmpty, last60.isEmpty, ring.allSatisfy(\.isEmpty) { return }
        var window: [String: Totals] = [:]
        for second in ring {
            for (app, t) in second {
                window[app, default: Totals()].bytes += t.bytes
                for (h, v) in t.hosts { window[app, default: Totals()].hosts[h, default: 0] += v }
            }
        }
        // @Observable her atamada bildirir; değişmediyse atama yapma (gözlemci görünümler boşuna yeniden çizilmesin).
        let newLast60 = Self.summaries(window, limit: 6)
        if newLast60 != last60 { last60 = newLast60 }
        let newBytes = window.mapValues(\.bytes)
        if newBytes != last60Bytes { last60Bytes = newBytes }
        if !buckets.isEmpty {
            let newToday = Self.summaries(todayTotals, limit: 30)
            if newToday != today { today = newToday }
        }
    }

    /// Canlı liste satırları (bkz. `LiveUsageHistory.rows`). Yalnızca görünür görünüm çağırır; ölçüm adımına ek iş yok.
    func liveRows(range: LiveRange, interface: LiveInterface, limit: Int? = nil, now: Date = .now) -> [LiveAppUsage] {
        live.rows(range: range, interface: interface, nowMinute: Int(now.timeIntervalSince1970) / 60, limit: limit)
    }

    /// Bugünün uygulama toplamları canlı liste biçiminde (anlık hız son saniyelerden). ↓/↑ ayrımı yoktur: hepsi `down`'da.
    func todayRows(interface: LiveInterface, now: Date = .now) -> [LiveAppUsage] {
        let rates = liveRows(range: .sec60, interface: interface, now: now).reduce(into: [String: UInt64]()) { $0[$1.app] = $1.rate }
        return LiveAppUsage.today(today, interface: interface, rates: rates)
    }

    /// Bekleyen satırları diske yazar (birkaç saniyede bir).
    func flush() async {
        guard !pending.isEmpty || !pendingHourly.isEmpty else { return }
        let rows = Array(pending.values)
        let hourly = Array(pendingHourly.values)
        pending.removeAll(keepingCapacity: true)
        pendingHourly.removeAll(keepingCapacity: true)
        await store.add(day: dayKey, rows: rows, hourly: hourly)
    }

    private func rollDayIfNeeded(now date: Date) {
        let now = UsageStore.dayKey(date, calendar: calendar)
        guard now != dayKey else { return }
        let rows = Array(pending.values)
        let hourly = Array(pendingHourly.values)
        let oldDay = dayKey
        pending.removeAll()
        pendingHourly.removeAll()
        Task { [store] in await store.add(day: oldDay, rows: rows, hourly: hourly) }
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
                let doms = DomainGrouper.displayOrder(t.hosts.map { (name: $0.key, bytes: $0.value) }, limit: 5,
                                                      name: \.name, bytes: \.bytes)
                return AppUsage(app: app, bytes: t.bytes, mobileBytes: t.mobile, domains: doms)
            }
    }
}
