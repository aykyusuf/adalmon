import SwiftUI

/// "İşlemler" satırı: ad hücresi + ısı haritası tonlu sayısal hücreler.
struct ProcessTableRow: View {
    let row: LiveRow
    let columns: ProcessTableColumns
    let memoryTotal: Double
    let isSelected: Bool
    let isExpanded: Bool
    let canExpand: Bool
    let isMeasuring: Bool
    let onToggleExpand: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            nameCell
                .frame(width: columns.nameWidth, alignment: .leading)
            ForEach(columns.entries) { entry in
                cell(entry)
            }
            Spacer(minLength: 0)
        }
        .frame(height: ProcessTableLayout.rowHeight)
        .background(isHovering && !isSelected ? Color.primary.opacity(0.05) : .clear)
        .onHover { isHovering = $0 }
    }

    private var nameCell: some View {
        HStack(spacing: 6) {
            if row.isMember { Color.clear.frame(width: 24, height: 1) }
            chevron
            if row.isMember {
                memberLabel
            } else {
                ResourceAppLabel(key: row.key, size: 20, hint: row.pathHint)
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

    /// Üye adı önce tam görünür; pid/adet etiketi yalnızca adın tamamıyla birlikte sığıyorsa gösterilir (üst üste binmez).
    private var memberLabel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                memberName
                if let suffix = memberSuffix {
                    Text(suffix.text).font(.caption).foregroundStyle(.tertiary).lineLimit(1).fixedSize().help(suffix.help)
                }
            }
            memberName
        }
    }

    private var memberName: some View {
        Text(row.name).lineLimit(1).truncationMode(.middle)
    }

    private var memberSuffix: (text: String, help: String)? {
        if row.processCount > 1 { return ("×\(row.processCount)", "\(row.processCount) süreç") }
        if let pid = row.pid, pid > 0 { return ("pid \(pid)", "PID \(pid)") }
        return nil
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
                    .animation(reduceMotion ? nil : .spring(duration: 0.28), value: isExpanded)
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

    private func cell(_ entry: ProcessTableColumns.Entry) -> some View {
        let column = entry.column
        let t = column.isMetric && !isSelected && !isMeasuring
            ? HeatTint.quantized(HeatTint.intensity(column: column, value: column.value(of: row), memoryTotal: memoryTotal))
            : 0
        let value = text(column)
        return Text(value)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(row.isMember ? .secondary : .primary)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: value)
            .padding(.horizontal, 8)
            .frame(width: entry.width, height: ProcessTableLayout.rowHeight, alignment: .trailing)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                $0.background(HeatTint.color(intensity: t, dark: scheme == .dark))
            }
            .overlay(alignment: .trailing) { if column.isMetric { Rectangle().fill(.background.opacity(0.5)).frame(width: 1) } }
    }

    private func text(_ column: ProcessColumn) -> String {
        if isMeasuring && !row.isMember && column.isMetric && column != .memory { return "…" }
        switch column {
        case .name: return ""
        case .cpu: return ResourceFormat.percent(row.cpu)
        case .memory: return ResourceFormat.bytes(row.memory)
        case .disk: return row.disk < 1 ? "—" : Format.rate(row.disk)
        case .network: return row.network < 1 ? "—" : Format.rate(row.network)
        case .gpu: return ResourceFormat.percent(row.gpu)
        case .energy: return ResourceFormat.watts(row.energy)
        case .category: return row.category.shortTitle
        case .processCount: return row.isMember && row.processCount <= 1 ? "—" : "\(row.processCount)"
        // Grup satırı: ana süreç (en eski = en küçük PID) + kaç alt süreç daha olduğu.
        case .pid:
            if row.isMember && row.processCount <= 1 { return row.pid.flatMap { $0 > 0 ? String($0) : nil } ?? "—" }
            guard let main = row.pids.min() else { return "—" }
            return row.pids.count > 1 ? "\(main) +\(row.pids.count - 1)" : String(main)
        }
    }
}
