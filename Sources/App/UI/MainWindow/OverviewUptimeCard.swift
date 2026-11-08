import SwiftUI

/// Genel bakış: bilgisayarın açık kalma süresi ve son açılışı. Dakikada bir yenilenir; açılış zamanı okunamazsa gizlenir.
struct OverviewUptimeCard: View {
    var boot: Date? = UptimeSummary.systemBoot

    var body: some View {
        if boot != nil {
            TimelineView(.everyMinute) { context in
                if let summary = UptimeSummary.make(boot: boot, now: context.date) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Açık kalma süresi", systemImage: "power")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(summary.duration)
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("Son açılış: \(summary.boot)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
