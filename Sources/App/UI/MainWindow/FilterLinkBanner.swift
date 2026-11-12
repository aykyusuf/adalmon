import SwiftUI

/// Filtre 60 sn'den uzun süredir bağlı değilse sayfanın üstünde: mobilde kırmızı şerit, Wi-Fi'de küçük nötr not.
/// "Filtreyi yeniden bağla" yalnızca XPC bağlantısını yeniden kurar; filtre ayarını değiştirmek Ayarlar › Filtre'dedir.
struct FilterLinkBanner: View {
    let level: FilterAlertLevel
    /// Filtre ayarı açık (yalnızca uzantıya ulaşılamıyor): yeniden bağlanmak işe yarayabilir.
    let canReconnect: Bool
    let onReconnect: () -> Void
    let onOpenSettings: () -> Void

    static let criticalText = "Filtre bağlı değil — mobil veri sınırları ve engeller UYGULANMIYOR, uygulama dağılımı güncellenmiyor"
    static let noteText = "Filtre bağlı değil. Wi-Fi'de etkisi az; mobil veriye geçersen sınırlar ve engeller uygulanmaz."

    var body: some View {
        switch level {
        case .none: EmptyView()
        case .critical: critical
        case .note: note
        }
    }

    private var critical: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Text(Self.criticalText)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            buttons
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red, in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Uyarı: \(Self.criticalText)")
    }

    private var note: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.slash")
                .accessibilityHidden(true)
            Text(Self.noteText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            buttons
                .controlSize(.small)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8, style: .continuous))
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if canReconnect {
                Button("Filtreyi yeniden bağla", systemImage: "arrow.triangle.2.circlepath", action: onReconnect)
                    .help("Filtre uzantısıyla bağlantıyı yeniden kurar ve ayarları yeniden gönderir; filtre ayarını değiştirmez.")
            }
            Button("Filtre ayarlarını aç", systemImage: "gearshape", action: onOpenSettings)
        }
        .buttonStyle(.bordered)
        .fixedSize()
    }
}
