import SwiftUI

/// Bugün ile dün (tam gün) toplamının yan yana iki ince çubuğu.
struct YesterdayComparison: View {
    let today: UInt64
    let yesterday: UInt64?

    var body: some View {
        if let yesterday, yesterday > 0 {
            let peak = Double(max(today, yesterday))
            VStack(alignment: .leading, spacing: 6) {
                row("Bugün", bytes: today, fraction: Double(today) / peak, tint: .accentColor)
                row("Dün", bytes: yesterday, fraction: Double(yesterday) / peak, tint: .secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Bugün \(Format.bytes(today)), dün \(Format.bytes(yesterday)), bugün dünün yüzde \(Int(Double(today) * 100 / Double(yesterday))) kadarı")
        } else {
            Text("Dün için kayıt yok")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ title: String, bytes: UInt64, fraction: Double, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
            UsageBar(fraction: fraction, tint: tint, height: 6)
            Text(Format.bytes(bytes)).font(.caption).monospacedDigit().frame(width: 70, alignment: .trailing)
        }
    }
}
