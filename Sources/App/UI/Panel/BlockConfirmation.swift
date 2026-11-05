import SwiftUI

/// Satır içi engelleme onayı: ne olacağını açıkça söyler.
struct BlockConfirmation: View {
    let name: String
    let isMobile: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(name) mobil veride engellensin mi?")
                .font(.caption.weight(.semibold))
            Text(isMobile
                 ? "Şu an mobil veridesin: \(name) interneti hemen kesilir. Wi-Fi'ye geçince serbest kalır."
                 : "Wi-Fi'de etkilenmez. Mobil veriye geçtiğinde \(name) internete çıkamaz.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Vazgeç", action: onCancel)
                    .controlSize(.small)
                Button("Engelle", role: .destructive, action: onConfirm)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding(6)
        .background(Color.red.opacity(0.08), in: .rect(cornerRadius: 10))
        .padding(.leading, 22)
    }
}
