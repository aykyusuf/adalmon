import SwiftUI

/// "Uygulamalar (12)" gibi katlanabilir bölüm başlığı.
struct ProcessSectionHeader: View {
    let category: ProcessCategory
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 14)
                Text("\(category.title) (\(count))").font(.callout.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("\(category.title), \(count) öğe, \(isCollapsed ? "kapalı" : "açık")")
        .accessibilityAddTraits(.isHeader)
    }
}
