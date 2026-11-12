import SwiftUI

/// Küçük bilgi hapı (Limitler sayfası).
struct LimitChip: View {
    let text: String
    var systemImage: String?
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .semibold)) }
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .monospacedDigit()
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .foregroundStyle(color == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(color))
        .background(color.opacity(0.15), in: .capsule)
    }
}

/// Sağlayıcı başına büyük "kahraman" kart: marka tonlu cam yüzey, plan rozeti, iki 3D halka (5 saat / haftalık) ve ayrıntılar.
/// İmleç üzerindeyken kart hafifçe eğilir (parallax); eğim yalnızca hover sırasında değişir.
struct LimitHeroCard: View {
    let section: LimitSection
    let plan: LimitPlan?
    let snapshot: LimitsSnapshot
    let openSettings: () -> Void
    var entrance = true
    var delay: Double = 0
    var previewTilt: CGSize?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.limitCardWidth) private var cardWidth

    var body: some View {
        let brand = LimitBrand.color(section.source)
        let metrics = LimitCardMetrics(cardWidth: cardWidth, windowCount: section.display?.windows.count ?? 0)
        VStack(alignment: .leading, spacing: 20) {
            LimitHeroHeader(source: section.source, plan: plan, display: section.display, now: snapshot.now, metrics: metrics)
            switch section.state {
            case .data(let display):
                LimitHeroWindows(display: display, snapshot: snapshot, metrics: metrics, entrance: entrance, delay: delay, previewTilt: previewTilt)
                    .opacity(display.isStale ? 0.72 : 1)
                LimitModelUsageSection(source: section.source, usage: snapshot.modelUsage[section.source], kinds: display.windows.map(\.kind),
                                       entrance: entrance, now: snapshot.now)
            case .empty(let reason):
                LimitEmptyHero(source: section.source, reason: reason, openSettings: openSettings, entrance: entrance, metrics: metrics)
            }
        }
        .padding(LimitCardMetrics.padding)
        // Üst hizalı, kardeş kartla eşit yükseklik (satır `fixedSize(vertical:)` ile en uzun kartın yüksekliğini alır).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { surface(brand) }
        .clipShape(.rect(cornerRadius: 24))
        // Gölge yalnızca yüzey şeklinde: kartın (animasyonlu) içeriği her karede yeniden bulanıklaştırılmaz.
        .background {
            RoundedRectangle(cornerRadius: 24).fill(brand.opacity(0.1))
                .shadow(color: brand.opacity(scheme == .dark ? 0.5 : 0.45), radius: 20, y: 10)
        }
        .tilt3D(4.5, perspective: 0.8, glossRadius: 320, glossOpacity: 0.12, fixed: previewTilt.map { CGSize(width: $0.width * 0.4, height: $0.height * 0.4) })
        .accessibilityElement(children: .contain)
    }

    private func surface(_ brand: Color) -> some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(LinearGradient(colors: [brand.opacity(scheme == .dark ? 0.24 : 0.16), brand.opacity(scheme == .dark ? 0.06 : 0.04)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(LinearGradient(colors: [brand.opacity(0.55), brand.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: 1)
            }
    }
}

/// Başlık: marka simgesi, ad, plan rozeti ve veri tazeliği.
private struct LimitHeroHeader: View {
    let source: LimitSource
    let plan: LimitPlan?
    let display: LimitProviderDisplay?
    let now: Date
    let metrics: LimitCardMetrics

    @Environment(\.limitTilt) private var tilt

    var body: some View {
        let brand = LimitBrand.color(source)
        if metrics.headerOneRow {
            HStack(alignment: .center, spacing: 14) {
                glyph(brand)
                identity
                Spacer(minLength: 8)
                trailing
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    glyph(brand)
                    identity
                }
                trailing
            }
        }
    }

    /// Sağlayıcının kendi logosu (marka renginde), nötr cam bir plakada.
    private func glyph(_ brand: Color) -> some View {
        let plate = RoundedRectangle(cornerRadius: 14)
        let shadowX: CGFloat = -tilt.width * 4
        let shadowY: CGFloat = 4 - tilt.height * 3
        let shiftX: CGFloat = tilt.width * 3
        let shiftY: CGFloat = tilt.height * 3
        let logo = BrandLogo(source: source, size: 26).frame(width: 46, height: 46)
        let framed = logo
            .background(Color.primary.opacity(0.07), in: plate)
            .overlay(plate.strokeBorder(brand.opacity(0.45), lineWidth: 1))
        return framed
            .shadow(color: brand.opacity(0.35), radius: 8, x: shadowX, y: shadowY)
            .offset(x: shiftX, y: shiftY)
            .accessibilityHidden(true)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(source.displayName).font(.title2.weight(.bold))
            HStack(spacing: 6) {
                if let plan {
                    LimitChip(text: plan.title, systemImage: "checkmark.seal.fill", color: LimitBrand.color(source))
                    if let subtitle = plan.subtitle { LimitChip(text: subtitle, color: .secondary) }
                } else {
                    Text("Plan bilgisi yok").font(.caption).foregroundStyle(.tertiary)
                }
            }
            if let plan, let detail = LimitsPresentation.planDetail(plan) {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        if let display {
            HStack(spacing: 6) {
                if let balance = display.creditsBalance {
                    LimitChip(text: "Kredi \(balance.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "tr_TR"))))",
                              systemImage: "creditcard", color: .secondary)
                }
                LimitChip(text: display.freshnessText(now: now), systemImage: display.isStale ? "clock.badge.exclamationmark" : "dot.radiowaves.left.and.right",
                          color: display.isStale ? .orange : .green)
            }
        }
    }
}

private struct LimitHeroWindows: View {
    let display: LimitProviderDisplay
    let snapshot: LimitsSnapshot
    let metrics: LimitCardMetrics
    let entrance: Bool
    let delay: Double
    let previewTilt: CGSize?

    var body: some View {
        if display.windows.count > 1 && metrics.windowsSideBySide {
            // Hücreler eşit yükseklikte (HStack en uzun hücrenin yüksekliğini alır).
            HStack(alignment: .top, spacing: LimitCardMetrics.cellGap) { cells }
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: LimitCardMetrics.cellGap) { cells }
        }
    }

    @ViewBuilder private var cells: some View {
        // Verisi hiç gelmeyen pencere (ör. Claude Ultra'da 5 saatlik) çizilmez; kalan kart tüm genişliği kullanır.
        ForEach(Array(display.windows.enumerated()), id: \.element.kind) { index, window in
            LimitHeroWindowCell(source: display.source, window: window, now: snapshot.now, entrance: entrance,
                                delay: delay + 0.18 + 0.12 * Double(index), previewTilt: previewTilt,
                                diameter: metrics.ringDiameter, compact: metrics.compactCell)
        }
    }
}

/// Bir pencerenin 3D halkası ve altında ayrıntılar (geri sayım, tahmin, hız, eşikler).
struct LimitHeroWindowCell: View {
    let source: LimitSource
    let window: LimitWindowDisplay
    let now: Date
    var entrance = true
    var delay: Double = 0
    var previewTilt: CGSize?
    var diameter: CGFloat = 128
    /// Dar hücre: yazılar küçülür, satırlar kısalır.
    var compact = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let color = LimitBrand.ringColor(window.tone, source: source)
        VStack(spacing: 12) {
            Text(window.kind.windowTitle.uppercased())
                .font(.caption.weight(.bold))
                .tracking(compact ? 0.3 : 0.6)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            LimitRing3D(fraction: window.fraction, tone: window.tone, source: source, diameter: diameter, lineWidth: (diameter * 0.11).rounded(),
                        label: window.percentText, caption: window.isReset ? nil : "kullanıldı",
                        markers: window.isReset ? [] : [window.warnAt / 100, window.criticalAt / 100], entrance: entrance, delay: delay)
                .padding(.bottom, 16)
                .tilt3D(13, perspective: 0.55, glossOpacity: 0, fixed: previewTilt)
            LimitChip(text: window.statusText, color: window.tone == .muted ? .secondary : color)
            details
        }
        .padding(compact ? 10 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(scheme == .dark ? 0.06 : 0.045), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(scheme == .dark ? 0.07 : 0.5), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var details: some View {
        VStack(spacing: 6) {
            if window.isReset {
                Label("Pencere yenilendi; yeni değer bekleniyor", systemImage: "arrow.clockwise")
                    .font(compact ? .caption : .callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let resetsAt = window.resetsAt, let countdown = window.countdownText(now: now) {
                Text(countdown)
                    .font(.system(size: compact ? 18 : 22, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.smooth, value: countdown)
                Text("sonra yenilenir · \(LimitForecastFormat.moment(resetsAt, kind: window.kind, now: now))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Yenilenme zamanı bilinmiyor").font(compact ? .caption : .callout).foregroundStyle(.secondary)
            }
            forecastBlock
            Text(LimitsPresentation.thresholdText(window)).font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var forecastBlock: some View {
        if window.forecast != nil {
            VStack(spacing: 2) {
                Label(window.forecastText(now: now) ?? "", systemImage: "exclamationmark.triangle.fill")
                    .font((compact ? Font.caption : .callout).weight(.medium)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if let rate = window.rateText {
                    Text("Kullanım hızı \(rate)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        } else if window.isStale {
            Text("Veri eski; tahmin gösterilmiyor").font(.caption).foregroundStyle(.tertiary)
        } else if !window.isReset {
            VStack(spacing: 2) {
                Text("Dolma tahmini yok").font(.caption).foregroundStyle(.tertiary)
                if let pace = window.paceText(now: now) { Text(pace).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private var accessibilityText: String {
        var parts = ["\(window.kind.windowTitle): \(window.percentText) kullanıldı", window.statusText]
        if let countdown = window.countdownText(now: now) { parts.append("\(countdown) sonra yenilenir") }
        if let forecast = window.forecast { parts.append(LimitForecastFormat.cardLine(forecast, kind: window.kind, now: now)) }
        return parts.joined(separator: ", ")
    }
}

/// Bağlı değil / veri yok durumu: hayalet halka + açıklama + eylem.
private struct LimitEmptyHero: View {
    let source: LimitSource
    let reason: LimitEmptyReason
    let openSettings: () -> Void
    let entrance: Bool
    let metrics: LimitCardMetrics

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if metrics.headerOneRow {
                HStack(spacing: 22) { ghost; text }
            } else {
                VStack(alignment: .leading, spacing: 14) { ghost; text }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(scheme == .dark ? 0.06 : 0.045), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    private var ghost: some View {
        LimitRing3D(fraction: 0, tone: .muted, source: source, diameter: 104, lineWidth: 12, label: "—", entrance: false)
            .padding(.bottom, 14)
            .tilt3D(13, perspective: 0.55, glossOpacity: 0)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reason.title).font(.title3.weight(.semibold))
            Text(reason.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let title = reason.actionTitle {
                Button(title, action: openSettings).buttonStyle(.borderedProminent).controlSize(.large).tint(LimitBrand.color(source))
            }
        }
    }
}
