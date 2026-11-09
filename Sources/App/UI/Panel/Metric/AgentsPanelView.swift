import SwiftUI

extension AgentModelBadge {
    var tint: Color {
        switch self {
        case .opus: .purple
        case .sonnet: .blue
        case .haiku: .green
        case .fable: .orange
        case .unknown: .gray
        }
    }
}

extension AgentStatus {
    var tint: Color {
        switch self {
        case .thinking: .blue
        case .tool: .green
        case .waitingPermission: .orange
        case .idle: .gray
        case .done: .teal
        case .ended: Color.secondary.opacity(0.5)
        }
    }
}

/// Claude ajanları paneli: oturum ağacı. Model yalnızca panel açıkken gözlenir; olay gelince yalnızca değişen satırlar çizilir
/// (`AgentSessionRow` Equatable).
struct AgentsPanelView: View {
    let monitor: AgentMonitorModel
    let actions: PanelActions
    let opensMainWindow: Bool
    var maxHeight: CGFloat?

    var body: some View {
        let dock = monitor.dock
        let sessions = dock.open
        let sleeping = dock.minimized
        let working = monitor.state.workingAgentCount
        PanelScaffold(kind: .agents, actions: actions, opensMainWindow: opensMainWindow,
                      subtitle: sessions.isEmpty && sleeping.isEmpty ? nil : "\(working) çalışan ajan · \(sessions.count + sleeping.count) oturum", maxHeight: maxHeight) {
            if sessions.isEmpty && sleeping.isEmpty {
                PanelCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Henüz ajan olayı yok", systemImage: "person.3").font(.callout.weight(.medium))
                        Text("Yeni bir Claude Code oturumu açın; oturumlar ve alt ajanlar burada canlı görünür. Önce Ayarlar › Claude ajanları'ndan özelliği açıp plugin'i kurmanız gerekir.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                if !sessions.isEmpty {
                    PanelCard(padding: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(sessions) { session in
                                AgentSessionRow(session: session).equatable()
                                    .contextMenu { Button("Küçült", systemImage: "minus.rectangle") { monitor.minimize(session.id) } }
                            }
                        }
                    }
                }
                if !sleeping.isEmpty {
                    SleepingSessionsCard(sessions: sleeping) { monitor.restore($0) }
                }
            }
        } footer: { EmptyView() }
        // Arka plan işlemleri yalnızca panel görünürken örneklenir (gözlemci sayacı).
        .onAppear { monitor.addShellObserver() }
        .onDisappear { monitor.removeShellObserver() }
    }
}

struct AgentModelBadgeView: View {
    let badge: AgentModelBadge

    var body: some View {
        Text(badge.label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(badge.tint)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(badge.tint.opacity(0.15), in: .capsule)
    }
}

/// Oturum satırı + girintili alt ajanlar. Eşit oturum → yeniden çizim yok.
struct AgentSessionRow: View, Equatable {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(session.status.tint).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(session.displayName).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.tail)
                AgentModelBadgeView(badge: session.badge)
                Spacer(minLength: 4)
                Text(session.status.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                // Süre kendi kendine ilerler; her saniye görünüm yeniden çizilmez.
                Text(session.startedAt, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)
            // Oturum adı varsa proje klasörü ikincil satırda (küçük, soluk); yoksa proje adı zaten ana başlık.
            if let project = session.secondaryName {
                Text(project).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.tail)
                    .padding(.leading, 14)
            }
            ForEach(session.subagents) { sub in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
                    Circle().fill(sub.status.tint).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text(sub.agentType).font(.caption).lineLimit(1)
                    AgentModelBadgeView(badge: AgentModelBadge(modelID: sub.model))
                    Spacer(minLength: 4)
                    Text(sub.status.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.leading, 16)
                .accessibilityElement(children: .combine)
            }
            if session.shells.total > 0 {
                AgentShellsSection(shells: session.shells).equatable()
            }
        }
    }
}

/// Oturum satırının altında katlanabilir "Arka plan işlemleri (N)" bölümü (N = toplam; 0 ise hiç çizilmez).
/// Yalnızca işlem adı, süre, CPU ve RAM; komut satırı yoktur.
struct AgentShellsSection: View, Equatable {
    let shells: SessionShells
    @State private var expanded = false

    nonisolated static func == (a: Self, b: Self) -> Bool { a.shells == b.shells }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold))
                        .frame(width: 10).accessibilityHidden(true)
                    Image(systemName: "server.rack").font(.caption2).accessibilityHidden(true)
                    Text(SessionShellFormat.title(total: shells.total)).font(.caption)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(SessionShellFormat.title(total: shells.total))
            .accessibilityValue(expanded ? "açık" : "kapalı")
            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(shells.items.map(SessionShellRowModel.init)) { row in
                        HStack(spacing: 6) {
                            Text(row.name).font(.caption).lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 4)
                            Text(row.age).lineLimit(1).frame(width: 62, alignment: .trailing)
                            Text(row.cpu).frame(width: 40, alignment: .trailing)
                            Text(row.ram).frame(width: 56, alignment: .trailing)
                        }
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                    }
                    if let more = SessionShellFormat.more(shells.hidden) {
                        Text(more).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text(SessionShellFormat.footnote).font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.leading, 28)
            }
        }
        .padding(.leading, 16)
    }
}

/// Panelde "Uykuda (N)" bölümü: uzun süre boşta kalan oturumlar tek satırlık sekmeler halinde, varsayılan kapalı.
struct SleepingSessionsCard: View {
    let sessions: [AgentSession]
    let onRestore: (String) -> Void
    @State private var expanded = false

    var body: some View {
        PanelCard(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold)).frame(width: 10)
                            .accessibilityHidden(true)
                        Image(systemName: "moon.zzz.fill").font(.caption).accessibilityHidden(true)
                        Text("Uykuda (\(sessions.count))").font(.callout.weight(.medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(expanded ? "açık" : "kapalı")
                if expanded {
                    ForEach(sessions) { s in
                        Button { onRestore(s.id) } label: {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2).fill(s.badge.tint).frame(width: 3, height: 14).accessibilityHidden(true)
                                Text(s.displayName).font(.caption).lineLimit(1).truncationMode(.tail)
                                Spacer(minLength: 4)
                                Text(SessionDormancy.idleText(since: s.lastEventAt, now: .now)).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 9)).foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .help("Aç")
                        .accessibilityLabel("\(s.displayName), uykuda")
                        .accessibilityHint("Oturumu açar")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
