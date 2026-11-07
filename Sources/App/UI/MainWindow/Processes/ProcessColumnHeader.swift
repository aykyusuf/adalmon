import SwiftUI

/// Görev Yöneticisi gibi sütun başlığı: üstte sistem toplamı ("%23"), altında sütun adı; tıklayınca sıralar. Hücre toplam yüküne göre tonlanır.
struct ProcessColumnHeader: View {
    let totals: ProcessTotals
    let sortColumn: ProcessColumn
    let sortAscending: Bool
    let onSort: (ProcessColumn) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            Button { onSort(.name) } label: {
                HStack(spacing: 4) {
                    Text("Ad").font(.callout.weight(.medium))
                    indicator(for: .name)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 40)
                .frame(height: ProcessTableLayout.headerHeight, alignment: .bottomLeading)
                .padding(.bottom, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ad, sırala")
            ForEach(ProcessTableLayout.numericColumns) { column in
                Button { onSort(column) } label: { cell(column) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(column.title), toplam \(total(column)), sırala")
            }
        }
        .frame(height: ProcessTableLayout.headerHeight)
    }

    private func cell(_ column: ProcessColumn) -> some View {
        let t = HeatTint.intensity(column: column, value: totalValue(column), memoryTotal: Double(totals.memoryTotal))
        return VStack(alignment: .trailing, spacing: 2) {
            Text(total(column))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 3) {
                indicator(for: column)
                Text(column.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: ProcessTableLayout.width(column), height: ProcessTableLayout.headerHeight, alignment: .trailing)
        .background(HeatTint.color(intensity: t, dark: scheme == .dark))
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
        case .name: 0
        case .cpu: totals.cpu
        case .memory: Double(totals.memoryUsed)
        case .disk: totals.disk
        case .network: totals.network
        case .gpu: totals.gpu
        case .energy: totals.energy
        }
    }

    private func total(_ column: ProcessColumn) -> String {
        switch column {
        case .name: ""
        case .cpu: ResourceFormat.percent(totals.cpu)
        case .memory: "%\(Int((totals.memoryFraction * 100).rounded()))"
        case .disk: Format.rate(totals.disk)
        case .network: Format.rate(totals.network)
        case .gpu: ResourceFormat.percent(totals.gpu)
        case .energy: ResourceFormat.watts(totals.energy)
        }
    }
}
