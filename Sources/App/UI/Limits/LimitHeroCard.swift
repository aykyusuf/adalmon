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

    var body: some View {
        let brand = LimitBrand.color(section.source)
        VStack(alignment: .leading, spacing: 20) {
            LimitHeroHeader(source: section.source, plan: plan, display: section.display, now: snapshot.now)
            switch section.state {
            case .data(let display):
                LimitHeroWindows(display: display, snapshot: snapshot, entrance: entrance, delay: delay, previewTilt: previewTilt)
                    .opacity(display.isStale ? 0.72 : 1)
            case .empty(let reason):
                LimitEmptyHero(source: section.source, reason: reason, openSettings: openSettings, entrance: entrance)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { surface(brand) }
        .clipShape(.rect(cornerRadius: 24))
        .tilt3D(4.5, perspective: 0.8, glossRadius: 320, glossOpacity: 0.12, fixed: previewTilt.map { CGSize(width: $0.width * 0.4, height: $0.height * 0.4) })
        .shadow(color: brand.opacity(scheme == .dark ? 0.22 : 0.2), radius: 20, y: 10)
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

    @Environment(\.limitTilt) private var tilt

    var body: some View {
        let brand = LimitBrand.color(source)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                glyph(brand)
                identity
                Spacer(minLength: 8)
                trailing
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    glyph(brand)
                    identity
                }
                trailing
            }
        }
    }

    private func glyph(_ brand: Color) -> some View {
        Image(systemName: LimitStyle.symbol(source))
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(LinearGradient(colors: [brand.mix(with: .white, by: 0.25), brand.mix(with: .black, by: 0.18)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: brand.opacity(0.45), radius: 8, x: -tilt.width * 4, y: 4 - tilt.height * 3)
            .offset(x: tilt.width * 3, y: tilt.height * 3)
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
    let entrance: Bool
    let delay: Double
    let previewTilt: CGSize?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) { cells }
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 14) { cells }
        }
    }

    @ViewBuilder private var cells: some View {
        ForEach(Array(LimitWindowKind.allCases.enumerated()), id: \.element) { index, kind in
            if let window = display.window(kind) {
                LimitHeroWindowCell(source: display.source, window: window, now: snapshot.now, entrance: entrance,
                                delay: delay + 0.18 + 0.12 * Double(index), previewTilt: previewTilt)
            } else {
                LimitMissingCell(source: display.source, kind: kind)
            }
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

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let color = LimitBrand.ringColor(window.tone, source: source)
        VStack(spacing: 12) {
            Text(window.kind.windowTitle.uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            LimitRing3D(fraction: window.fraction, tone: window.tone, source: source, diameter: 128, lineWidth: 14,
                        label: window.percentText, caption: window.isReset ? nil : "kullanıldı",
                        markers: window.isReset ? [] : [window.warnAt / 100, window.criticalAt / 100], entrance: entrance, delay: delay)
                .padding(.bottom, 16)
                .tilt3D(13, perspective: 0.55, glossOpacity: 0, fixed: previewTilt)
            LimitChip(text: window.statusText, color: window.tone == .muted ? .secondary : color)
            details
        }
        .padding(14)
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
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else if let resetsAt = window.resetsAt, let countdown = window.countdownText(now: now) {
                Text(countdown)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.smooth, value: countdown)
                Text("sonra yenilenir · \(LimitForecastFormat.moment(resetsAt, kind: window.kind, now: now))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            } else {
                Text("Yenilenme zamanı bilinmiyor").font(.callout).foregroundStyle(.secondary)
            }
            forecastBlock
            Text(LimitsPresentation.thresholdText(window)).font(.caption2).foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var forecastBlock: some View {
        if window.forecast != nil {
            VStack(spacing: 2) {
                Label(window.forecastText(now: now) ?? "", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium)).foregroundStyle(.orange)
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

private struct LimitMissingCell: View {
    let source: LimitSource
    let kind: LimitWindowKind

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 12) {
            Text(kind.windowTitle.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(.secondary)
            LimitRing3D(fraction: 0, tone: .muted, source: source, diameter: 128, lineWidth: 14, label: "—", entrance: false)
                .padding(.bottom, 16)
            Text("Bu pencere için veri gelmedi").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(scheme == .dark ? 0.06 : 0.045), in: .rect(cornerRadius: 18))
    }
}

/// Bağlı değil / veri yok durumu: hayalet halka + açıklama + eylem.
private struct LimitEmptyHero: View {
    let source: LimitSource
    let reason: LimitEmptyReason
    let openSettings: () -> Void
    let entrance: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 22) { ghost; text }
            VStack(alignment: .leading, spacing: 14) { ghost; text }
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
