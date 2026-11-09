import SwiftUI

/// Ofis sahnesi + sağ üstte tek tıkla açılan detay kartı. Hem ana pencere sayfasında hem ayrı pencerede kullanılır.
/// Işık modu `@AppStorage` ile (`officeLightingMode`) okunur; menü aynı anahtarı yazar.
struct OfficeSceneContainer: View {
    let members: [OfficeMember]
    @Binding var selectedRoom: String?
    /// Pano (kiosk) düzeni: ayrı pencere tam ekranda ya da "Hep" iken true.
    var panoActive = false
    /// Oturum kartındaki "Küçült" düğmesi (oturum kimliği); nil ise düğme çıkmaz (ör. demo).
    var onMinimize: ((String) -> Void)?
    @AppStorage(OfficeLighting.defaultsKey) private var lightingRaw = OfficeLightingMode.auto.rawValue
    @AppStorage(OfficeTheme.defaultsKey) private var themeRaw = OfficeTheme.default.rawValue
    @State private var card: OfficeDetailCard?

    var body: some View {
        OfficeSceneView(members: members, selectedRoom: $selectedRoom, lightingMode: OfficeLightingMode(rawValue: lightingRaw) ?? .auto,
                        theme: OfficeTheme(rawValue: themeRaw) ?? .default, panoActive: panoActive, card: $card)
            .overlay(alignment: .topTrailing) {
                if let card {
                    OfficeCardView(card: card, onMinimize: onMinimize.map { f in { f(card.memberID); self.card = nil } }) { self.card = nil }
                        .padding(10)
                        .transition(.opacity)
                }
            }
    }
}

/// "Işık: Otomatik / Gün / Gece" menüsü (sayfa başlığı ve ayrı pencere seçenek menüsü).
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
        .frame(width: 250)
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
