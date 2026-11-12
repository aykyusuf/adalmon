import SwiftUI

extension LimitBrand {
    /// Model satırı/çubuk dilimi rengi: marka renginin tonları (sıraya göre); "Diğer" nötr.
    static func modelColor(_ source: LimitSource, index: Int, isOther: Bool = false) -> Color {
        if isOther { return Color.secondary.opacity(0.55) }
        let base = color(source)
        switch index % 5 {
        case 0: return base
        case 1: return base.mix(with: .black, by: 0.32)
        case 2: return base.mix(with: .white, by: 0.38)
        case 3: return base.mix(with: .black, by: 0.55)
        default: return base.mix(with: .white, by: 0.62)
        }
    }
}

/// Sağlayıcı kartındaki "Model dağılımı" bölümü: seçili pencerede hangi modelden ne kadar token kullanıldığı ve limitin yaklaşık ne kadarını
/// tükettiği. Yatay yığılmış çubuk ilk görünüşte ve pencere değişince yumuşakça dolar; sürekli animasyon yok.
/// Paylar gerçek sayaç değil, model fiyat oranlarına göre yaklaşık tahmindir ("≈ tahmini").
struct LimitModelUsageSection: View {
    let source: LimitSource
    let usage: ProviderModelUsage?
    /// Kartta verisi gelen pencereler (sıralı); yalnızca bunlar için sekme gösterilir.
    let kinds: [LimitWindowKind]
    var entrance = true
    var now: Date = .now

    @State private var selected: LimitWindowKind?
    @State private var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.limitCardWidth) private var cardWidth

    private var metrics: LimitCardMetrics { LimitCardMetrics(cardWidth: cardWidth, windowCount: kinds.count) }

    init(source: LimitSource, usage: ProviderModelUsage?, kinds: [LimitWindowKind], entrance: Bool = true, now: Date = .now,
         initialKind: LimitWindowKind? = nil) {
        self.source = source
        self.usage = usage
        self.kinds = kinds
        self.entrance = entrance
        self.now = now
        _selected = State(initialValue: initialKind)
        _shown = State(initialValue: !entrance)
    }

    private var kind: LimitWindowKind? { selected.flatMap { kinds.contains($0) ? $0 : nil } ?? kinds.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let usage, let kind, let window = usage.window(kind) {
                if window.rows.isEmpty {
                    Text("Bu pencerede \(source.displayName) model kullanımı bulunamadı.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    content(window)
                }
            } else {
                Text("Model kullanımı hesaplanıyor…").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .onAppear {
            guard !shown else { return }
            if reduceMotion { shown = true } else { withAnimation(.easeOut(duration: 0.9).delay(0.35)) { shown = true } }
        }
    }

    @ViewBuilder private var header: some View {
        if metrics.usageHeaderOneRow {
            HStack(spacing: 8) { title; Spacer(minLength: 6); picker }
        } else {
            VStack(alignment: .leading, spacing: 8) { title; picker }
        }
    }

    private var title: some View {
        HStack(spacing: 8) {
            Label("Model dağılımı", systemImage: "chart.bar.xaxis").font(.headline).lineLimit(1)
            LimitChip(text: "≈ tahmini", color: .secondary)
                .help("Pay, modellerin yaklaşık fiyat oranına göre ağırlıklı kullanımından tahmin edilir; gerçek limit sayacı değildir.")
        }
    }

    @ViewBuilder private var picker: some View {
        if kinds.count > 1 {
            Picker("Pencere", selection: Binding(get: { kind ?? kinds[0] }, set: { selected = $0 })) {
                ForEach(kinds) { Text($0.shortLabel).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
        } else if let only = kinds.first {
            LimitChip(text: only.windowTitle, color: .secondary)
        }
    }

    private func content(_ window: ModelUsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary(window)).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(2).fixedSize(horizontal: false, vertical: true)
            ModelUsageBar(shares: window.rows.map(\.costShare),
                          colors: window.rows.enumerated().map { LimitBrand.modelColor(source, index: $0.offset, isOther: $0.element.isOther) },
                          shown: shown)
            VStack(spacing: 8) {
                ForEach(Array(window.rows.enumerated()), id: \.element.id) { index, row in
                    ModelUsageRowView(row: row, color: LimitBrand.modelColor(source, index: index, isOther: row.isOther),
                                      showsShare: window.usedPercent != nil, inline: metrics.usageRowsInline)
                }
            }
            Text(footnote(window)).font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: window)
    }

    private func summary(_ window: ModelUsageWindow) -> String {
        let range = window.isFallbackRange ? "Son \(window.kind == .fiveHour ? "5 saat" : "7 gün")" : "\(window.kind.windowTitle) başlangıcından beri"
        let total = window.totalTokens
        return "\(range) · \(ModelUsageFormat.count(window.totalMessages)) mesaj · \(ModelUsageFormat.tokens(total.total)) token"
    }

    private func footnote(_ window: ModelUsageWindow) -> String {
        if let used = window.usedPercent {
            return "≈ pay: modelin ağırlıklı maliyet payı × pencerenin kullanılan %\(Int(used.rounded())) değeri. Ağırlıklar yaklaşık fiyat oranlarıdır (Opus > Sonnet > Haiku); tahmindir."
        }
        return "Pencerenin yenilenme zamanı bilinmediği için yüzde payı hesaplanamadı; yalnızca token sayıları gösteriliyor."
    }
}

/// Yığılmış yatay çubuk: dilim genişlikleri paylarla orantılı; dolum soldan sağa animasyonlanır.
struct ModelUsageBar: View {
    let shares: [Double]
    let colors: [Color]
    let shown: Bool

    var body: some View {
        let total = max(shares.reduce(0, +), 0.0001)
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(shares.enumerated()), id: \.offset) { index, share in
                    Capsule()
                        .fill(colors[index % max(colors.count, 1)].gradient)
                        .frame(width: max(share > 0 ? 4 : 0, (geo.size.width - 2 * CGFloat(max(shares.count - 1, 0))) * share / total))
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .mask(alignment: .leading) { Rectangle().frame(width: shown ? geo.size.width : 0) }
            .animation(.smooth(duration: 0.5), value: shares)
        }
        .frame(height: 14)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .accessibilityHidden(true)
    }
}

private struct ModelUsageRowView: View {
    let row: ModelUsageRow
    let color: Color
    let showsShare: Bool
    /// Dar kartta sayılar adın altına iner, döküm iki satıra kadar sarılır.
    var inline = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 1) {
                if inline {
                    HStack(alignment: .firstTextBaseline, spacing: 6) { name; counts }
                } else {
                    name
                    counts
                }
                Text(ModelUsageFormat.breakdown(row.tokens)).font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    .lineLimit(inline ? 1 : 2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if showsShare, let text = ModelUsageFormat.approxPercent(row.approxPercent) {
                Text(text).font(.callout.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name): \(ModelUsageFormat.tokens(row.tokens.total)) token, \(row.messages) mesaj"
            + (showsShare ? ModelUsageFormat.approxPercent(row.approxPercent).map { ", yaklaşık \($0)" } ?? "" : ""))
    }

    private var name: some View { Text(row.name).font(.callout.weight(.semibold)).lineLimit(1) }

    private var counts: some View {
        Text("\(ModelUsageFormat.tokens(row.tokens.total)) token · \(ModelUsageFormat.count(row.messages)) mesaj")
            .font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
    }
}
