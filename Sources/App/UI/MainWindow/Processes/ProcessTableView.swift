import SwiftUI

/// "İşlemler": Görev Yöneticisi gibi gruplu (Uygulamalar / Arka plan / Sistem), ısı haritalı, sıralanabilir canlı süreç tablosu.
struct ProcessTableView: View {
    let model: AppModel
    let router: SettingsRouter
    @Bindable var live: ProcessLiveModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Sütunlara ayrılabilen ölçülmüş genişlik (ilk ölçümden önce makul bir varsayılan).
    @State private var contentWidth: CGFloat = 700
    /// Kullanıcının sütun sırası / görünürlüğü (UserDefaults'ta kalıcı).
    @State private var columnLayout = ProcessColumnLayout.load()

    var body: some View {
        let sections = live.sections
        let columns = ProcessTableLayout.columns(forWidth: contentWidth, layout: columnLayout)
        VStack(spacing: 0) {
            ProcessColumnHeader(columns: columns, totals: live.totals, sortColumn: live.sortColumn, sortAscending: live.sortAscending,
                                onSort: live.sort(by:), layout: $columnLayout, contentWidth: contentWidth)
                .padding(.leading, ProcessTableLayout.leadingInset)
                .padding(.trailing, ProcessTableLayout.trailingInset)
            Divider()
            List(selection: $live.selection) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            tableRow(row, columns: columns)
                        }
                    } header: {
                        ProcessSectionHeader(category: section.category, count: section.groupCount,
                                             isCollapsed: live.collapsed.contains(section.category)) { toggle(section.category) }
                            .listRowInsets(EdgeInsets())
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, ProcessTableLayout.rowHeight)
            .onHover { live.isPointerInside = $0 }
            .overlay {
                if sections.isEmpty {
                    if live.rows.isEmpty {
                        ContentUnavailableView("Ölçülüyor…", systemImage: "waveform.path.ecg",
                                               description: Text("İlk değerler birkaç saniye içinde gelir."))
                    } else {
                        ContentUnavailableView.search(text: live.query)
                    }
                }
            }
            .onDeleteCommand { if let row = live.row(id: live.selection) { live.requestKill(row) } }
            .onKeyPress(.return) { toggleExpansionOfSelection() }
            .onCopyCommand { copyProviders() }
            Divider()
            footer(sections)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            contentWidth = ProcessTableLayout.contentWidth(forContainer: width)
        }
        .onChange(of: columnLayout) { _, layout in
            layout.save()
            applySortFallback()
        }
        .searchable(text: $live.query, prompt: "İşlem veya uygulama ara")
        .toolbar { ProcessToolbar(live: live) }
        .sheet(item: $live.infoRow) { ProcessInfoSheet(row: $0) }
        .sheet(item: $live.limitRow) { ProcessLimitSheet(row: $0, model: model) }
        .confirmationDialog(killTitle, isPresented: isKilling, presenting: live.killRequest) { request in
            Button("Sonlandır", role: .destructive) { live.confirmKill(request) }
            Button("Vazgeç", role: .cancel) {}
        } message: { request in
            Text("\(request.pids.count) süreç sonlandırma isteği (SIGTERM) alacak. Kaydedilmemiş veriler kaybolabilir.")
        }
        .confirmationDialog("İşlem hâlâ çalışıyor", isPresented: isForceKilling, presenting: live.forceKillRequest) { request in
            Button("Zorla sonlandır", role: .destructive) { live.confirmForceKill(request) }
            Button("Bekle", role: .cancel) {}
        } message: { request in
            Text("“\(request.name)” sonlandırma isteğine yanıt vermedi (\(request.pids.count) süreç). Zorla sonlandırma (SIGKILL) hemen keser; kaydedilmemiş veriler kaybolur.")
        }
    }

    // MARK: Satır

    private func tableRow(_ row: LiveRow, columns: ProcessTableColumns) -> some View {
        ProcessTableRow(row: row, columns: columns, memoryTotal: Double(live.totals.memoryTotal), isSelected: live.selection == row.id,
                        isExpanded: live.expanded.contains(row.key), canExpand: live.canExpand(row), isMeasuring: live.isMeasuring) {
            live.setExpanded(row.key, !live.expanded.contains(row.key), service: model.resources, model: model)
        }
        // Görünen içeriği değişmeyen satırlar her ölçümde yeniden çizilmez (bkz. `ProcessTableRow.==`).
        .equatable()
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
        .listRowSeparator(.hidden)
        .contextMenu { ProcessContextMenu(row: row, model: model, router: router, live: live) }
    }

    // MARK: Alt çubuk

    private func footer(_ sections: [ProcessSection]) -> some View {
        let selected = live.row(id: live.selection)
        return HStack(spacing: 12) {
            Text(live.statusMessage ?? summary(sections))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.opacity)
            Spacer(minLength: 12)
            if let selected {
                Text(selected.name).font(.callout).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            }
            Button("İşlemi sonlandır", systemImage: "xmark.circle") {
                if let selected { live.requestKill(selected) }
            }
            .disabled(selected.map { !live.canKill($0) } ?? true)
            .help(selected.flatMap { live.permissions(for: $0).reason } ?? "Seçili işlemi sonlandırır (⌫). Yalnızca kendi kullanıcınıza ait, sistem dışı süreçler sonlandırılabilir.")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func summary(_ sections: [ProcessSection]) -> String {
        let apps = sections.first { $0.category == .app }?.groupCount ?? 0
        return "\(apps) uygulama · \(live.totalProcessCount) işlem"
    }

    // MARK: Yardımcılar

    /// Kullanıcı sıralama sütununu gizlediyse tablo görünmeyen bir sütuna göre sıralı kalmasın. (Pencere daralıp bir bilgi
    /// sütunu kendiliğinden düştüğünde sıralama korunur; genişleyince geri gelir.)
    private func applySortFallback() {
        if let fallback = columnLayout.sortFallback(for: live.sortColumn, width: contentWidth) { live.sort(by: fallback) }
    }

    private func toggleExpansionOfSelection() -> KeyPress.Result {
        guard let row = live.row(id: live.selection), live.canExpand(row) else { return .ignored }
        live.setExpanded(row.key, !live.expanded.contains(row.key), service: model.resources, model: model)
        return .handled
    }

    private func copyProviders() -> [NSItemProvider] {
        guard let row = live.row(id: live.selection) else { return [] }
        return [NSItemProvider(object: live.infoText(for: row) as NSString)]
    }

    private func toggle(_ category: ProcessCategory) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.28)) {
            if live.collapsed.contains(category) { live.collapsed.remove(category) } else { live.collapsed.insert(category) }
        }
    }

    private var killTitle: String {
        live.killRequest.map { "“\($0.name)” sonlandırılsın mı?" } ?? "İşlem sonlandırılsın mı?"
    }

    private var isKilling: Binding<Bool> {
        Binding(get: { live.killRequest != nil }, set: { if !$0 { live.killRequest = nil } })
    }

    private var isForceKilling: Binding<Bool> {
        Binding(get: { live.forceKillRequest != nil }, set: { if !$0 { live.forceKillRequest = nil } })
    }
}
