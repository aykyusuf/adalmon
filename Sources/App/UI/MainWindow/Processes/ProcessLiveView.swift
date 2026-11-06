import SwiftUI

/// "Şu an": uygulamaya göre canlı CPU / bellek / GPU / disk yazma / enerji, satırı açınca üye süreçler.
struct ProcessLiveView: View {
    let model: AppModel
    @State private var live = ProcessLiveModel()
    @State private var sortOrder = [KeyPathComparator(\LiveRow.cpu, order: .reverse)]

    var body: some View {
        let sorted = Array(live.rows.sorted(using: sortOrder).prefix(ProcessLiveModel.maxRows))
        VStack(alignment: .leading, spacing: 8) {
            Table(of: LiveRow.self, sortOrder: $sortOrder) {
                TableColumn("Uygulama", value: \.name) { row in
                    LiveNameCell(row: row)
                }
                .width(min: 180, ideal: 260)
                TableColumn("CPU", value: \.cpu) { row in
                    cell(ResourceFormat.percent(row.cpu), row: row)
                }
                .width(min: 60, ideal: 72)
                TableColumn("Bellek", value: \.memory) { row in
                    cell(ResourceFormat.bytes(row.memory), row: row)
                }
                .width(min: 70, ideal: 84)
                TableColumn("GPU", value: \.gpu) { row in
                    cell(ResourceFormat.percent(row.gpu), row: row)
                }
                .width(min: 56, ideal: 66)
                TableColumn("Disk yazma/sn", value: \.write) { row in
                    cell(row.write < 1 ? "—" : Format.rate(row.write), row: row)
                }
                .width(min: 90, ideal: 108)
                TableColumn("Enerji", value: \.energy) { row in
                    cell(ResourceFormat.watts(row.energy), row: row)
                }
                .width(min: 60, ideal: 72)
            } rows: {
                ForEach(sorted) { row in
                    if row.processCount > 1 || live.expanded.contains(row.key) {
                        DisclosureTableRow(row, isExpanded: expandedBinding(row.key)) {
                            ForEach(live.members[row.key] ?? []) { TableRow($0) }
                        }
                    } else {
                        TableRow(row)
                    }
                }
            }
            .overlay {
                if live.rows.isEmpty {
                    ContentUnavailableView("Ölçülüyor…", systemImage: "waveform.path.ecg",
                                           description: Text("İlk değerler birkaç saniye içinde gelir."))
                }
            }
            Text("CPU ve GPU yüzdeleri çekirdek başınadır; birden çok çekirdek kullanan uygulamada %100'ü aşabilir. Bellek: Etkinlik Monitörü'ndeki \"Bellek\" (ayak izi). Enerji: ortalama güç. Satırdaki grup, uygulamanın tüm yardımcı süreçlerini ve kısa ömürlü alt süreçlerini kapsar.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(priority: .utility) { await live.run(service: model.resources, model: model) }
    }

    private func expandedBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { live.expanded.contains(key) },
                set: { live.setExpanded(key, $0, service: model.resources) })
    }

    private func cell(_ text: String, row: LiveRow) -> some View {
        Text(live.isMeasuring && !row.isMember ? "…" : text)
            .monospacedDigit()
            .foregroundStyle(row.isMember ? .secondary : .primary)
            .lineLimit(1)
    }
}

private struct LiveNameCell: View {
    let row: LiveRow

    var body: some View {
        if row.isMember {
            HStack(spacing: 6) {
                Text(row.name).lineLimit(1).truncationMode(.middle)
                if let pid = row.pid {
                    Text("pid \(pid)").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, 6)
        } else {
            HStack(spacing: 8) {
                ResourceAppLabel(key: row.key)
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
        }
    }
}
