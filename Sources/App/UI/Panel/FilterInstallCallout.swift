import SwiftUI

/// Uygulama bazlı ölçüm için ağ filtresi kurulu değilse listelerin yerinde gösterilir.
struct FilterInstallCallout: View {
    let state: ExtensionInstaller.State
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Uygulama bazlı ölçüm kapalı", systemImage: "chart.bar.doc.horizontal")
                .font(.caption.weight(.semibold))
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Ağ filtresini kur", action: onInstall)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(state == .installing)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.1), in: .rect(cornerRadius: PanelMetricCard.cornerRadius, style: .continuous))
    }

    private var message: String {
        switch state {
        case .needsApproval: "Sistem Ayarları › Genel › Giriş Öğeleri ve Uzantılar › Ağ Uzantıları'ndan Adalmon'u aç."
        case .failed(let e): "Kurulum hatası: \(e)"
        case .installing: "Kuruluyor…"
        default: "Hangi uygulamanın ve sitenin ne kadar veri harcadığını görmek için ağ filtresi gerekir. Trafiği engellemez, sadece sayar."
        }
    }
}
