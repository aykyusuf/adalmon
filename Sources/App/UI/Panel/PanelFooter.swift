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
                .fill(Self.dotColor(data))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(statusText)
                .lineLimit(1)
                .foregroundStyle(data.filterAlert == .critical ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                .fontWeight(data.filterAlert == .critical ? .semibold : nil)
            Spacer(minLength: 8)
            if uptimeInline { UptimeLine(boot: bootTime) }
            Button("Çık", systemImage: "power", action: onQuit)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Adalmon'dan çık")
        }
    }

    private var statusText: String {
        var parts: [String] = [Self.filterText(data)]
        if let port = data.proxyPorts.first {
            let owner = data.proxyOwnerPaths.first.map { ($0 as NSString).lastPathComponent } ?? "proxy"
            parts.append("\(owner) :\(port) ayrıştırılıyor")
        }
        return parts.joined(separator: " · ")
    }

    /// Bağlıyken yeşil; mobilde uzun süredir bağlı değilken kırmızı; diğer kopukluklarda turuncu.
    static func dotColor(_ data: PanelData) -> Color {
        if data.filterConnected { return .green }
        return data.filterAlert == .critical ? .red : .orange
    }

    static func filterText(_ data: PanelData) -> String {
        if data.filterConnected { return "Filtre aktif" }
        return data.filterAlert == .critical ? "Filtre bağlı değil — sınırlar uygulanmıyor" : "Filtre bağlı değil"
    }
}
