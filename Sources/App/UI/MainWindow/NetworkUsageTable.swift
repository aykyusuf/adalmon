import SwiftUI

/// Ağ kullanımı tablosu. Sütun kümesi içeriğin genişliğine göre değişir (ayrıntı paneli açıkken daralır).
struct NetworkUsageTable: View {
    let rows: [AppUsageTableRow]
    let isSearching: Bool
    @Binding var selection: String?
    @Binding var sortOrder: [KeyPathComparator<AppUsageTableRow>]
    let onShowDetails: (String) -> Void
    let onToggleBlock: (AppUsageTableRow) -> Void
    let onClose: () -> Void

    @State private var columns = NetworkColumnSet.full

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Uygulama", value: \.name) { row in
                AppNameCell(row: row, showsStatusGlyph: !columns.showsStatus)
            }
            .width(min: 150, ideal: 220)
            if columns.showsDomains {
                TableColumn("Alan adları", value: \.domainText) { row in
                    Text(row.domainText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .width(min: 120, ideal: 220)
            }
            TableColumn("Toplam", value: \.total) { row in
                Text(Format.bytes(row.total)).monospacedDigit()
            }
            .width(min: 64, ideal: 84, max: 120)
            TableColumn("Mobil", value: \.mobile) { row in
                Text(row.mobile > 0 ? Format.bytes(row.mobile) : "–")
                    .monospacedDigit()
                    .foregroundStyle(row.mobile > 0 ? .orange : .secondary)
            }
            .width(min: 64, ideal: 84, max: 120)
            if columns.showsStatus {
                TableColumn("Durum", value: \.statusRank) { row in
                    AppStatusCell(row: row) { onToggleBlock(row) }
                }
                .width(min: 110, ideal: 240)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            let next = NetworkColumnSet(width: width)
            if next != columns { columns = next }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let row = rows.first(where: { ids.contains($0.id) }) {
                Button("Ayrıntıları göster", systemImage: "sidebar.trailing") { onShowDetails(row.id) }
                Divider()
                Button(row.isBlocked ? "Engeli kaldır" : "Mobilde engelle",
                       systemImage: row.isBlocked ? "hand.raised.slash" : "hand.raised") { onToggleBlock(row) }
            }
        } primaryAction: { ids in
            if let id = ids.first { onShowDetails(id) }
        }
        .onExitCommand(perform: onClose)
        .overlay {
            if rows.isEmpty {
                if isSearching {
                    ContentUnavailableView.search
                } else {
                    ContentUnavailableView("Henüz kayıt yok", systemImage: "chart.bar", description: Text("Bugün ağ kullanan uygulamalar burada listelenir."))
                }
            }
        }
    }
}
