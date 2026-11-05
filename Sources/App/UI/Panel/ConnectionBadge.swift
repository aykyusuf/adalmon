import SwiftUI

/// Başlıktaki bağlantı rozeti: Wi-Fi / Ethernet / Mobil veri / Çevrimdışı.
struct ConnectionBadge: View {
    let medium: PathMonitor.Medium
    let isMobile: Bool
    let interfaceName: String

    var body: some View {
        let offline = medium == .offline
        let color: Color = offline ? .secondary : (isMobile ? .orange : .green)
        Label(offline ? "Çevrimdışı" : (isMobile ? "Mobil veri" : mediumName),
              systemImage: offline ? "wifi.slash" : (isMobile ? "antenna.radiowaves.left.and.right" : "wifi"))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: .capsule)
            .help(interfaceName.isEmpty ? "" : "Arayüz: \(interfaceName)")
    }

    private var mediumName: String {
        switch medium {
        case .wifi: "Wi-Fi"
        case .ethernet: "Ethernet"
        default: "Bağlı"
        }
    }
}
