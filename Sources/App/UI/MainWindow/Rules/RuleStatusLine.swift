import SwiftUI

/// Bir kuralın canlı durumu: kullanılan/eşik çubuğu, sıfırlanmaya kalan süre, uygulanıyor rozeti ve Wi-Fi notu.
struct RuleStatusLine: View {
    let rule: UsageRule
    let status: RuleStatus?

    var body: some View {
        if let status {
            let fraction = status.thresholdBytes == 0 ? 0 : min(1, Double(status.usedBytes) / Double(status.thresholdBytes))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    UsageBar(fraction: fraction, tint: tint(status, fraction), height: 6)
                    Text("\(Format.bytes(status.usedBytes)) / \(Format.bytes(status.thresholdBytes))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                HStack(spacing: 6) {
                    phaseBadge(status)
                    if let remaining = remainingText(status) {
                        Text(remaining).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func tint(_ status: RuleStatus, _ fraction: Double) -> Color {
        if status.phase == .active { return .red }
        return fraction >= 0.8 ? .orange : .green
    }

    @ViewBuilder
    private func phaseBadge(_ status: RuleStatus) -> some View {
        switch status.phase {
        case .disabled: RuleBadge(text: "Kapalı", systemImage: "pause.circle", color: .secondary)
        case .idle: RuleBadge(text: "Bekliyor", systemImage: "clock", color: .green)
        case .cooldown: RuleBadge(text: "Bekleme süresi", systemImage: "hourglass", color: .secondary)
        case .active:
            if status.isEnforcedNow {
                RuleBadge(text: "Uygulanıyor", systemImage: "checkmark.shield.fill", color: .red)
            } else {
                RuleBadge(text: "Tetiklendi · bu ağda geçerli değil", systemImage: "exclamationmark.triangle", color: .orange)
            }
        }
    }

    private func remainingText(_ status: RuleStatus) -> String? {
        guard rule.enabled else { return nil }
        if rule.trigger.isFixedWindow {
            guard let left = status.secondsUntilReset else { return "Pencere ilk kullanımda başlar" }
            return "Sıfırlanmaya \(RuleText.duration(left)) kaldı"
        }
        guard status.phase == .active, let left = status.secondsUntilReset else { return nil }
        return "En az \(RuleText.duration(left)) sürer"
    }
}
