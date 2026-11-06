import SwiftUI

/// Rapor dönem kısayolu (Dün / Son 7 gün / Bu ay); seçiliyken vurgulanır.
struct HistoryReportChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.07), in: .capsule)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
