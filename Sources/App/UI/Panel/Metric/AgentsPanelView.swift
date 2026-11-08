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
        let sessions = monitor.state.orderedSessions
        let working = monitor.state.workingAgentCount
        PanelScaffold(kind: .agents, actions: actions, opensMainWindow: opensMainWindow,
                      subtitle: sessions.isEmpty ? nil : "\(working) çalışan ajan · \(sessions.count) oturum", maxHeight: maxHeight) {
            if sessions.isEmpty {
                PanelCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Henüz ajan olayı yok", systemImage: "person.3").font(.callout.weight(.medium))
                        Text("Yeni bir Claude Code oturumu açın; oturumlar ve alt ajanlar burada canlı görünür. Önce Ayarlar › Claude ajanları'ndan özelliği açıp plugin'i kurmanız gerekir.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                PanelCard(padding: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(sessions) { session in
                            AgentSessionRow(session: session).equatable()
                        }
                    }
                }
            }
        } footer: { EmptyView() }
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
        }
    }
}
