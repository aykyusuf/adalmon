import SwiftUI

/// Ofis sahnesi + sağ üstte tek tıkla açılan detay kartı. Hem ana pencere sayfasında hem ayrı pencerede kullanılır.
/// Işık modu `@AppStorage` ile (`officeLightingMode`) okunur; menü aynı anahtarı yazar.
struct OfficeSceneContainer: View {
    let members: [OfficeMember]
    @Binding var selectedRoom: String?
    @AppStorage(OfficeLighting.defaultsKey) private var lightingRaw = OfficeLightingMode.auto.rawValue
    @AppStorage(OfficeTheme.defaultsKey) private var themeRaw = OfficeTheme.default.rawValue
    @State private var card: OfficeDetailCard?

    var body: some View {
        OfficeSceneView(members: members, selectedRoom: $selectedRoom, lightingMode: OfficeLightingMode(rawValue: lightingRaw) ?? .auto,
                        theme: OfficeTheme(rawValue: themeRaw) ?? .default, card: $card)
            .overlay(alignment: .topTrailing) {
                if let card {
                    OfficeCardView(card: card) { self.card = nil }
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
        }
        .padding(12)
        .frame(width: 250)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
        .accessibilityElement(children: .contain)
    }
}
