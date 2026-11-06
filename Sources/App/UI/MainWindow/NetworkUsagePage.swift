import SwiftUI

/// "Ağ kullanımı": bugünün uygulama tablosu (sıralanabilir, aranabilir).
struct NetworkUsagePage: View {
    let data: PanelData
    let limits: [String: AppLimit]
    let actions: PanelActions

    @State private var query = ""
    @State private var sortOrder = [KeyPathComparator(\AppUsageTableRow.total, order: .reverse)]
    @State private var selection = Set<String>()
    @State private var pendingBlock: AppUsageTableRow?

    var body: some View {
        let rows = visibleRows
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: MainSection.network.title) {
                Text("Bugün ↓\(Format.bytes(data.downToday)) ↑\(Format.bytes(data.upToday))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 24)
            if data.showsFilterCallout {
                FilterInstallCallout(state: data.installerState, onInstall: actions.installFilter)
                    .padding(.horizontal, 24)
                Spacer()
            } else {
                table(rows)
            }
        }
        .padding(.top, 24)
        .searchable(text: $query, prompt: "Uygulama veya alan adı ara")
        .confirmationDialog(
            pendingBlock.map { "\($0.name) mobil veride engellensin mi?" } ?? "",
            isPresented: Binding(get: { pendingBlock != nil }, set: { if !$0 { pendingBlock = nil } }),
            titleVisibility: .visible,
            presenting: pendingBlock
        ) { row in
            Button("Engelle", role: .destructive) { actions.setBlocked(row.id, true) }
        } message: { _ in
            Text(data.isMobile ? "Şu an mobil verideysin; uygulamanın interneti hemen kesilir." : "Şu an Wi-Fi'desin, etkilenmez; mobil veriye geçince uygulanır.")
        }
    }

    private var visibleRows: [AppUsageTableRow] {
        data.today
            .map { AppUsageTableRow(usage: $0, blocked: data.blockedApps, limits: limits) }
            .filter { $0.matches(query) }
            .sorted(using: sortOrder)
    }

    private func table(_ rows: [AppUsageTableRow]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Uygulama", value: \.name) { row in
                AppNameCell(row: row)
            }
            .width(min: 160, ideal: 220)
            TableColumn("Alan adları", value: \.domainText) { row in
                Text(row.domainText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 140, ideal: 220)
            TableColumn("Toplam", value: \.total) { row in
                Text(Format.bytes(row.total)).monospacedDigit()
            }
            .width(min: 70, ideal: 90)
            TableColumn("Mobil", value: \.mobile) { row in
                Text(row.mobile > 0 ? Format.bytes(row.mobile) : "–")
                    .monospacedDigit()
                    .foregroundStyle(row.mobile > 0 ? .orange : .secondary)
            }
            .width(min: 70, ideal: 90)
            TableColumn("Durum", value: \.statusRank) { row in
                AppStatusCell(row: row) { toggleBlock(row) }
            }
            .width(min: 190, ideal: 260)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let row = rows.first(where: { ids.contains($0.id) }) {
                Button(row.isBlocked ? "Engeli kaldır" : "Mobilde engelle",
                       systemImage: row.isBlocked ? "hand.raised.slash" : "hand.raised") { toggleBlock(row) }
            }
        }
        .overlay {
            if rows.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("Henüz kayıt yok", systemImage: "chart.bar", description: Text("Bugün ağ kullanan uygulamalar burada listelenir."))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }

    private func toggleBlock(_ row: AppUsageTableRow) {
        if row.isBlocked { actions.setBlocked(row.id, false) } else { pendingBlock = row }
    }
}
