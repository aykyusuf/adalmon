import SwiftUI

/// Sonuç ekranının üstündeki büyük toplam ("12,4 GB" / "temizlenebilir"). Değer değişince rakamlar kayarak güncellenir.
/// `notes` küçük açıklama satırları, `warning` turuncu uyarıdır.
struct CleanupResultHeader: View {
    let bytes: UInt64
    let caption: String
    let accent: CleanupAccent
    var notes: [String] = []
    var warning: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            Text(Format.bytes(bytes))
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(LinearGradient(colors: [accent.light, accent.deep], startPoint: .top, endPoint: .bottom))
                .contentTransition(.numericText(value: Double(bytes)))
                .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: bytes)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.title3).foregroundStyle(.secondary)
            ForEach(notes, id: \.self) { note in
                Text(note).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 520)
            }
            if let warning {
                Label(warning, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .accessibilityElement(children: .combine)
    }
}
