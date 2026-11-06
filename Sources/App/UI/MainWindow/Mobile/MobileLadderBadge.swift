import SwiftUI

/// Kademeli limit durumu rozeti (açıkken).
struct MobileLadderBadge: View {
    let status: LadderStatus

    private var tint: Color {
        switch status.level {
        case .none: .green
        case .warn: .yellow
        case .slow: .orange
        case .cut: .red
        }
    }

    var body: some View {
        if status.enabled {
            StatusBadge(text: "Kademeli limit: \(status.level.title) · %\(status.percent)", systemImage: "stairs", color: tint)
                .help(helpText)
        } else {
            Text("Kademeli limit kapalı")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var helpText: String {
        var parts: [String] = []
        if !status.throttledApps.isEmpty { parts.append("\(status.throttledApps.count) uygulama yavaşlatıldı") }
        if !status.blockedApps.isEmpty { parts.append("\(status.blockedApps.count) uygulama engellendi") }
        return parts.isEmpty ? "Kullanım yüzdesi günlük ve aylık limite göre hesaplanır" : parts.joined(separator: " · ")
    }
}
