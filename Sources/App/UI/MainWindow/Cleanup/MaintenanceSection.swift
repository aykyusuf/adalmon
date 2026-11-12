import SwiftUI

/// Bakım: yalnızca bilgi + kopyala. Hiçbir komut çalıştırılmaz (yönetici gerektirenler Terminal'de elle çalıştırılır).
struct MaintenanceSection: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label(MaintenanceInfo.terminalNote, systemImage: "terminal")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
                ForEach(MaintenanceInfo.topics) { MaintenanceTopicCard(topic: $0) }
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
    }
}

private struct MaintenanceTopicCard: View {
    let topic: MaintenanceTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(topic.title, systemImage: topic.symbol).font(.headline)
            Text(topic.summary).font(.callout).fixedSize(horizontal: false, vertical: true)
            ForEach(topic.notes, id: \.self) { note in
                Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
            if let warning = topic.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
            ForEach(topic.commands) { MaintenanceCommandRow(command: $0) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }
}

private struct MaintenanceCommandRow: View {
    let command: MaintenanceCommand
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(command.caption).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(command.text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.opacity(0.6), in: .rect(cornerRadius: 6))
                Button(copied ? "Kopyalandı" : "Kopyala", systemImage: copied ? "checkmark" : "doc.on.doc", action: copy)
                    .help("Komutu panoya kopyalar; çalıştırmaz")
            }
            if command.needsAdmin {
                Text("Terminal'de çalıştırman gerekir, yönetici parolası ister.").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func copy() {
        ProcessActions.copy(command.text)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
