import SwiftUI

/// Bağlantı rozeti: Wi-Fi, Ethernet, hotspot (iPhone vb.), mobil veri ya da çevrimdışı.
struct ConnectionBadge: View {
    let medium: PathMonitor.Medium
    let isMobile: Bool
    let interfaceName: String

    var body: some View {
        let tint = tint
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: .capsule)
            .lineLimit(1)
            .help(interfaceName.isEmpty ? "" : "Arayüz: \(interfaceName)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bağlantı: \(title)")
    }

    private var isOffline: Bool { medium == .offline }

    /// Hücresel arayüz doğrudan "Mobil veri"; pahalı/kısıtlı Wi-Fi ya da USB yolu iPhone hotspot'tur.
    private var title: String {
        if isOffline { return "Çevrimdışı" }
        if isMobile { return medium == .cellular ? "Mobil veri" : "Hotspot" }
        switch medium {
        case .wifi: return "Wi-Fi"
        case .ethernet: return "Ethernet"
        default: return "Bağlı"
        }
    }

    private var symbol: String {
        if isOffline { return "wifi.slash" }
        if isMobile { return medium == .cellular ? "antenna.radiowaves.left.and.right" : "personalhotspot" }
        return medium == .ethernet ? "cable.connector.horizontal" : "wifi"
    }

    private var tint: Color { isOffline ? .secondary : (isMobile ? .orange : .green) }
}
