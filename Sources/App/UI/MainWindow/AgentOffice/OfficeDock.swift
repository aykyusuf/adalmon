import SwiftUI

/// Ofisin altında yüzen "uykuda" sekmeleri: uzun süre boşta kalan (ya da elle küçültülen) oturumlar oda yerine buraya iner.
/// Sekmeye tıklayınca oturum yeniden oda olur. Çizim yalnızca küçük oturum varken vardır; boşta zamanlayıcı yoktur
/// (boşta süresi dakikada bir yenilenir).
struct OfficeDock: View {
    let sessions: [AgentSession]
    let onRestore: (String) -> Void

    var body: some View {
        if !sessions.isEmpty {
            HStack(spacing: 8) {
                Label("Uykuda", systemImage: "moon.zzz.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(sessions) { s in OfficeDockChip(session: s) { onRestore(s.id) } }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.regularMaterial, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            .frame(maxWidth: 760)
            .padding(.horizontal, 16).padding(.bottom, 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Uykuda olan oturumlar: \(sessions.count)")
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Tek sekme: model rengi şeridi, durum noktası, oturum adı ve boşta süresi. Üzerine gelince büyür ve "Aç" ipucu görünür.
struct OfficeDockChip: View {
    let session: AgentSession
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(session.badge.tint).frame(width: 3, height: 16).accessibilityHidden(true)
                Circle().fill(session.status.tint).frame(width: 6, height: 6).accessibilityHidden(true)
                Text(session.displayName).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.tail).frame(maxWidth: 130, alignment: .leading)
                TimelineView(.periodic(from: .now, by: 60)) { ctx in
                    Text(SessionDormancy.idleText(since: session.lastEventAt, now: ctx.date))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
                if hovering {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.quaternary.opacity(hovering ? 0.9 : 0.5), in: .rect(cornerRadius: 8))
            .scaleEffect(hovering ? 1.04 : 1)
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("\(session.displayName) · \(session.badge.label) · \(session.status.label) — odayı aç")
        .accessibilityLabel("\(session.displayName), \(session.badge.label), \(session.status.label)")
        .accessibilityHint("Odayı açar")
    }
}
