import SwiftUI

/// Temizlik > Başlangıç: kahraman başlık + özet ve sade kartlar. Süreçler > Başlangıç sekmesindeki `StartupItemsView` aynen kalır;
/// bu görünüm aynı `StartupItemsModel`i kullanır, mantık (devre dışı bırakma, kaldırma, sudo metni) değişmez.
struct CleanupStartupSection: View {
    var body: some View { StartupCleanupView() }
}
