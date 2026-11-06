import SwiftUI

/// Kademeli limitin şu anki seviyesi.
struct TierLadderStatusLine: View {
    let status: LadderStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                badge
                Text("Kullanım %\(status.percent)").font(.callout).monospacedDigit()
                if !status.throttledApps.isEmpty {
                    Text("\(status.throttledApps.count) uygulama yavaşlatıldı").font(.caption).foregroundStyle(.secondary)
                }
                if !status.blockedApps.isEmpty {
                    Text("\(status.blockedApps.count) uygulama engellendi").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch status.level {
        case .none: RuleBadge(text: "Normal", systemImage: "checkmark.circle", color: .green)
        case .warn: RuleBadge(text: "Uyarı", systemImage: "exclamationmark.circle", color: .blue)
        case .slow: RuleBadge(text: "Yavaşlatıldı", systemImage: "tortoise", color: .orange)
        case .cut: RuleBadge(text: "Kesildi", systemImage: "hand.raised.fill", color: .red)
        }
    }
}
