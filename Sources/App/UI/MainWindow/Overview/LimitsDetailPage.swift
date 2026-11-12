import SwiftUI

/// Genel bakıştaki limit karosuna tıklayınca açılan ayrıntı sayfası (Genel bakış içinde, geri düğmeli). Claude ve Codex için ayrı
/// bölümler; her pencere için büyük halka, yenilenme geri sayımı, dolma tahmini, kullanım hızı, veri yaşı ve eşikler.
/// Pil: görünürken `addViewer` ile veri güncellenir; geri sayım dakikalık TimelineView (yalnızca görünürken); sürekli animasyon yok.
struct LimitsDetailPage: View {
    let model: SubscriptionLimitsModel
    let agentsEnabled: Bool
    let onBack: () -> Void
    let openSettings: () -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            LimitsDetailContent(snapshot: model.snapshot(agentsEnabled: agentsEnabled, now: context.date),
                                onBack: onBack, openSettings: openSettings)
        }
        .onAppear { model.addViewer() }
        .onDisappear { model.removeViewer() }
    }
}

struct LimitsDetailContent: View {
    let snapshot: LimitsSnapshot
    let onBack: () -> Void
    let openSettings: () -> Void
    var entrance = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Button(action: onBack) {
                    Label("Genel bakış", systemImage: "chevron.left").font(.callout.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("Genel bakışa döner")
                PageHeader(title: "Limitler")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(snapshot.sections) { section in
                        ProviderSection(section: section, snapshot: snapshot, entrance: entrance, openSettings: openSettings)
                    }
                    ThresholdFooter(thresholds: snapshot.thresholds, openSettings: openSettings)
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.never)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SectionCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
    }
}

private struct ProviderSection: View {
    let section: LimitSection
    let snapshot: LimitsSnapshot
    let entrance: Bool
    let openSettings: () -> Void

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                switch section.state {
                case .data(let display):
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) { windows(display) }
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 14) { windows(display) }
                    }
                    .opacity(display.isStale ? 0.7 : 1)
                case .empty(let reason):
                    EmptyProvider(reason: reason, openSettings: openSettings)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func windows(_ display: LimitProviderDisplay) -> some View {
        ForEach(LimitWindowKind.allCases) { kind in
            if let window = display.window(kind) {
                WindowPanel(window: window, now: snapshot.now, entrance: entrance)
            } else {
                MissingWindow(kind: kind)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: LimitStyle.symbol(section.source))
                .font(.system(size: 13, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.15), in: .circle)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(section.source.displayName).font(.title3.weight(.semibold))
            Spacer(minLength: 8)
            if let display = section.display {
                if let balance = display.creditsBalance {
                    Chip(text: "Kredi \(balance.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "tr_TR"))))",
                         color: .secondary)
                }
                Chip(text: display.freshnessText(now: snapshot.now), color: display.isStale ? .orange : .green)
            }
        }
    }
}

private struct Chip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(color))
            .background(color.opacity(0.14), in: .capsule)
    }
}

/// Bir pencerenin büyük halkası ve ayrıntıları.
private struct WindowPanel: View {
    let window: LimitWindowDisplay
    let now: Date
    let entrance: Bool

    var body: some View {
        let color = LimitStyle.color(window.tone)
        HStack(alignment: .center, spacing: 16) {
            VStack(spacing: 6) {
                LimitRing(fraction: window.fraction, tone: window.tone, diameter: 112, lineWidth: 11, label: window.percentText,
                          labelFont: .system(size: 26, weight: .bold, design: .rounded),
                          markers: window.isReset ? [] : [window.warnAt / 100, window.criticalAt / 100], entrance: entrance)
                Text(window.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(window.tone == .muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(color))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(window.kind.windowTitle).font(.headline)
                resetBlock
                if let elapsed = window.elapsedFraction(now: now), !window.isReset {
                    VStack(alignment: .leading, spacing: 3) {
                        LimitBar(fraction: elapsed, tint: .secondary, height: 4, entrance: entrance)
                        Text("Pencerenin %\(Int((elapsed * 100).rounded()))'i geçti")
                            .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    }
                }
                forecastBlock
                Text(LimitsPresentation.thresholdText(window))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var resetBlock: some View {
        if window.isReset {
            Label("Pencere yenilendi; yeni değer bekleniyor", systemImage: "arrow.clockwise")
                .font(.callout).foregroundStyle(.secondary)
        } else if let resetsAt = window.resetsAt, let countdown = window.countdownText(now: now) {
            VStack(alignment: .leading, spacing: 1) {
                Text(countdown)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.smooth, value: countdown)
                Text("sonra yenilenir · \(LimitForecastFormat.moment(resetsAt, kind: window.kind, now: now))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        } else {
            Text("Yenilenme zamanı bilinmiyor").font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var forecastBlock: some View {
        if let forecast = window.forecast {
            VStack(alignment: .leading, spacing: 1) {
                Label(window.forecastText(now: now) ?? "", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium)).foregroundStyle(.orange)
                if let rate = window.rateText {
                    Text("Kullanım hızı \(rate)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        } else if window.isStale {
            Text("Veri eski; tahmin gösterilmiyor").font(.caption).foregroundStyle(.tertiary)
        } else if !window.isReset {
            Text("Dolma tahmini yok").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var accessibilityText: String {
        var parts = ["\(window.kind.windowTitle): \(window.percentText) kullanıldı", window.statusText]
        if let countdown = window.countdownText(now: now) { parts.append("\(countdown) sonra yenilenir") }
        if let forecast = window.forecast { parts.append(LimitForecastFormat.cardLine(forecast, kind: window.kind, now: now)) }
        return parts.joined(separator: ", ")
    }
}

private struct MissingWindow: View {
    let kind: LimitWindowKind

    var body: some View {
        HStack(spacing: 16) {
            LimitRing(fraction: 0, tone: .muted, diameter: 112, lineWidth: 11, label: "—",
                      labelFont: .system(size: 26, weight: .bold, design: .rounded), entrance: false)
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.windowTitle).font(.headline)
                Text("Bu pencere için veri gelmedi").font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 12))
    }
}

private struct EmptyProvider: View {
    let reason: LimitEmptyReason
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            LimitRing(fraction: 0, tone: .muted, diameter: 64, lineWidth: 7, label: "—",
                      labelFont: .system(size: 16, weight: .bold, design: .rounded), entrance: false)
            VStack(alignment: .leading, spacing: 4) {
                Text(reason.title).font(.headline)
                Text(reason.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let title = reason.actionTitle {
                Button(title, action: openSettings).buttonStyle(.borderedProminent).controlSize(.regular)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

private struct ThresholdFooter: View {
    let thresholds: LimitAlertThresholds
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(thresholds.notificationsEnabled ? "Bildirimler açık" : "Bildirimler kapalı",
                      systemImage: thresholds.notificationsEnabled ? "bell.fill" : "bell.slash")
                    .font(.callout.weight(.medium))
                Text("5 saat: uyarı \(LimitFormat.percent(thresholds.fiveHourWarn)), kritik \(LimitFormat.percent(thresholds.fiveHourCritical))"
                     + " · Haftalık: uyarı \(LimitFormat.percent(thresholds.weeklyWarn)), kritik \(LimitFormat.percent(thresholds.weeklyCritical))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Text("Değerler yalnızca bu Mac'teki Claude Code ve Codex verisinden okunur; hesap bilgisi tutulmaz. Halkadaki çentikler eşikleri gösterir.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Button(action: openSettings) {
                Label("Ayarlar › Claude ajanları", systemImage: "gearshape").font(.callout)
            }
            .buttonStyle(.link)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: .rect(cornerRadius: 14))
    }
}
