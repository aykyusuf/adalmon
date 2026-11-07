import SwiftUI

/// "İşlemler" satırı: ad hücresi + ısı haritası tonlu sayısal hücreler.
struct ProcessTableRow: View {
    let row: LiveRow
    let memoryTotal: Double
    let isSelected: Bool
    let isExpanded: Bool
    let canExpand: Bool
    let isMeasuring: Bool
    let onToggleExpand: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            nameCell
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(ProcessTableLayout.numericColumns) { column in
                numericCell(column)
            }
        }
        .frame(height: ProcessTableLayout.rowHeight)
        .background(isHovering && !isSelected ? Color.primary.opacity(0.05) : .clear)
        .onHover { isHovering = $0 }
    }

    private var nameCell: some View {
        HStack(spacing: 6) {
            if row.isMember { Color.clear.frame(width: 34, height: 1) }
            chevron
            if row.isMember {
                Text(row.name).lineLimit(1).truncationMode(.middle)
                if let pid = row.pid { Text("pid \(pid)").font(.caption).foregroundStyle(.tertiary) }
            } else {
                ResourceAppLabel(key: row.key, size: 20)
                if row.processCount > 1 {
                    Text("\(row.processCount)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08), in: .capsule)
                        .help("\(row.processCount) süreç")
                }
            }
            badges
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .foregroundStyle(row.isMember ? .secondary : .primary)
    }

    @ViewBuilder
    private var badges: some View {
        if row.isSuspended {
            Label("Askıda", systemImage: "pause.fill")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Color.orange.opacity(0.16), in: .capsule)
                .help("Süreç askıya alındı (SIGSTOP). Devam ettirmek için bağlam menüsünü kullan.")
        }
        if row.isEfficient {
            Image(systemName: "leaf.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .help("Verimlilik modu: düşük öncelikli (arka plan) çalışıyor")
                .accessibilityLabel("Verimlilik modu")
        }
    }

    @ViewBuilder
    private var chevron: some View {
        if canExpand {
            Button(action: onToggleExpand) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 18, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(isExpanded ? "Süreçleri gizle" : "Süreçleri göster")
        } else {
            Color.clear.frame(width: 18, height: 1)
        }
    }

    private func numericCell(_ column: ProcessColumn) -> some View {
        let t = isSelected || isMeasuring ? 0 : HeatTint.intensity(column: column, value: column.value(of: row), memoryTotal: memoryTotal)
        return Text(text(column))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(row.isMember ? .secondary : .primary)
            .padding(.horizontal, 8)
            .frame(width: ProcessTableLayout.width(column), height: ProcessTableLayout.rowHeight, alignment: .trailing)
            .background(HeatTint.color(intensity: t, dark: scheme == .dark))
            .overlay(alignment: .trailing) { Rectangle().fill(.background.opacity(0.5)).frame(width: 1) }
    }

    private func text(_ column: ProcessColumn) -> String {
        if isMeasuring && !row.isMember && column != .memory { return "…" }
        switch column {
        case .name: return ""
        case .cpu: return ResourceFormat.percent(row.cpu)
        case .memory: return ResourceFormat.bytes(row.memory)
        case .disk: return row.disk < 1 ? "—" : Format.rate(row.disk)
        case .network: return row.network < 1 ? "—" : Format.rate(row.network)
        case .gpu: return ResourceFormat.percent(row.gpu)
        case .energy: return ResourceFormat.watts(row.energy)
        }
    }
}
