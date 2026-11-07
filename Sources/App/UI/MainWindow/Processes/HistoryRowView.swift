import SwiftUI

/// "Uygulama geçmişi" satırı. Isı yoğunluğu, sütundaki en büyük değere göre (karekök ölçeği).
struct HistoryRowView: View {
    let row: AppHistoryRow
    let maxima: [HistoryColumn: Double]
    let dark: Bool
    var hint: String?

    var body: some View {
        HStack(spacing: 0) {
            ResourceAppLabel(key: row.app, size: 20, hint: hint)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(HistoryColumn.numeric) { column in
                let v = column.value(of: row)
                let peak = maxima[column] ?? 0
                let t = peak > 0 && v > 0 ? min(1, (v / peak).squareRoot()) : 0
                Text(column.text(v))
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(width: column.width, height: ProcessTableLayout.rowHeight, alignment: .trailing)
                    .background(HeatTint.color(intensity: t * 0.9, dark: dark))
            }
        }
        .frame(height: ProcessTableLayout.rowHeight)
        .accessibilityElement(children: .combine)
    }
}
