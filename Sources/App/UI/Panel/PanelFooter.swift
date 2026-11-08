import SwiftUI

struct PanelFooter: View {
    let data: PanelData
    let onQuit: () -> Void
    /// Açık kalma satırı için son açılış; `nil` ise satır gösterilmez.
    var bootTime: Date? = UptimeSummary.systemBoot

    var body: some View {
        // Açık kalma satırı durum satırına sığıyorsa aynı satırda (panel yüksekliği artmaz), sığmıyorsa altta ayrı satır.
        ViewThatFits(in: .horizontal) {
            row(uptimeInline: true)
            VStack(alignment: .leading, spacing: 3) {
                row(uptimeInline: false)
                UptimeLine(boot: bootTime)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func row(uptimeInline: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(data.filterConnected ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(statusText)
                .lineLimit(1)
            Spacer(minLength: 8)
            if uptimeInline { UptimeLine(boot: bootTime) }
            Button("Çık", systemImage: "power", action: onQuit)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Adalmon'dan çık")
        }
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
