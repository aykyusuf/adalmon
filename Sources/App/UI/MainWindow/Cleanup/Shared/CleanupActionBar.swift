import SwiftUI

/// Sonuç ekranının altındaki sabit eylem çubuğu: seçili toplam + silme yöntemi + tek "Temizle" düğmesi.
/// Silme yöntemi varsayılan Çöp'tür; kalıcı seçilirse düğme kırmızı olur (asıl onay `DeleteConfirmation`da, işlem başına).
/// `leading` sol tarafa küçük ek eylemler koyar (ör. "Yeniden tara", "Seçimi temizle").
struct CleanupActionBar<Leading: View>: View {
    let countText: String
    let bytes: UInt64
    @Binding var mode: DeleteMode
    var title = "Temizle"
    var isEnabled = true
    var isBusy = false
    let accent: CleanupAccent
    let onClean: () -> Void
    private let leading: Leading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(countText: String, bytes: UInt64, mode: Binding<DeleteMode>, title: String = "Temizle", isEnabled: Bool = true,
         isBusy: Bool = false, accent: CleanupAccent, onClean: @escaping () -> Void, @ViewBuilder leading: () -> Leading) {
        self.countText = countText
        self.bytes = bytes
        _mode = mode
        self.title = title
        self.isEnabled = isEnabled
        self.isBusy = isBusy
        self.accent = accent
        self.onClean = onClean
        self.leading = leading()
    }

    private var permanent: Bool { mode == .permanent }

    var body: some View {
        HStack(spacing: 14) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(Format.bytes(bytes)).font(.title3.weight(.semibold)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(bytes)))
                    .animation(reduceMotion ? nil : .smooth, value: bytes)
                Text(countText).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 8)
            modeMenu
            Button(action: onClean) {
                if isBusy {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Temizleniyor…") }
                } else {
                    Label(permanent ? "Kalıcı sil…" : "\(title)…", systemImage: permanent ? "xmark.bin" : "sparkles")
                }
            }
            .buttonStyle(CleanupPrimaryButtonStyle(accent: permanent ? .destructive : accent, prominent: false))
            .disabled(!isEnabled || isBusy)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    }

    private var modeMenu: some View {
        Menu {
            Picker("Silme yöntemi", selection: $mode) {
                Text("Çöp'e taşı").tag(DeleteMode.trash)
                Text("Kalıcı sil").tag(DeleteMode.permanent)
            }
            .pickerStyle(.inline)
        } label: {
            Label(permanent ? "Kalıcı" : "Çöp'e taşı", systemImage: permanent ? "exclamationmark.triangle.fill" : "trash")
                .foregroundStyle(permanent ? Color.red : Color.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isBusy)
        .help("Kalıcı silme yalnızca bu işlem içindir; sonra Çöp'e taşımaya döner.")
    }
}

extension CleanupActionBar where Leading == EmptyView {
    init(countText: String, bytes: UInt64, mode: Binding<DeleteMode>, title: String = "Temizle", isEnabled: Bool = true,
         isBusy: Bool = false, accent: CleanupAccent, onClean: @escaping () -> Void) {
        self.init(countText: countText, bytes: bytes, mode: mode, title: title, isEnabled: isEnabled, isBusy: isBusy,
                  accent: accent, onClean: onClean) { EmptyView() }
    }
}

extension CleanupAccent {
    /// Kalıcı silme düğmesi için kırmızı.
    static let destructive = CleanupAccent(hue: 0.0, saturation: 0.78, brightness: 0.92)
}
