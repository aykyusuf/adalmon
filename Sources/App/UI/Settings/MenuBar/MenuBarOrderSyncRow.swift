import SwiftUI

/// "Sırayı menü çubuğundan al" (MENUBAR-01): tek seferlik okuma, izleyici/zamanlayıcı yok.
struct MenuBarOrderSyncRow: View {
    @Bindable var store: MenuBarConfigStore
    /// Bileşen kimliği → ekran x konumu (StatusBarController.itemPositions).
    let readPositions: (() -> [UUID: CGFloat])?
    @State private var message: String?

    private var isSeparate: Bool { store.config.displayMode == .separate }

    var body: some View {
        HStack {
            Button("Sırayı menü çubuğundan al", systemImage: "arrow.left.arrow.right", action: sync)
                .disabled(!isSeparate || readPositions == nil)
                .help(isSeparate
                      ? "macOS menü çubuğunda ⌘ ile sürükleyerek değiştirdiğin sırayı Adalmon ayarlarına kaydeder."
                      : "Yalnızca “Ayrı” gösterimde kullanılabilir: birleşik modda tüm metrikler tek öğedir, sırası menü çubuğunda değiştirilemez.")
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            } else if !isSeparate {
                Text("Yalnızca “Ayrı” gösterimde.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sync() {
        switch store.syncOrder(positions: readPositions?() ?? [:]) {
        case .applied: message = "Sıra menü çubuğundan alındı."
        case .unchanged: message = "Sıra zaten aynı"
        case .noItems: message = "Menü çubuğunda okunacak öğe bulunamadı."
        }
    }
}
