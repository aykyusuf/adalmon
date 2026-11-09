import SwiftUI

/// Ofis başlığında "hat sağlığı": son olay ne zaman geldi; tıklayınca ayrıntı ve "Hattı test et" (gerçek hook betiğiyle uçtan uca).
struct AgentHookHealthChip: View {
    let agents: AgentService
    @State private var shown = false

    private enum Level { case off, waiting, healthy, quiet, broken }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { ctx in
            let (level, text) = status(now: ctx.date)
            Button { shown.toggle() } label: {
                HStack(spacing: 5) {
                    Circle().fill(color(level)).frame(width: 7, height: 7)
                    Text(text).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.quaternary.opacity(0.6), in: .capsule)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $shown, arrowEdge: .bottom) { details(now: ctx.date) }
            .help("Claude oturumlarından gelen olayların durumu")
            .accessibilityLabel("Ajan hattı: \(text)")
        }
    }

    private func status(now: Date) -> (Level, String) {
        guard case .running = agents.listener else { return (.off, "Hat kapalı") }
        if let test = agents.selfTest, !test.isHealthy { return (.broken, "Hat sorunlu") }
        guard let last = agents.monitor.lastEventAt else { return (.waiting, "Olay bekleniyor") }
        let ago = max(0, Int(now.timeIntervalSince(last)))
        return (ago > 600 ? .quiet : .healthy, "Son olay " + (ago < 60 ? "\(ago) sn" : ago < 3600 ? "\(ago / 60) dk" : "\(ago / 3600) sa") + " önce")
    }

    private func color(_ level: Level) -> Color {
        switch level {
        case .healthy: .green
        case .waiting, .quiet: .yellow
        case .off: .gray
        case .broken: .red
        }
    }

    @ViewBuilder
    private func details(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ajan hattı").font(.headline)
            Text("Claude oturumları her olayı (oturum, alt ajan, araç) yerel hook betiğiyle bu uygulamaya gönderir. Bir oturum görünmüyorsa buradan hattı uçtan uca sınayabilirsiniz.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let port = agents.port { LabeledContent("Dinleyici", value: "127.0.0.1:\(port)") }
            LabeledContent("Açık oturum", value: "\(agents.monitor.state.sessions.count)")
            if let last = agents.monitor.lastEventAt {
                LabeledContent("Son olay", value: last.formatted(date: .omitted, time: .standard))
            }
            Divider()
            HStack(spacing: 8) {
                Button("Hattı test et", systemImage: "waveform.path.ecg") { Task { await agents.runSelfTest() } }
                    .disabled(agents.isSelfTesting)
                if agents.isSelfTesting { ProgressView().controlSize(.small) }
            }
            if let test = agents.selfTest {
                Label(test.message, systemImage: test.isHealthy ? (test.verdict == .healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill") : "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(test.verdict == .healthy ? Color.green : test.isHealthy ? Color.orange : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
