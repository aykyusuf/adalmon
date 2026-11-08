import SwiftUI

/// "Ajan ofisi": canlı Claude oturumları ve alt ajanları pixel-art bir ofiste. Sahne yalnızca bu sayfa açıkken ve pencere
/// görünürken çalışır; olay gelince yalnızca ilgili karakter güncellenir.
struct AgentOfficePage: View {
    let model: AppModel
    let router: SettingsRouter
    /// Demo açıkken sahte oturumlar (paylaşılan `AgentMonitorModel`'e yazılmaz: menü çubuğu/panel sayıları etkilenmez).
    @State private var demoSessions: [AgentSession]?
    @State private var demoTask: Task<Void, Never>?

    var body: some View {
        let sessions = demoSessions ?? model.agents.monitor.state.orderedSessions
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: MainSection.agentOffice.title) {
                HStack(spacing: 10) {
                    if !sessions.isEmpty {
                        let working = sessions.reduce(0) { $0 + $1.workingCount }
                        Text("\(working) çalışan ajan · \(sessions.count) oturum").font(.callout).foregroundStyle(.secondary)
                    }
                    demoMenu
                }
            }
            OfficeSceneView(members: OfficeMember.members(from: sessions))
                .clipShape(.rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08)))
                .frame(minHeight: 360)
                .accessibilityLabel("Ajan ofisi: \(sessions.count) oturum")
            if sessions.isEmpty { emptyState }
        }
        .padding(24)
        .onDisappear { stopDemo() }
    }

    private var demoMenu: some View {
        Menu {
            if demoTask == nil {
                Button("Demo'yu başlat", systemImage: "play.fill") { startDemo() }
            } else {
                Button("Demo'yu durdur", systemImage: "stop.fill") { stopDemo() }
            }
        } label: {
            Label("Demo", systemImage: "wand.and.stars")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sahte oturum ve alt ajanlarla ofisi dener; gerçek veriyi etkilemez")
    }

    @ViewBuilder
    private var emptyState: some View {
        let enabled = model.prefs.agentsEnabled
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Henüz ajan olayı yok", systemImage: "person.3").font(.callout.weight(.medium))
                Text(enabled
                     ? "Yeni bir Claude Code oturumu açın; oturumlar ve alt ajanlar ofiste canlı görünür. Plugin kurulu değilse Ayarlar › Claude ajanları'ndan kurun."
                     : "Claude ajanları özelliği kapalı. Açıp plugin'i kurduğunuzda oturumlar ve alt ajanlar ofiste canlı görünür.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(enabled ? "Claude ajanları ayarları" : "Özelliği aç") { router.open(.agents) }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
    }

    private func startDemo() {
        stopDemo()
        demoTask = Task {
            let steps = OfficeDemo.steps()
            demoSessions = steps[0]
            var i = 1
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(OfficeDemo.stepInterval))
                if Task.isCancelled { break }
                demoSessions = steps[i % steps.count]
                i += 1
            }
        }
    }

    private func stopDemo() {
        demoTask?.cancel()
        demoTask = nil
        demoSessions = nil
    }
}
