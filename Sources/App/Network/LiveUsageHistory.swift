import Foundation

/// Canlı uygulama listesinin zaman aralığı (rawValue = saniye).
enum LiveRange: Int, CaseIterable, Identifiable, Sendable {
    /// `now`: anlık hız (son `LiveUsageHistory.rateWindow` saniyenin ortalaması, saniye başına).
    case now = 5, sec60 = 60, min5 = 300, min15 = 900, min30 = 1_800, hour1 = 3_600

    var id: Int { rawValue }
    var seconds: Int { rawValue }
    /// Dakika kovası sayısı (60 sn için 1).
    var minutes: Int { rawValue / 60 }

    var title: String {
        switch self {
        case .now: "Anlık"
        case .sec60: "60 sn"
        case .min5: "5 dk"
        case .min15: "15 dk"
        case .min30: "30 dk"
        case .hour1: "1 sa"
        }
    }

    /// "son 15 dakikada" gibi cümle içi biçim.
    var phrase: String {
        switch self {
        case .now: "şu an (saniyede)"
        case .sec60: "son 60 saniyede"
        case .min5: "son 5 dakikada"
        case .min15: "son 15 dakikada"
        case .min30: "son 30 dakikada"
        case .hour1: "son 1 saatte"
        }
    }
}

/// Canlı listenin ağ süzgeci.
enum LiveInterface: String, CaseIterable, Identifiable, Sendable {
    case all, wifi, mobile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Tümü"
        case .wifi: "Wi‑Fi"
        case .mobile: "Mobil"
        }
    }
}

/// Bir uygulamanın bir aralıktaki trafiği (mobil = pahalı yol; "Wi‑Fi" = pahalı olmayan her yol, kablolu dahil).
struct LiveTraffic: Equatable, Sendable {
    var down: UInt64 = 0
    var up: UInt64 = 0
    var mobileDown: UInt64 = 0
    var mobileUp: UInt64 = 0

    var isEmpty: Bool { down == 0 && up == 0 }

    mutating func add(_ o: LiveTraffic) {
        down &+= o.down
        up &+= o.up
        mobileDown &+= o.mobileDown
        mobileUp &+= o.mobileUp
    }

    /// Süzgece göre (↓, ↑).
    func split(_ interface: LiveInterface) -> (down: UInt64, up: UInt64) {
        switch interface {
        case .all: (down, up)
        case .mobile: (mobileDown, mobileUp)
        case .wifi: (down &- min(down, mobileDown), up &- min(up, mobileUp))
        }
    }
}

/// Canlı listenin bir satırı.
struct LiveAppUsage: Identifiable, Equatable, Sendable {
    var id: String { app }
    var app: String
    var down: UInt64
    var up: UInt64
    /// Son birkaç saniyenin ortalaması (byte/sn, ↓+↑, süzgece göre).
    var rate: UInt64

    var bytes: UInt64 { down &+ up }
}

extension LiveAppUsage {
    /// Bugünkü toplamlar → süzgeçten geçen satırlar (toplam `down`'da, `up` = 0), büyükten küçüğe (eşitlikte ada göre).
    static func today(_ usage: [AppUsage], interface: LiveInterface, rates: [String: UInt64] = [:]) -> [LiveAppUsage] {
        usage.compactMap { u -> LiveAppUsage? in
            let mobile = min(u.mobileBytes, u.bytes)
            let bytes: UInt64 = switch interface {
            case .all: u.bytes
            case .mobile: mobile
            case .wifi: u.bytes - mobile
            }
            guard bytes > 0 else { return nil }
            return LiveAppUsage(app: u.app, down: bytes, up: 0, rate: rates[u.app] ?? 0)
        }
        .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.app < $1.app }
    }
}

/// Uygulama başına son 60 saniyenin (saniye kovaları) ve son 60 dakikanın (dakika kovaları) trafiği; yalnızca bellekte.
/// Yeni zamanlayıcı yok: `UsageEngine.ingest` (ölçüm adımı) besler, görünüm görünürken `rows` ile okunur. Saf, test edilir.
struct LiveUsageHistory: Sendable {
    /// Anlık hız için ortalaması alınan son saniye sayısı (ölçüm aralığı 2-5 sn olabildiği için birkaç saniye).
    static let rateWindow = 5

    private var seconds: [[String: LiveTraffic]] = Array(repeating: [:], count: 60)
    private var secondIndex = 0
    /// Unix dakikası → uygulama → trafik.
    private var minutes: [Int: [String: LiveTraffic]] = [:]

    /// Saniye halkasını `count` saniye ilerletir (her ölçüm adımının başında, geçen süre kadar).
    mutating func advance(seconds count: Int) {
        for _ in 0..<min(max(1, count), seconds.count) {
            secondIndex = (secondIndex + 1) % seconds.count
            if !seconds[secondIndex].isEmpty { seconds[secondIndex] = [:] }
        }
    }

    /// Bu adımın trafiği: şu anki saniyeye ve `minute` (Unix dakikası) kovasına yazılır.
    mutating func record(app: String, bytesIn: UInt64, bytesOut: UInt64, mobile: Bool, minute: Int) {
        let t = LiveTraffic(down: bytesIn, up: bytesOut, mobileDown: mobile ? bytesIn : 0, mobileUp: mobile ? bytesOut : 0)
        guard !t.isEmpty else { return }
        seconds[secondIndex][app, default: LiveTraffic()].add(t)
        minutes[minute, default: [:]][app, default: LiveTraffic()].add(t)
    }

    /// 60 dakikadan eski dakika kovalarını atar.
    mutating func prune(nowMinute: Int) {
        guard minutes.keys.contains(where: { $0 <= nowMinute - LiveRange.hour1.minutes }) else { return }
        minutes = minutes.filter { $0.key > nowMinute - LiveRange.hour1.minutes }
    }

    /// Aralıktaki toplam (uygulama → trafik). 60 sn saniye halkasından, diğerleri son N dakika kovasından
    /// (şu anki, henüz dolmamış dakika dahil).
    func totals(range: LiveRange, nowMinute: Int) -> [String: LiveTraffic] {
        var out: [String: LiveTraffic] = [:]
        if range == .now {
            return recent()
        } else if range == .sec60 {
            for slot in seconds { for (app, t) in slot { out[app, default: LiveTraffic()].add(t) } }
        } else {
            let first = nowMinute - range.minutes + 1
            for (minute, apps) in minutes where minute >= first && minute <= nowMinute {
                for (app, t) in apps { out[app, default: LiveTraffic()].add(t) }
            }
        }
        return out
    }

    /// Son `rateWindow` saniyenin uygulama başına toplamı.
    private func recent() -> [String: LiveTraffic] {
        var out: [String: LiveTraffic] = [:]
        for k in 0..<Self.rateWindow {
            let i = (secondIndex - k + seconds.count) % seconds.count
            for (app, t) in seconds[i] { out[app, default: LiveTraffic()].add(t) }
        }
        return out
    }

    /// Süzgeçten geçen, byte'a göre büyükten küçüğe (eşitlikte ada göre) sıralı satırlar.
    func rows(range: LiveRange, interface: LiveInterface, nowMinute: Int, limit: Int? = nil) -> [LiveAppUsage] {
        let recent = recent()
        var rows: [LiveAppUsage] = []
        for (app, t) in totals(range: range, nowMinute: nowMinute) {
            var (down, up) = t.split(interface)
            guard down &+ up > 0 else { continue }
            let r = recent[app].map { $0.split(interface) } ?? (0, 0)
            let rate = (r.down &+ r.up) / UInt64(Self.rateWindow)
            if range == .now {
                // Anlık: değerler saniye başına (B/s); toplam = hız.
                down /= UInt64(Self.rateWindow); up /= UInt64(Self.rateWindow)
                guard down &+ up > 0 else { continue }
            }
            rows.append(LiveAppUsage(app: app, down: down, up: up, rate: rate))
        }
        rows.sort { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.app < $1.app }
        if let limit, rows.count > limit { rows.removeSubrange(limit...) }
        return rows
    }
}
