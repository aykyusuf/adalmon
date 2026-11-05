import SwiftUI

struct PanelFooter: View {
    let data: PanelData
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(data.filterConnected ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(statusText)
                .lineLimit(1)
            Spacer()
            Button("Çık", systemImage: "power", action: onQuit)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Adalmon'dan çık")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var statusText: String {
        var parts: [String] = [data.filterConnected ? "Filtre aktif" : "Filtre bağlı değil"]
        if let port = data.proxyPorts.first {
            let owner = data.proxyOwnerPaths.first.map { ($0 as NSString).lastPathComponent } ?? "proxy"
            parts.append("\(owner) :\(port) ayrıştırılıyor")
        }
        return parts.joined(separator: " · ")
    }
}
