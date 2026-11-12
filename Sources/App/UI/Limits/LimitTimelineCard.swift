import SwiftUI

/// Sayfadaki düz bölüm kartı.
struct LimitSectionCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(scheme == .dark ? 0.06 : 0.045), in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(scheme == .dark ? 0.07 : 0.5), lineWidth: 1))
    }
}

/// Yenilenme zaman çizelgesi: her pencerede "şimdi" nerede, ne kadarı geçti, ne kadarı kullanıldı ve (varsa) bu hızla nerede dolacağı.
struct LimitTimelineCard: View {
    let snapshot: LimitsSnapshot
    var entrance = true

    private var rows: [(source: LimitSource, window: LimitWindowDisplay)] { LimitsPresentation.timelineRows(snapshot) }

    var body: some View {
        LimitSectionCard {
            VStack(alignment: .leading, spacing: 16) {
                Label("Yenilenme zaman çizelgesi", systemImage: "calendar.badge.clock").font(.headline)
                if rows.isEmpty {
                    Text("Yenilenme zamanı bilinen pencere yok.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        LimitTimelineRow(source: row.source, window: row.window, now: snapshot.now, entrance: entrance, delay: 0.3 + 0.1 * Double(index))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct LimitTimelineRow: View {
    let source: LimitSource
    let window: LimitWindowDisplay
    let now: Date
    let entrance: Bool
    let delay: Double

    @State private var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(source: LimitSource, window: LimitWindowDisplay, now: Date, entrance: Bool, delay: Double) {
        self.source = source
        self.window = window
        self.now = now
        self.entrance = entrance
        self.delay = delay
        _shown = State(initialValue: !entrance)
    }

    private static let trackHeight: CGFloat = 12

    var body: some View {
        let brand = LimitBrand.color(source)
        let elapsed = window.elapsedFraction(now: now) ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(brand.gradient).frame(width: 9, height: 9)
                Text("\(source.displayName) · \(window.kind.windowTitle)").font(.callout.weight(.semibold))
                Spacer(minLength: 8)
                if let countdown = window.countdownText(now: now), let resetsAt = window.resetsAt {
                    Text("\(countdown) sonra · \(LimitForecastFormat.moment(resetsAt, kind: window.kind, now: now))")
                        .font(.callout).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .smooth, value: countdown)
                }
            }
            track(elapsed: elapsed, brand: brand)
            usageBar
            HStack {
                if let start = window.startsAt {
                    Text("Başlangıç \(LimitForecastFormat.moment(start, kind: window.kind, now: now))")
                }
                Spacer(minLength: 8)
                Text("Süre %\(Int((elapsed * 100).rounded())) geçti · Kullanım \(window.percentText)").monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        .onAppear {
            guard !shown else { return }
            if reduceMotion { shown = true } else { withAnimation(.easeOut(duration: 0.9).delay(delay)) { shown = true } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(elapsed: elapsed))
    }

    private func track(elapsed: Double, brand: Color) -> some View {
        let value = shown ? elapsed : 0
        let ticks = window.kind == .fiveHour ? 5 : 7
        return GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule()
                    .fill(LinearGradient(colors: [brand.opacity(0.3), brand.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(Self.trackHeight, width * value))
                ForEach(1..<ticks, id: \.self) { index in
                    Rectangle().fill(Color.primary.opacity(0.18)).frame(width: 1, height: Self.trackHeight - 4)
                        .offset(x: width * Double(index) / Double(ticks))
                }
                if let fill = window.forecastFraction, fill > elapsed {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.orange)
                        .background(Circle().fill(.background).padding(2))
                        .position(x: width * fill, y: geo.size.height / 2)
                        .opacity(shown ? 1 : 0)
                        .help("Bu hızla burada dolar")
                }
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(brand, lineWidth: 3))
                    .shadow(color: .black.opacity(0.28), radius: 3, y: 1.5)
                    .position(x: max(9, min(width - 9, width * value)), y: geo.size.height / 2)
            }
        }
        .frame(height: 18)
        .animation(reduceMotion ? nil : .smooth(duration: 0.7), value: elapsed)
    }

    private var usageBar: some View {
        LimitBar(fraction: window.fraction, tint: LimitBrand.ringColor(window.tone, source: source), height: 5, entrance: entrance)
    }

    private func accessibilityText(elapsed: Double) -> String {
        var parts = ["\(source.displayName) \(window.kind.windowTitle)", "süre yüzde \(Int((elapsed * 100).rounded())) geçti",
                     "\(window.percentText) kullanıldı"]
        if let resetsAt = window.resetsAt { parts.append(LimitFormat.resetText(resetsAt, now: now)) }
        if let forecast = window.forecast { parts.append(LimitForecastFormat.cardLine(forecast, kind: window.kind, now: now)) }
        return parts.joined(separator: ", ")
    }
}
