import Foundation

// Model bazında kullanımın ekrana hazır hali (USAGE-03): fiyat ağırlıkları, "pencerenin yaklaşık payı", model adı biçimi, sayı biçimi.
// Saf mantık; test fixture'larıyla doğrulanır. Ağırlıklar GERÇEK limit sayacı değildir: model fiyat oranlarına göre yaklaşık
// bir tahmindir ve arayüzde "≈ tahmini" diye belirtilir.

enum ModelPricing {
    /// Göreli maliyet oranları (milyon token başına USD'ye yakın, yalnızca birbirine oranı önemli).
    struct Rates: Equatable, Sendable {
        var input: Double
        var output: Double
        var cacheWrite: Double
        var cacheRead: Double

        init(input: Double, output: Double, cacheWrite: Double? = nil, cacheRead: Double? = nil) {
            self.input = input
            self.output = output
            self.cacheWrite = cacheWrite ?? input * 1.25
            self.cacheRead = cacheRead ?? input * 0.1
        }
    }

    static func rates(for model: String, source: LimitSource) -> Rates {
        let name = model.lowercased()
        switch source {
        case .claude:
            if name.contains("opus") {
                let legacy = name.contains("3-opus") || name.contains("opus-4-1") || name.contains("opus-4-0")
                    || name.contains("opus-4-2025") || name == "claude-opus-4"
                return legacy ? Rates(input: 15, output: 75) : Rates(input: 5, output: 25)
            }
            if name.contains("haiku") { return Rates(input: 1, output: 5) }
            return Rates(input: 3, output: 15)
        case .codex:
            let base: Rates
            if name.contains("nano") { base = Rates(input: 0.05, output: 0.4, cacheWrite: 0.05) }
            else if name.contains("mini") { base = Rates(input: 0.25, output: 2, cacheWrite: 0.25) }
            else { base = Rates(input: 1.25, output: 10, cacheWrite: 1.25) }
            return base
        }
    }

    static func cost(_ tokens: ModelTokens, rates: Rates) -> Double {
        Double(tokens.input) * rates.input + Double(tokens.output) * rates.output
            + Double(tokens.cacheWrite) * rates.cacheWrite + Double(tokens.cacheRead) * rates.cacheRead
    }
}

enum ModelNaming {
    /// "claude-opus-5-5" → "Opus 5.5", "claude-3-5-sonnet-20241022" → "Sonnet 3.5", "gpt-6.1-sol" → "GPT-6.1 Sol".
    static func display(_ id: String) -> String {
        let parts = id.lowercased().split(separator: "-").map(String.init)
        if parts.first == "claude" {
            let families = ["opus", "sonnet", "haiku"]
            guard let family = parts.first(where: { families.contains($0) }) else { return id }
            let numbers = parts.filter { Int($0) != nil && $0.count < 8 }
            let version = numbers.joined(separator: ".")
            let title = family.prefix(1).uppercased() + family.dropFirst()
            return version.isEmpty ? title : "\(title) \(version)"
        }
        if parts.first == "gpt", parts.count >= 2 {
            let head = "GPT-" + parts[1]
            let rest = parts.dropFirst(2).map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return ([head] + rest).joined(separator: " ")
        }
        return id
    }
}

struct ModelUsageRow: Equatable, Identifiable, Sendable {
    /// Ham model kimliği (ya da birleştirilmiş satır için "__other__").
    var id: String
    var name: String
    var tokens: ModelTokens
    var messages: Int
    /// Ağırlıklı maliyet payı (0...1); toplamı 1.
    var costShare: Double
    /// Pencerenin yaklaşık payı (yüzde puanı) = costShare × pencerenin kullanılan yüzdesi; yüzde bilinmiyorsa nil.
    var approxPercent: Double?
    var isOther: Bool { id == ModelUsageBuilder.otherID }
}

struct ModelUsageWindow: Equatable, Sendable {
    var kind: LimitWindowKind
    var start: Date
    var end: Date
    /// Pencerenin kullanılan yüzdesi (limit verisinden); yok/yenilenmişse nil ve pay gösterilmez.
    var usedPercent: Double?
    /// true: gerçek pencere başlangıcı bilinmiyor, son 5 sa / 7 gün alındı.
    var isFallbackRange: Bool
    var rows: [ModelUsageRow]

    var totalTokens: ModelTokens { rows.reduce(ModelTokens()) { $0 + $1.tokens } }
    var totalMessages: Int { rows.reduce(0) { $0 + $1.messages } }
}

struct ProviderModelUsage: Equatable, Sendable {
    var source: LimitSource
    var windows: [ModelUsageWindow]
    var computedAt: Date

    func window(_ kind: LimitWindowKind) -> ModelUsageWindow? { windows.first { $0.kind == kind } }
    var hasRows: Bool { windows.contains { !$0.rows.isEmpty } }
}

enum ModelUsageBuilder {
    static let otherID = "__other__"
    static let maxRows = 5

    struct Range: Equatable, Sendable {
        var kind: LimitWindowKind
        var start: Date
        var end: Date
        var usedPercent: Double?
        var isFallback: Bool
    }

    /// Sağlayıcıda GELEN her pencere için aralık: yenilenme anı biliniyorsa [yenilenme − uzunluk, şimdi] ve kullanılan yüzde;
    /// yoksa/yenilenmişse son 5 sa / 7 gün (yüzde yok). Hiç gelmeyen pencere için aralık üretilmez.
    static func ranges(for limits: ProviderLimits, now: Date) -> [Range] {
        LimitWindowKind.allCases.compactMap { kind in
            guard let window = limits.window(kind) else { return nil }
            if let resets = window.resetsAt, !window.isReset(now: now) {
                return Range(kind: kind, start: min(now, resets.addingTimeInterval(-kind.duration)), end: now,
                             usedPercent: window.usedPercent, isFallback: false)
            }
            return Range(kind: kind, start: now.addingTimeInterval(-kind.duration), end: now, usedPercent: nil, isFallback: true)
        }
    }

    static func build(source: LimitSource, ranges: [Range], now: Date, aggregate: (Date, Date) -> [ModelAggregate]) -> ProviderModelUsage {
        ProviderModelUsage(source: source, windows: ranges.map { range in
            window(source: source, range: range, aggregates: aggregate(range.start, range.end))
        }, computedAt: now)
    }

    static func window(source: LimitSource, range: Range, aggregates: [ModelAggregate]) -> ModelUsageWindow {
        let costs = aggregates.map { ModelPricing.cost($0.tokens, rates: ModelPricing.rates(for: $0.model, source: source)) }
        let totalCost = costs.reduce(0, +)
        var rows = zip(aggregates, costs).map { aggregate, cost -> ModelUsageRow in
            let share = totalCost > 0 ? cost / totalCost : 0
            return ModelUsageRow(id: aggregate.model, name: ModelNaming.display(aggregate.model), tokens: aggregate.tokens,
                                 messages: aggregate.messages, costShare: share, approxPercent: range.usedPercent.map { $0 * share })
        }
        rows.sort { ($0.costShare, $1.id) > ($1.costShare, $0.id) }
        if rows.count > maxRows {
            let rest = rows.dropFirst(maxRows - 1)
            let merged = ModelUsageRow(
                id: otherID, name: "Diğer (\(rest.count) model)", tokens: rest.reduce(ModelTokens()) { $0 + $1.tokens },
                messages: rest.reduce(0) { $0 + $1.messages }, costShare: rest.reduce(0) { $0 + $1.costShare },
                approxPercent: range.usedPercent.map { used in rest.reduce(0) { $0 + $1.costShare } * used })
            rows = Array(rows.prefix(maxRows - 1)) + [merged]
        }
        return ModelUsageWindow(kind: range.kind, start: range.start, end: range.end, usedPercent: range.usedPercent,
                                isFallbackRange: range.isFallback, rows: rows)
    }
}

enum ModelUsageFormat {
    private static func decimal(_ value: Double) -> String {
        let text = String(format: value < 10 ? "%.1f" : "%.0f", value)
        return text.replacingOccurrences(of: ".", with: ",").replacingOccurrences(of: ",0", with: "")
    }

    /// Binlik ayraçlı sayı: "12.340".
    static func count(_ value: Int) -> String { value.formatted(.number.grouping(.automatic).locale(Locale(identifier: "tr_TR"))) }

    /// "950", "12,3K", "4,5Mn", "1,2Mr".
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        if count < 1000 { return "\(count)" }
        if count < 1_000_000 { return decimal(value / 1000) + "K" }
        if count < 1_000_000_000 { return decimal(value / 1_000_000) + "Mn" }
        return decimal(value / 1_000_000_000) + "Mr"
    }

    /// "≈ %23" (küçük paylar için ondalık: "≈ %0,4"); yüzde yoksa nil.
    static func approxPercent(_ value: Double?) -> String? {
        guard let value else { return nil }
        if value > 0, value < 1 { return "≈ %" + String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",") }
        return "≈ %\(Int(value.rounded()))"
    }

    /// "girdi 12K · çıktı 200K · önbellek 1,1Mn".
    static func breakdown(_ tokens: ModelTokens) -> String {
        "girdi \(Self.tokens(tokens.input)) · çıktı \(Self.tokens(tokens.output)) · önbellek \(Self.tokens(tokens.cached))"
    }
}
