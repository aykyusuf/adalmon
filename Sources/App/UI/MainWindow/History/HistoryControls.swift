import SwiftUI

/// Aralık seçici (Gün/Hafta/Ay) ve önceki/sonraki dönem düğmeleri.
struct HistoryControls: View {
    @Binding var range: HistoryRange
    @Binding var offset: Int
    let periodTitle: String

    var body: some View {
        HStack(spacing: 12) {
            Picker("Aralık", selection: $range) {
                ForEach(HistoryRange.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            ControlGroup {
                Button("Önceki dönem", systemImage: "chevron.left", action: older)
                    .disabled(offset >= range.maxOffset)
                Button("Sonraki dönem", systemImage: "chevron.right", action: newer)
                    .disabled(offset == 0)
            }
            .labelStyle(.iconOnly)
            .controlGroupStyle(.navigation)
            if !periodTitle.isEmpty {
                Text(periodTitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 110, alignment: .leading)
            }
        }
    }

    private func older() { offset = min(range.maxOffset, offset + 1) }
    private func newer() { offset = max(0, offset - 1) }
}
