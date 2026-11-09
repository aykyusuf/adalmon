import SwiftUI

/// Üst katmanın (sayfa/pencere) ofis sahnesine verdiği komutlar. Sahne kendini buraya kaydeder; kayıtlı değilse komut hemen tamamlanır.
@MainActor
final class OfficeSceneCommands {
    var tuckHandler: ((String, @escaping @MainActor () -> Void) -> Void)?

    /// Odayı sola süzülerek küçültür; animasyon bitince `completion` çağrılır (küçültmeyi uygulayan kod orada çalışır).
    func tuck(_ id: String, completion: @escaping @MainActor () -> Void) {
        if let tuckHandler { tuckHandler(id, completion) } else { completion() }
    }
}

/// Sol kenardaki Stage Manager tarzı "uykuda" şeridi. Kapalıyken yalnızca ince renkli çentikler görünür (her oturum için bir tane);
/// fare sol kenara gelince kartlar soldan süzülerek açılır, tıklanan oturum yeniden oda olur. Yeni bir oturum uykuya geçince
/// şerit kısa süre kendiliğinden açılıp nereye gittiğini gösterir. Boşta zamanlayıcı yoktur (kapanma tek seferlik gecikmedir).
struct OfficeSleepRail: View {
    let sessions: [AgentSession]
    let onRestore: (String) -> Void
    @State private var revealed = false
    @State private var hideTask: Task<Void, Never>?
    @State private var knownCount = 0

    var body: some View {
        if !sessions.isEmpty {
            ZStack(alignment: .leading) {
                Color.clear.frame(width: revealed ? 214 : 26, height: 440)
                if revealed {
                    cards.transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    notches.transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(.rect)
            .onHover { inside in
                if inside { reveal() } else { scheduleHide(after: 0.35) }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: revealed)
            .onChange(of: sessions.count) { _, new in
                if new > knownCount { reveal(); scheduleHide(after: 1.8) }
                knownCount = new
            }
            .onAppear { knownCount = sessions.count }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Uykuda olan oturumlar: \(sessions.count)")
        }
    }

    private var notches: some View {
        VStack(spacing: 6) {
            ForEach(sessions.prefix(8)) { s in
                Capsule().fill(s.badge.tint.opacity(0.85)).frame(width: 5, height: 24)
                    .shadow(color: .black.opacity(0.25), radius: 2)
            }
        }
        .padding(.leading, 6)
        .accessibilityHidden(true)
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Uykuda", systemImage: "moon.zzz.fill")
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.leading, 4)
            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    ForEach(sessions) { s in OfficeSleepCard(session: s) { onRestore(s.id) } }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(width: 200)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.22), radius: 10, x: 2)
        .padding(.leading, 8)
    }

    private func reveal() {
        hideTask?.cancel()
        if !revealed { revealed = true }
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            revealed = false
        }
    }
}

/// Şeritteki tek kart: model renkli üst şerit, oturum adı, durum ve boşta süresi. Üzerine gelince hafif öne çıkar.
struct OfficeSleepCard: View {
    let session: AgentSession
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle().fill(session.status.tint).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(session.displayName).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    AgentModelBadgeView(badge: session.badge)
                    Text(session.status.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 60)) { ctx in
                        Text(SessionDormancy.idleText(since: session.lastEventAt, now: ctx.date))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                }
                if let project = session.secondaryName {
                    Text(project).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(session.badge.tint).frame(width: 3).padding(.vertical, 6)
            }
            .background(.quaternary.opacity(hovering ? 0.95 : 0.55), in: .rect(cornerRadius: 10))
            .scaleEffect(hovering ? 1.03 : 1)
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("\(session.displayName) · \(session.badge.label) · \(session.status.label): odayı aç")
        .accessibilityLabel("\(session.displayName), \(session.badge.label), \(session.status.label)")
        .accessibilityHint("Odayı açar")
    }
}

/// Üzerine gelinen odanın köşesinde beliren yuvarlak "küçült" düğmesi.
struct OfficeMinimizeButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus").font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(.regularMaterial, in: .circle)
                .overlay(Circle().strokeBorder(.white.opacity(hovering ? 0.35 : 0.18)))
                .scaleEffect(hovering ? 1.1 : 1)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("Odayı küçült: sol kenara iner, üstüne gelince geri açabilirsin")
        .accessibilityLabel("Odayı küçült")
    }
}
