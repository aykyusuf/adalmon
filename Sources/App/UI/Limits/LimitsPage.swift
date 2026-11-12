import SwiftUI

/// Kenar çubuğundaki "Limitler" sayfası: Claude ve Codex abonelik limitleri için 3D hissi veren kahraman kartlar, plan rozeti,
/// yenilenme zaman çizelgesi, eşikler ve bildirim durumu.
/// Pil: görünürken `addViewer` ile veri güncellenir; geri sayım `TimelineView(.periodic(by: 60))` (yalnızca görünürken);
/// sürekli animasyon yok — hareket yalnızca ilk görünüşte (bir kez), imleç üzerindeyken ve değer değişince olur.
struct LimitsPage: View {
    let model: SubscriptionLimitsModel
    let agentsEnabled: Bool
    let openSettings: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            LimitsPageContent(snapshot: model.snapshot(agentsEnabled: agentsEnabled, now: context.date), openSettings: openSettings)
        }
        .onAppear { model.addViewer(); model.addUsageViewer() }
        .onDisappear { model.removeViewer(); model.removeUsageViewer() }
    }
}

struct LimitsPageContent: View {
    let snapshot: LimitsSnapshot
    let openSettings: () -> Void
    var entrance: Bool
    /// Yalnızca önizleme/test: imleç olmadan sabit eğim (-1...1).
    var previewTilt: CGSize?

    @State private var appeared: Bool

    init(snapshot: LimitsSnapshot, openSettings: @escaping () -> Void, entrance: Bool = true, previewTilt: CGSize? = nil) {
        self.snapshot = snapshot
        self.openSettings = openSettings
        self.entrance = entrance
        self.previewTilt = previewTilt
        _appeared = State(initialValue: !entrance)
    }

    private static let sidePadding: CGFloat = 24
    /// Kaydırma içeriğinin yanlardaki payı (eğilen kartların ve gölgelerin kesilmemesi için).
    private static let scrollInset: CGFloat = 6
    static let heroSpacing: CGFloat = 18

    /// Kartlar her zaman yan yana (sağlayıcı başına bir sütun, eşit genişlik); alt alta düşme yok. Genişlik tek geçişte
    /// hesaplanır, kartların içi buna uyar (halkalar küçülür, satırlar bölünür).
    static func cardWidth(pageWidth: CGFloat, count: Int) -> CGFloat {
        let columns = CGFloat(max(1, count))
        let available = pageWidth - 2 * sidePadding - 2 * scrollInset - heroSpacing * (columns - 1)
        return max(0, (available / columns).rounded(.down))
    }

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = Self.cardWidth(pageWidth: proxy.size.width, count: snapshot.sections.count)
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: MainSection.limits.title)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Üst hizalı, eşit yükseklik: HStack en uzun kartın yüksekliğini alır, kartlar maxHeight: .infinity ile uzar.
                        HStack(alignment: .top, spacing: Self.heroSpacing) { heroes(cardWidth: cardWidth) }
                            .fixedSize(horizontal: false, vertical: true)
                        LimitTimelineCard(snapshot: snapshot, entrance: entrance)
                            .limitEntrance(appeared, index: 2)
                        LimitThresholdFooter(thresholds: snapshot.thresholds, kinds: snapshot.visibleKinds, openSettings: openSettings)
                            .limitEntrance(appeared, index: 3)
                    }
                    .padding(.horizontal, Self.scrollInset)
                    .padding(.top, 6)
                    .padding(.bottom, 26)
                }
                .scrollIndicators(.never)
                .scrollClipDisabled()
            }
            .padding(.horizontal, Self.sidePadding)
            .padding(.top, 24)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { if !appeared { appeared = true } }
    }

    @ViewBuilder private func heroes(cardWidth: CGFloat) -> some View {
        ForEach(Array(snapshot.sections.enumerated()), id: \.element.source) { index, section in
            LimitHeroCard(section: section, plan: snapshot.plans[section.source], snapshot: snapshot, openSettings: openSettings,
                          entrance: entrance, delay: 0.09 * Double(index), previewTilt: previewTilt)
                .environment(\.limitCardWidth, cardWidth)
                .frame(width: cardWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .limitEntrance(appeared, index: index)
        }
    }
}

/// Eşikler, bildirim durumu ve Ayarlar bağlantısı.
struct LimitThresholdFooter: View {
    let thresholds: LimitAlertThresholds
    var kinds: [LimitWindowKind] = LimitWindowKind.allCases
    let openSettings: () -> Void

    var body: some View {
        LimitSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Eşikler ve bildirimler", systemImage: thresholds.notificationsEnabled ? "bell.badge.fill" : "bell.slash").font(.headline)
                    Spacer(minLength: 8)
                    LimitChip(text: thresholds.notificationsEnabled ? "Bildirimler açık" : "Bildirimler kapalı",
                              color: thresholds.notificationsEnabled ? .green : .secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { cards }
                    VStack(spacing: 10) { cards }
                }
                HStack(alignment: .top, spacing: 12) {
                    Text("Halkadaki çentikler eşikleri gösterir. Limit değerleri yalnızca bu Mac'teki Claude Code ve Codex verisinden okunur. "
                         + "Plan adı için Claude'da ~/.claude.json'daki plan alanları, Codex'te oturum olaylarındaki plan türü okunur; "
                         + "e-posta, ad ve hesap kimliği okunmaz ya da saklanmaz.")
                        .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(action: openSettings) {
                        Label("Ayarlar › Claude ajanları", systemImage: "gearshape").font(.callout).lineLimit(1)
                    }
                    .buttonStyle(.link)
                    .fixedSize()
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var cards: some View {
        ForEach(kinds) { kind in
            let warn = kind == .fiveHour ? thresholds.fiveHourWarn : thresholds.weeklyWarn
            let critical = kind == .fiveHour ? thresholds.fiveHourCritical : thresholds.weeklyCritical
            HStack(spacing: 10) {
                Text(kind.label).font(.callout.weight(.semibold))
                Spacer(minLength: 6)
                LimitChip(text: "Uyarı \(LimitFormat.percent(min(warn, critical)))", color: .orange)
                LimitChip(text: "Kritik \(LimitFormat.percent(max(warn, critical)))", color: .red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 12))
        }
    }
}
