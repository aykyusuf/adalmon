import SwiftUI

/// Ofis sahnesi + sağ üstte tek tıkla açılan detay kartı. Hem ana pencere sayfasında hem ayrı pencerede kullanılır.
/// Işık modu `@AppStorage` ile (`officeLightingMode`) okunur; menü aynı anahtarı yazar.
struct OfficeSceneContainer: View {
    let members: [OfficeMember]
    @Binding var selectedRoom: String?
    var panoActive = false
    /// Oturumu küçültür (oturum kimliği). nil ise küçült düğmeleri çıkmaz (ör. demo). Animasyonu çağıran taraf `commands` ile yapar.
    var onMinimize: ((String) -> Void)?
    /// Uykudaki (küçük) oturumlar ve geri açma; boşsa sol şerit çıkmaz.
    var sleeping: [AgentSession] = []
    var onRestore: ((String) -> Void)?
    var commands: OfficeSceneCommands?
    /// Oda üstüne gelince çıkan küçült düğmesi etkin mi (tam ekranda hareketsizken kapanır: düğme takılı kalmasın).
    var hoverControlsEnabled = true
    /// Bilgi kartının üst boşluğu (tam ekranda görünür araç şeridinin altında kalması için).
    var cardTopInset: CGFloat = 0
    /// Ofisten cevapla (OFFICE-CTRL-01): bekleyen izin/soru kartları ve kullanıcının kararı. nil ise (demo, testler) hiçbir şey çıkmaz.
    var decisions: PendingDecisionStore?
    var onDecide: ((UUID, DecisionVerdict) -> Void)?
    @Environment(\.controlActiveState) private var controlState
    @AppStorage(OfficeLighting.defaultsKey) private var lightingRaw = OfficeLightingMode.auto.rawValue
    @AppStorage(OfficeTheme.defaultsKey) private var themeRaw = OfficeTheme.default.rawValue
    @State private var card: OfficeDetailCard?
    @State private var hoveredRoom: OfficeRoomHover?
    @State private var overButton = false
    @State private var clearTask: Task<Void, Never>?
    /// Bekleyen karar için kendiliğinden açılan kartın üyesi (sahne seçimi değildir; üyeden her seferinde taze üretilir).
    @State private var decisionMemberID: String?

    var body: some View {
        OfficeSceneView(members: members, selectedRoom: $selectedRoom, lightingMode: OfficeLightingMode(rawValue: lightingRaw) ?? .auto,
                        theme: OfficeTheme(rawValue: themeRaw) ?? .default, panoActive: panoActive, card: $card,
                        commands: commands, onRoomHover: onMinimize == nil ? nil : { roomHover($0) })
            .overlay { minimizeButtonLayer }
            .onChange(of: hoverControlsEnabled) { _, enabled in if !enabled { hoveredRoom = nil; overButton = false } }
            .overlay(alignment: .leading) {
                if let onRestore { OfficeSleepRail(sessions: sleeping, onRestore: onRestore) }
            }
            .overlay(alignment: .topTrailing) {
                if let shown = shownCard {
                    let pending = pendingDecisions(for: shown)
                    OfficeCardView(card: shown, decisions: pending, onDecide: onDecide,
                                   onMinimize: onMinimize.map { f in { f(shown.memberID); closeCard() } }) { closeCard() }
                        .padding(10)
                        .padding(.top, cardTopInset)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomTrailing) { decisionBadge }
            .onChange(of: pendingIDs) { old, new in decisionsChanged(old: old, new: new) }
    }

    // MARK: Bekleyen kararlar

    private var pendingIDs: [UUID] { decisions?.items.map(\.id) ?? [] }

    /// Sahnede seçili kart; yoksa bekleyen karar için kendiliğinden açılan üyenin (güncel) kartı.
    private var shownCard: OfficeDetailCard? {
        var base = card
        if base == nil, let id = decisionMemberID, let member = members.first(where: { $0.id == id }) {
            base = OfficeDetailCard.make(member: member, members: members, spawnedAt: nil)
        }
        guard var shown = base else { return nil }
        shown.pendingDecisions = pendingDecisions(for: shown).count
        return shown
    }

    private func pendingDecisions(for shown: OfficeDetailCard) -> [PendingDecision] {
        guard let items = decisions?.items else { return [] }
        return items.filter { shown.isSession ? $0.sessionID == shown.memberID : memberID(of: $0) == shown.memberID }
    }

    /// Kararın ofis üyesi: alt ajan odada yoksa oturum.
    private func memberID(of decision: PendingDecision) -> String {
        members.contains { $0.id == decision.memberID } ? decision.memberID : decision.sessionID
    }

    private func closeCard() {
        card = nil
        decisionMemberID = nil
    }

    private func decisionsChanged(old: [UUID], new: [UUID]) {
        guard onDecide != nil, let items = decisions?.items else { decisionMemberID = nil; return }
        // Yeni karar geldi ve ofis penceresi önde: kart kendiliğinden açılır. Önde değilse yalnızca rozet görünür.
        if let added = items.first(where: { !old.contains($0.id) }), controlState != .inactive {
            card = nil
            decisionMemberID = memberID(of: added)
        }
        if let id = decisionMemberID, !items.contains(where: { memberID(of: $0) == id || $0.sessionID == id }) { decisionMemberID = nil }
    }

    /// Açık kartta görünmeyen bekleyen istekler için rozet: tıklayınca ilgili kart açılır.
    @ViewBuilder
    private var decisionBadge: some View {
        if onDecide != nil, let items = decisions?.items {
            let shownIDs = Set(shownCard.map { pendingDecisions(for: $0).map(\.id) } ?? [])
            let hidden = items.filter { !shownIDs.contains($0.id) }
            if let first = hidden.first {
                Button { card = nil; decisionMemberID = memberID(of: first) } label: {
                    Label("\(hidden.count) bekleyen istek", systemImage: "hand.raised.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.orange, in: .capsule)
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .padding(12)
                .help("Claude Code bir izin ya da soru için sizi bekliyor")
                .accessibilityLabel("\(hidden.count) bekleyen izin ya da soru isteği")
            }
        }
    }

    /// Fare bir odanın üstündeyken köşesinde "küçült" düğmesi. Oda dışına çıkınca kısa gecikmeyle söner (düğmeye ulaşmak için).
    private func roomHover(_ hover: OfficeRoomHover?) {
        if let hover {
            clearTask?.cancel()
            hoveredRoom = hover
        } else {
            clearTask?.cancel()
            clearTask = Task {
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled, !overButton else { return }
                hoveredRoom = nil
            }
        }
    }

    @ViewBuilder
    private var minimizeButtonLayer: some View {
        if hoverControlsEnabled, let room = hoveredRoom, let onMinimize {
            GeometryReader { geo in
                let x = min(max(room.rect.maxX - 22, 22), geo.size.width - 22)
                let y = min(max(room.rect.minY + 18, 22), geo.size.height - 22)
                OfficeMinimizeButton { hoveredRoom = nil; onMinimize(room.id) }
                    .position(x: x, y: y)
                    .onHover { inside in
                        overButton = inside
                        if inside { clearTask?.cancel() } else { roomHover(nil) }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
            .animation(.easeOut(duration: 0.15), value: room.id)
        }
    }
}

struct OfficeLightingMenu: View {
    @AppStorage(OfficeLighting.defaultsKey) private var lightingRaw = OfficeLightingMode.auto.rawValue

    var body: some View {
        let mode = OfficeLightingMode(rawValue: lightingRaw) ?? .auto
        Picker(selection: $lightingRaw) {
            ForEach(OfficeLightingMode.allCases, id: \.rawValue) { m in Text(m.title).tag(m.rawValue) }
        } label: {
            Label("Işık: \(mode.title)", systemImage: mode == .night ? "moon.fill" : mode == .day ? "sun.max.fill" : "circle.lefthalf.filled")
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help("Ofis ışığı: Otomatik (yerel saate göre gece 19:30–06:30), Gün ya da Gece")
    }
}

/// "Tema: Vektör / Piksel" menüsü (sayfa başlığı ve ayrı pencere seçenek menüsü).
struct OfficeThemeMenu: View {
    @AppStorage(OfficeTheme.defaultsKey) private var themeRaw = OfficeTheme.default.rawValue

    var body: some View {
        let theme = OfficeTheme(rawValue: themeRaw) ?? .default
        Picker(selection: $themeRaw) {
            ForEach(OfficeTheme.allCases, id: \.rawValue) { t in Text(t.title).tag(t.rawValue) }
        } label: {
            Label("Tema: \(theme.title)", systemImage: theme == .vector ? "square.on.circle" : "squareshape.split.3x3")
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help("Ofis görünümü: Vektör (modern, keskin) ya da Piksel (eski)")
    }
}

/// Karakter detay kartı: oturum adı/rol, model rozeti, durum, araç, çalışma süresi sayacı, üst oturum ve alt ajan bilgisi.
struct OfficeCardView: View {
    let card: OfficeDetailCard
    /// Bu kartın oturumu/ajanı için ofiste bekleyen izin/soru istekleri (ilki gösterilir).
    var decisions: [PendingDecision] = []
    var onDecide: ((UUID, DecisionVerdict) -> Void)?
    var onMinimize: (() -> Void)?
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title).font(.headline).lineLimit(2)
                    if let role = card.roleName, !card.isSession { Text(role).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 4)
                Text(card.badge.label)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Kartı kapat")
                    .help("Kapat (Esc)")
            }
            if let first = decisions.first, let onDecide {
                OfficeDecisionView(decision: first, queued: decisions.count - 1, onDecide: onDecide)
                    .id(first.id)
                Divider()
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(card.rows(now: ctx.date).enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.title).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Text(row.value).monospacedDigit().multilineTextAlignment(.trailing).lineLimit(2)
                        }
                        .font(.caption)
                    }
                }
            }
            if card.isSession, card.shellsKnown {
                Divider()
                OfficeCardShells(shells: card.shells)
            } else if card.isSession {
                Divider()
                Text("İşlem bilgisi yok (eski oturum)").font(.caption2).foregroundStyle(.tertiary)
            }
            if !card.children.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(card.children.enumerated()), id: \.offset) { _, c in
                        HStack {
                            Text(c.role).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(c.status).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .font(.caption2)
                    }
                }
            }
            if card.isSession, let onMinimize {
                Divider()
                Button("Küçült", systemImage: "minus.rectangle", action: onMinimize)
                    .controlSize(.small)
                    .help("Oturumu uykuya al: oda kapanır, altta sekme olarak kalır")
            }
        }
        .padding(12)
        .frame(width: decisions.isEmpty ? 250 : 300)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
        .accessibilityElement(children: .contain)
    }
}

/// Kartta "Arka plan işlemleri" listesi: ad, süre, CPU, RAM (N>12 ise "+K daha"); komut satırı yok.
struct OfficeCardShells: View {
    let shells: SessionShells

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(SessionShellFormat.title(total: shells.total), systemImage: "server.rack")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if shells.total == 0 {
                Text("Çalışan arka plan işlemi yok").font(.caption2).foregroundStyle(.tertiary)
            }
            ForEach(shells.items.map(SessionShellRowModel.init)) { row in
                HStack(spacing: 6) {
                    Text(row.name).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(row.age).lineLimit(1).frame(width: 62, alignment: .trailing)
                    Text(row.cpu).frame(width: 36, alignment: .trailing)
                    Text(row.ram).frame(width: 50, alignment: .trailing)
                }
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
            if let more = SessionShellFormat.more(shells.hidden) { Text(more).font(.caption2).foregroundStyle(.tertiary) }
            Text(SessionShellFormat.footnote).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
