import SwiftUI

/// "Bilgi": yol, pid/ppid, kullanıcı, başlangıç, iş parçacığı, imza, coalition, mimari, öncelik.
struct ProcessInfoSheet: View {
    let row: LiveRow
    @Environment(\.dismiss) private var dismiss
    @State private var details: ProcessDetails?
    @State private var architecture: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ResourceAppLabel(key: row.key, size: 36).font(.title2.weight(.semibold))
                Spacer()
            }
            if let d = details {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                    line("Yol", d.path ?? row.path ?? "—")
                    line(row.isMember ? "PID" : "Süreçler", row.isMember ? "\(d.pid)" : "\(row.processCount) süreç · temsilci pid \(d.pid)")
                    line("Üst süreç (ppid)", d.parentPID.map(String.init) ?? "—")
                    line("Kullanıcı", d.user ?? "—")
                    line("Başlangıç", d.startDate.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "—")
                    line("Çalışma süresi", d.uptime().map { PerformanceStatsBuilder.uptime($0) } ?? "—")
                    line("İş parçacığı", d.threads.map(String.init) ?? "—")
                    line("Açık dosya", d.openFiles.map(String.init) ?? "—")
                    line("Öncelik (nice)", d.nice.map(String.init) ?? "—")
                    line("Mimari", architecture ?? "—")
                    line("Kod imzası", signature(d))
                    line("Coalition", d.coalitionID.map(String.init) ?? "—")
                    if d.isSuspended { line("Durum", "Askıda") }
                    if d.isEfficient { line("Durum", "Verimlilik modu") }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            HStack {
                Button("Bilgiyi kopyala", systemImage: "doc.on.doc") { copyAll() }
                Spacer()
                Button("Kapat") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .task {
            guard let pid = row.pid ?? row.pids.min() else { return }
            details = await Task.detached(priority: .userInitiated) { ProcessDetailsReader.read(pid: pid) }.value
            architecture = ProcessDetailsReader.architecture(of: pid)
        }
    }

    private func line(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled).lineLimit(3).truncationMode(.middle)
        }
    }

    private func signature(_ d: ProcessDetails) -> String {
        guard let signed = d.isSigned else { return "Okunamadı" }
        var parts = [signed ? "Geçerli" : "Geçersiz / imzasız"]
        if let id = d.signingIdentifier { parts.append(id) }
        if let team = d.teamIdentifier { parts.append("Takım \(team)") }
        return parts.joined(separator: " · ")
    }

    private func copyAll() {
        guard let d = details else { return }
        let text = [row.name, "Yol: \(d.path ?? "—")", "PID: \(d.pid)", "PPID: \(d.parentPID.map(String.init) ?? "—")",
                    "Kullanıcı: \(d.user ?? "—")", "İmza: \(signature(d))"].joined(separator: "\n")
        ProcessActions.copy(text)
    }
}
