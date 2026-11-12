import Foundation
import Observation
import os

private let usageLog = Logger(subsystem: AdalmonIdentity.appBundleID, category: "usage")

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
    /// Arayüz sınırını aştığı için mobilden düşülen toplam byte (tanı sayacı; uygulama açıkken birikir).
    @ObservationIgnored private(set) var droppedMobileExcess: UInt64 = 0

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
    /// - Parameter mobileCap: Bu adımda fiziksel arayüzden geçen mobil byte; uygulamalara yazılan mobil toplam bunu aşamaz.
    ///   `nil` = sınır yok (testler / arayüz ölçümü olmayan çağrılar).
    func ingest(_ buckets: [UsageBucket], seconds: Int = 1, now: Date = .now, mobileCap: UInt64? = nil) {
        rollDayIfNeeded(now: now)
        let hour = Int(now.timeIntervalSince1970) / 3600 * 3600
        for _ in 0..<min(max(1, seconds), ring.count) {
            ringIndex = (ringIndex + 1) % ring.count
            ring[ringIndex] = [:]
        }
        live.advance(seconds: seconds)
        live.prune(nowMinute: Int(now.timeIntervalSince1970) / 60)

        let mobileShare = Self.mobileShares(buckets, cap: mobileCap)
        if mobileShare.dropped > 0 {
            droppedMobileExcess += mobileShare.dropped
            usageLog.debug("mobile cap: dropped \(mobileShare.dropped, privacy: .public) B (total \(self.droppedMobileExcess, privacy: .public) B)")
        }

        for (i, b) in buckets.enumerated() {
            let bytes = b.bytesIn + b.bytesOut
            if b.kind == .proxyEgress { proxyEgressToday += bytes; continue }
            let host = DomainGrouper.group(b.host)
            let mobile = mobileShare.bytes[i]

            ring[ringIndex][b.app, default: Totals()].bytes += bytes
            ring[ringIndex][b.app, default: Totals()].mobile += mobile
            ring[ringIndex][b.app, default: Totals()].hosts[host, default: 0] += bytes

            todayTotals[b.app, default: Totals()].bytes += bytes
            todayTotals[b.app, default: Totals()].hosts[host, default: 0] += bytes
            if mobile > 0 {
                todayTotals[b.app, default: Totals()].mobile += mobile
                attributedMobileToday += mobile
            }

            // Kova mobil ve mobil olmayan iki parçaya bölünür (↓/↑ oranı korunur); satırlar parça başına yazılır.
            let mobileIn = bytes == 0 ? 0 : min(UInt64((Double(b.bytesIn) * Double(mobile) / Double(bytes)).rounded()), b.bytesIn, mobile)
            let mobileOut = min(mobile - mobileIn, b.bytesOut)
            for (isMobile, bIn, bOut) in [(true, mobileIn, mobileOut), (false, b.bytesIn - mobileIn, b.bytesOut - mobileOut)] {
                guard bIn + bOut > 0 else { continue }
                live.record(app: b.app, bytesIn: bIn, bytesOut: bOut, mobile: isMobile, minute: b.minute)

                let key = "\(b.app)\u{1F}\(b.host)\u{1F}\(isMobile)"
                var row = pending[key] ?? UsageStore.Row(app: b.app, host: b.host, mobile: isMobile, bytesIn: 0, bytesOut: 0)
                row.bytesIn += bIn
                row.bytesOut += bOut
                pending[key] = row

                let domain = b.host.isEmpty ? "" : host
                let hk = HourlyKey(hour: hour, app: b.app, domain: domain, mobile: isMobile)
                var hr = pendingHourly[hk] ?? UsageStore.HourlyRow(hour: hour, app: b.app, domain: domain.isEmpty ? nil : domain,
                                                                   mobile: isMobile, bytesIn: 0, bytesOut: 0)
                hr.bytesIn += bIn
                hr.bytesOut += bOut
                pendingHourly[hk] = hr
            }
        }

        // Boşta (kova yok, halka boş) 60 sn'lik pencereyi yeniden toplamanın anlamı yok.
        if buckets.isEmpty, last60.isEmpty, ring.allSatisfy(\.isEmpty) { return }
        var window: [String: Totals] = [:]
        for second in ring {
            for (app, t) in second {
                window[app, default: Totals()].bytes += t.bytes
                window[app, default: Totals()].mobile += t.mobile
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

    /// Kova başına (aynı sırayla) uygulamaya yazılacak mobil byte.
    /// - `.proxied` (uygulama → yerel proxy, loopback): kendi `expensive` bayrağı genel yol bayrağıdır, güvenilmez.
    ///   Bu penceredeki mobil `.proxyEgress` (Mac'ten gerçekten çıkan) byte'ları, proxied kovalara loopback byte'ları
    ///   oranında dağıtılır: toplam = min(proxied, mobil egress). Egress yoksa proxied mobil değildir.
    /// - Diğerleri: `expensive` ise tamamı mobil. `.proxyEgress` kovaları 0 alır.
    /// - `cap` verilirse toplam mobil onu aşamaz; aşan kısım oranla düşülür (`dropped`).
    nonisolated static func mobileShares(_ buckets: [UsageBucket], cap: UInt64?) -> (bytes: [UInt64], dropped: UInt64) {
        var shares = [UInt64](repeating: 0, count: buckets.count)
        var egressMobile: UInt64 = 0
        var proxied: [Int] = []
        for (i, b) in buckets.enumerated() {
            switch b.kind {
            case .proxyEgress: if b.expensive { egressMobile += b.bytesIn + b.bytesOut }
            case .proxied: proxied.append(i)
            case .direct: if b.expensive { shares[i] = b.bytesIn + b.bytesOut }
            }
        }
        let proxiedTotal = proxied.reduce(UInt64(0)) { $0 + buckets[$1].bytesIn + buckets[$1].bytesOut }
        let proxiedMobile = min(proxiedTotal, egressMobile)
        for (k, part) in distribute(proxiedMobile, weights: proxied.map { buckets[$0].bytesIn + buckets[$0].bytesOut }).enumerated() {
            shares[proxied[k]] = part
        }
        let total = shares.reduce(0, +)
        guard let cap, total > cap else { return (shares, 0) }
        let indices = shares.indices.filter { shares[$0] > 0 }
        for (k, part) in distribute(cap, weights: indices.map { shares[$0] }).enumerated() { shares[indices[k]] = part }
        return (shares, total - cap)
    }

    /// `total`'ı ağırlıklara oranla böler (toplam tam `total`; yuvarlama artığı en büyük kesirlilere).
    nonisolated static func distribute(_ total: UInt64, weights: [UInt64]) -> [UInt64] {
        let sum = weights.reduce(0, +)
        guard sum > 0, total > 0 else { return weights.map { _ in 0 } }
        var parts: [UInt64] = []
        var remainders: [(index: Int, rem: UInt64)] = []
        for (i, w) in weights.enumerated() {
            let product = w.multipliedFullWidth(by: total)
            let (q, r) = sum.dividingFullWidth((high: product.high, low: product.low))
            parts.append(q)
            remainders.append((i, r))
        }
        var left = total - parts.reduce(0, +)
        for (i, _) in remainders.sorted(by: { $0.rem != $1.rem ? $0.rem > $1.rem : $0.index < $1.index }) where left > 0 {
            parts[i] += 1
            left -= 1
        }
        return parts
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
