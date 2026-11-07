import SwiftUI

/// Modern giriş öğesi satırı: salt okunur (SMAppService öğeleri yalnızca sahibi uygulama ya da Sistem Ayarları'ndan değiştirilebilir).
struct BackgroundItemRow: View {
    let item: BackgroundItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind == .agent ? "gearshape.2" : "person.crop.circle.badge.checkmark")
                .font(.title3).foregroundStyle(.secondary).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(item.isEnabled ? "Açık" : "Kapalı")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background((item.isEnabled ? Color.green : Color.secondary).opacity(0.18), in: .capsule)
                .foregroundStyle(item.isEnabled ? Color.green : Color.secondary)
                .accessibilityLabel("Durum: \(item.isEnabled ? "Açık" : "Kapalı")")
        }
        .padding(.vertical, 3)
        .help("Sistem Ayarları › Genel › Giriş Öğeleri'nden yönetilir")
    }

    private var subtitle: String {
        [item.detail, item.kind.title, item.developer].compactMap { $0 }.joined(separator: " · ")
    }
}
