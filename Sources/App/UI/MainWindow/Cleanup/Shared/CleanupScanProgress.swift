import SwiftUI

/// Tarama ekranındaki adım satırı.
struct CleanupScanStepInfo: Identifiable, Equatable {
    enum State: Equatable { case pending, active, done }

    let id: String
    var title: String
    var state: State
    /// Biten adımın sağında gösterilen kısa sonuç (ör. boyut).
    var trailing: String?

    init(id: String, title: String, state: State, trailing: String? = nil) {
        self.id = id
        self.title = title
        self.state = state
        self.trailing = trailing
    }
}

/// Tarama ekranı: büyük ilerleme halkası (değer değişince yumuşakça dolar; sürekli dönmez), o an taranan yer,
/// isteğe bağlı adım listesi ve "Durdur". `fraction` nil ise (süre bilinmiyor) halkanın ortasında sistem göstergesi çıkar.
struct CleanupScanProgress: View {
    let accent: CleanupAccent
    let symbol: String
    /// 0...1; nil = bilinmiyor.
    var fraction: Double?
    let title: String
    var detail: String?
    var steps: [CleanupScanStepInfo] = []
    var onStop: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(accent: CleanupAccent, symbol: String, fraction: Double? = nil, title: String, detail: String? = nil,
         steps: [CleanupScanStepInfo] = [], onStop: (() -> Void)? = nil) {
        self.accent = accent
        self.symbol = symbol
        self.fraction = fraction
        self.title = title
        self.detail = detail
        self.steps = steps
        self.onStop = onStop
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            ring
            VStack(spacing: 4) {
                Text(title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                if let detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            .frame(maxWidth: 460)
            if !steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(steps) { step in stepRow(step) }
                }
                .padding(14)
                .frame(maxWidth: 380)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 14))
            }
            if let onStop {
                Button("Durdur", action: onStop).controlSize(.large)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var ring: some View {
        let value = max(0.015, min(1, fraction ?? 0))
        return ZStack {
            Circle().fill(RadialGradient(colors: [accent.base.opacity(0.22), accent.base.opacity(0)], center: .center, startRadius: 40, endRadius: 100))
                .frame(width: 200, height: 200)
            Circle().stroke(accent.base.opacity(0.16), lineWidth: 13).frame(width: 150, height: 150)
            if fraction != nil {
                Circle().trim(from: 0, to: value)
                    .stroke(LinearGradient(colors: [accent.light, accent.deep], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 13, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 150, height: 150)
                    .shadow(color: accent.base.opacity(0.5), radius: 6)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: value)
            }
            if fraction != nil {
                VStack(spacing: 2) {
                    Image(systemName: symbol).font(.system(size: 30, weight: .semibold)).foregroundStyle(accent.gradient)
                    Text(Format.percent(value)).font(.callout.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: value))
                        .animation(reduceMotion ? nil : .smooth, value: value)
                }
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .frame(width: 170, height: 170)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(fraction.map { Format.percent($0) } ?? "")
    }

    private func stepRow(_ step: CleanupScanStepInfo) -> some View {
        HStack(spacing: 8) {
            Group {
                switch step.state {
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .active: ProgressView().controlSize(.small)
                case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 16)
            Text(step.title).foregroundStyle(step.state == .pending ? .tertiary : .primary)
            Spacer(minLength: 8)
            if let trailing = step.trailing {
                Text(trailing).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }
}
