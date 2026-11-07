import SwiftUI

/// Engelleme sonrası kısa bildirim + "Geri al".
struct ToastBanner: View {
    let toast: AppModel.Toast?
    let onUndo: () -> Void
    let onAction: (AppModel.Toast.Action) -> Void

    var body: some View {
        if let toast {
            HStack(spacing: 8) {
                Image(systemName: toast.undoBlocked ? "hand.raised.fill" : "checkmark.circle.fill")
                    .foregroundStyle(toast.undoBlocked ? .red : .green)
                    .accessibilityHidden(true)
                Text(toast.message)
                    .font(.caption)
                    .lineLimit(2)
                Spacer(minLength: 4)
                if toast.undoApp != nil {
                    Button("Geri al", action: onUndo)
                        .buttonStyle(.link)
                        .font(.caption.weight(.semibold))
                }
                if let action = toast.action {
                    Button("Yeniden başlat") { onAction(action) }
                        .buttonStyle(.link)
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(8)
            .background { PanelCardBackground(cornerRadius: 10) }
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }
}
