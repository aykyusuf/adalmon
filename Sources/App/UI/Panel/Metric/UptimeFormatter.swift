import Darwin
import Foundation

/// Bilgisayarın son açılış zamanını okur (sysctl `kern.boottime`: uykuda geçen süre dahil, duvar saati). Testlerde sahte okuyucu enjekte edilir.
struct BootTimeReader: Sendable {
    var read: @Sendable () -> Date?

    static let system = BootTimeReader {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000)
    }
}

/// Saf biçimleyici: süre → Türkçe metin ("2 g 23 sa 14 dk"), açılış zamanı → "6 Kas 09:12".
enum UptimeFormatter {
    /// Tam süre; sıfır bileşenler atlanır. 1 dakikadan azsa "1 dk'dan az".
    static func duration(_ seconds: TimeInterval) -> String {
        let (d, h, m) = parts(seconds)
        if d == 0, h == 0, m == 0 { return "1 dk'dan az" }
        return [(d, "g"), (h, "sa"), (m, "dk")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }.joined(separator: " ")
    }

    /// Kısa süre ("2 g 23 sa", "5 sa 14 dk", "14 dk"): en önemli iki birim.
    static func shortDuration(_ seconds: TimeInterval) -> String {
        let (d, h, m) = parts(seconds)
        if d == 0, h == 0, m == 0 { return "1 dk'dan az" }
        if d > 0 { return h > 0 ? "\(d) g \(h) sa" : "\(d) g" }
        if h > 0 { return m > 0 ? "\(h) sa \(m) dk" : "\(h) sa" }
        return "\(m) dk"
    }

    /// "6 Kas 09:12" (yerel biçim; yıl yok).
    static func bootStamp(_ date: Date, locale: Locale = Locale(identifier: "tr_TR"), timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate("dMMMHHmm")
        return f.string(from: date)
    }

    /// Açılış zamanından `now`'a geçen süre; saat geriye alınmışsa 0.
    static func uptime(since boot: Date, now: Date) -> TimeInterval { max(0, now.timeIntervalSince(boot)) }

    private static func parts(_ seconds: TimeInterval) -> (days: Int, hours: Int, minutes: Int) {
        let total = Int(max(0, seconds.isFinite ? seconds : 0)) / 60
        return (total / 1440, total % 1440 / 60, total % 60)
    }
}
