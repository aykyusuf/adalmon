import SwiftUI

/// Açık kalma süresi + son açılış, birleşik panel ve Genel bakış için ortak metinler (biçimleme `UptimeFormatter`'da).
struct UptimeSummary: Equatable {
    /// "2 g 23 sa 14 dk"
    var duration: String
    /// "2 g 23 sa"
    var shortDuration: String
    /// "6 Kas 09:12"
    var boot: String

    /// "Açık: 2 g 23 sa · Son açılış 6 Kas 09:12"
    var line: String { "Açık: \(shortDuration) · Son açılış \(boot)" }

    /// Açılış zamanı bilinmiyorsa `nil` (satır/kart hiç gösterilmez).
    static func make(boot: Date?, now: Date) -> UptimeSummary? {
        guard let boot else { return nil }
        let seconds = UptimeFormatter.uptime(since: boot, now: now)
        return UptimeSummary(duration: UptimeFormatter.duration(seconds),
                             shortDuration: UptimeFormatter.shortDuration(seconds),
                             boot: UptimeFormatter.bootStamp(boot))
    }

    /// Açılış zamanı oturum boyunca değişmez: sysctl bir kez okunur (görünümler her saniye yeniden kurulur).
    static let systemBoot: Date? = BootTimeReader.system.read()
}

/// Birleşik panelin alt bilgisindeki kompakt satır. Dakikada bir yenilenir (`TimelineView(.everyMinute)`):
/// yalnızca görünürken çalışır, ayrı timer yoktur.
struct UptimeLine: View {
    var boot: Date? = UptimeSummary.systemBoot

    var body: some View {
        if boot != nil {
            TimelineView(.everyMinute) { context in
                if let summary = UptimeSummary.make(boot: boot, now: context.date) {
                    Text(summary.line)
                        .lineLimit(1)
                }
            }
        }
    }
}
