import SwiftUI

/// Görev Yöneticisi gibi sütun başlığı: üstte sistem toplamı ("%23"), altında sütun adı; tıklayınca sıralar. Hücre toplam yüküne göre tonlanır.
/// Sütun genişlikleri satırlarla aynı `ProcessTableColumns`tan gelir.
struct ProcessColumnHeader: View {
    let columns: ProcessTableColumns
    let totals: ProcessTotals
    let sortColumn: ProcessColumn
    let sortAscending: Bool
    let onSort: (ProcessColumn) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Button { onSort(.name) } label: {
                HStack(spacing: 4) {
                    Text("Ad").font(.callout.weight(.medium))
                    indicator(for: .name)
                }
                .padding(.leading, 40)
                .frame(width: columns.nameWidth, height: ProcessTableLayout.headerHeight, alignment: .bottomLeading)
                .padding(.bottom, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ad, sırala")
            ForEach(columns.entries) { entry in
                Button { onSort(entry.column) } label: { cell(entry) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.column.isMetric ? "\(entry.column.title), toplam \(total(entry.column)), sırala" : "\(entry.column.title), sırala")
            }
            Spacer(minLength: 0)
        }
        .frame(height: ProcessTableLayout.headerHeight)
    }

    private func cell(_ entry: ProcessTableColumns.Entry) -> some View {
        let column = entry.column
        let t = column.isMetric
            ? HeatTint.quantized(HeatTint.intensity(column: column, value: totalValue(column), memoryTotal: Double(totals.memoryTotal)))
            : 0
        return VStack(alignment: .trailing, spacing: 2) {
            Text(total(column))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: total(column))
            HStack(spacing: 3) {
                indicator(for: column)
                Text(column.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: entry.width, height: ProcessTableLayout.headerHeight, alignment: .trailing)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            $0.background(HeatTint.color(intensity: t, dark: scheme == .dark))
        }
        .contentShape(.rect)
    }

    @ViewBuilder
    private func indicator(for column: ProcessColumn) -> some View {
        if sortColumn == column {
            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private func totalValue(_ column: ProcessColumn) -> Double {
        switch column {
        case .cpu: totals.cpu
        case .memory: Double(totals.memoryUsed)
        case .disk: totals.disk
        case .network: totals.network
        case .gpu: totals.gpu
        case .energy: totals.energy
        case .name, .category, .processCount, .pid: 0
        }
    }

    private func total(_ column: ProcessColumn) -> String {
        switch column {
        case .cpu: ResourceFormat.percent(totals.cpu)
        case .memory: "%\(Int((totals.memoryFraction * 100).rounded()))"
        case .disk: Format.rate(totals.disk)
        case .network: Format.rate(totals.network)
        case .gpu: ResourceFormat.percent(totals.gpu)
        case .energy: ResourceFormat.watts(totals.energy)
        case .name, .category, .processCount, .pid: ""
        }
    }
}
