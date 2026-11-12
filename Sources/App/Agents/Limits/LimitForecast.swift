import Foundation

// Limit tahmini (USAGE-02): pencere başına küçük (zaman, kullanılan %) geçmişinden tüketim hızı ve dolma anı tahmini.
// Saf mantık: zamanlayıcı, dosya ya da ağ yok. Geçmiş yalnızca bellekte; "uyarıldı" kaydı modelde ayrı anahtarla kalıcıdır.

/// Tahmin uyarısının duyarlılığı. Yüksek = daha erken/daha düşük kullanımda uyarır; Düşük = yalnızca çok belirgin durumda.
enum LimitForecastSensitivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case low, medium, high

    var id: String { rawValue }
    var title: String {
        switch self {
        case .low: "Düşük"
        case .medium: "Orta"
        case .high: "Yüksek"
        }
    }
}

/// Bir pencere türü ve duyarlılık için uyarı koşulları.
struct LimitForecastRule: Equatable, Sendable {
    /// Şu anki kullanım en az bu kadar olmalı (%).
    var minUsedPercent: Double
    /// Tahmini dolma, yenilenmeden en az bu kadar önce olmalı.
    var minMargin: TimeInterval
    /// Hız en az bu kadar örnekten ve bu kadar zaman aralığından hesaplanmalı.
    var minSamples: Int
    var minSpan: TimeInterval
    /// Hız için yalnızca son örneğe bu kadar yakın örnekler kullanılır.
    var lookback: TimeInterval

    static func rule(_ kind: LimitWindowKind, _ sensitivity: LimitForecastSensitivity) -> Self {
        let minute: TimeInterval = 60, hour: TimeInterval = 3600
        switch (kind, sensitivity) {
        case (.fiveHour, .low): return .init(minUsedPercent: 65, minMargin: 75 * minute, minSamples: 3, minSpan: 15 * minute, lookback: hour)
        case (.fiveHour, .medium): return .init(minUsedPercent: 50, minMargin: 45 * minute, minSamples: 3, minSpan: 10 * minute, lookback: hour)
        case (.fiveHour, .high): return .init(minUsedPercent: 35, minMargin: 30 * minute, minSamples: 3, minSpan: 10 * minute, lookback: hour)
        case (.weekly, .low): return .init(minUsedPercent: 55, minMargin: 24 * hour, minSamples: 3, minSpan: 3 * hour, lookback: 24 * hour)
        case (.weekly, .medium): return .init(minUsedPercent: 40, minMargin: 12 * hour, minSamples: 3, minSpan: 2 * hour, lookback: 24 * hour)
        case (.weekly, .high): return .init(minUsedPercent: 30, minMargin: 6 * hour, minSamples: 3, minSpan: 2 * hour, lookback: 24 * hour)
        }
    }
}

struct LimitSample: Equatable, Sendable {
    var time: Date
    var usedPercent: Double
}

/// Bir pencerenin örnek geçmişi. Yenilenme anı değişince (±10 dk tolerans) ya da kullanım belirgin düşünce sıfırlanır.
struct LimitHistory: Equatable, Sendable {
    static let maxSamples = 48
    /// Bu kadar puan düşüş pencerenin yenilendiği anlamına gelir (yenilenme anı bilinmese bile).
    static let resetDrop: Double = 2

    var resetsAt: Date?
    var samples: [LimitSample] = []

    /// Pencere türüne göre örnekler arası en kısa aralık: sık gelen değerlerde (Claude her değişiklikte gönderir) sınırlı sayıda
    /// örnek yine de haftalık hız için yeterli zamanı kapsasın. Daha sık gelen örnek son örneğin yerine yazılır.
    static func minSpacing(_ kind: LimitWindowKind) -> TimeInterval {
        switch kind {
        case .fiveHour: 60
        case .weekly: 15 * 60
        }
    }

    /// Örneği ekler. Aynı ya da daha eski zamanlı örnek (ör. Codex'in aynı olayı yeniden okunması) atlanır.
    mutating func add(_ window: LimitWindow, at time: Date, minSpacing: TimeInterval = 0) {
        let sameWindow: Bool = switch (resetsAt, window.resetsAt) {
        case (nil, nil): true
        case let (a?, b?): abs(a.timeIntervalSince(b)) <= LimitAlertTracker.sameWindowTolerance
        default: samples.isEmpty
        }
        let dropped = samples.last.map { window.usedPercent < $0.usedPercent - Self.resetDrop } ?? false
        if !sameWindow || dropped { samples = [] }
        resetsAt = window.resetsAt
        if let last = samples.last, time <= last.time { return }
        let sample = LimitSample(time: time, usedPercent: window.usedPercent)
        if samples.count >= 2, time.timeIntervalSince(samples[samples.count - 2].time) < minSpacing {
            samples[samples.count - 1] = sample
            return
        }
        samples.append(sample)
        if samples.count > Self.maxSamples { samples.removeFirst(samples.count - Self.maxSamples) }
    }
}

struct LimitForecast: Equatable, Sendable {
    /// Bu hızla %100'e ulaşılacak an.
    var fillsAt: Date
    var resetsAt: Date
    /// Saatte kullanılan yüzde puanı.
    var ratePerHour: Double
    var usedPercent: Double
    /// Hesabın dayandığı son örneğin zamanı.
    var basedOn: Date
}

enum LimitForecaster {
    /// Yeterli veri ve artan kullanım varsa dolma anı tahmini; dolma yenilenmeden önce değilse nil.
    /// Hız: son `lookback` içindeki örneklere en küçük kareler doğrusu (pozitif eğim şart).
    static func forecast(_ history: LimitHistory, kind: LimitWindowKind, sensitivity: LimitForecastSensitivity) -> LimitForecast? {
        let rule = LimitForecastRule.rule(kind, sensitivity)
        guard let resetsAt = history.resetsAt, let last = history.samples.last, last.usedPercent < 100 else { return nil }
        let recent = history.samples.filter { last.time.timeIntervalSince($0.time) <= rule.lookback }
        guard recent.count >= rule.minSamples, let first = recent.first,
              last.time.timeIntervalSince(first.time) >= rule.minSpan else { return nil }
        let xs = recent.map { $0.time.timeIntervalSince(first.time) }, ys = recent.map(\.usedPercent)
        let n = Double(recent.count)
        let meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
        var sxx = 0.0, sxy = 0.0
        for (x, y) in zip(xs, ys) { sxx += (x - meanX) * (x - meanX); sxy += (x - meanX) * (y - meanY) }
        guard sxx > 0 else { return nil }
        let perSecond = sxy / sxx
        guard perSecond > 0, perSecond.isFinite else { return nil }
        let fillsAt = last.time.addingTimeInterval((100 - last.usedPercent) / perSecond)
        guard fillsAt < resetsAt else { return nil }
        return LimitForecast(fillsAt: fillsAt, resetsAt: resetsAt, ratePerHour: perSecond * 3600,
                             usedPercent: last.usedPercent, basedOn: last.time)
    }

    /// Uyarı koşulları: kullanım yeterince yüksek ve dolma, yenilenmeden belirgin şekilde önce.
    static func shouldWarn(_ forecast: LimitForecast, kind: LimitWindowKind, sensitivity: LimitForecastSensitivity) -> Bool {
        let rule = LimitForecastRule.rule(kind, sensitivity)
        return forecast.usedPercent >= rule.minUsedPercent
            && forecast.resetsAt.timeIntervalSince(forecast.fillsAt) >= rule.minMargin
    }
}

struct LimitForecastAlert: Equatable, Sendable {
    var source: LimitSource
    var kind: LimitWindowKind
    var forecast: LimitForecast

    func title() -> String { "\(source.displayName) \(kind.noun) yenilenmeden dolabilir" }

    /// "Bu hızla 5 saatlik limit ~14:20'de dolacak, yenilenme 16:00 (şu an %62)."
    func body(now: Date, calendar: Calendar = LimitForecastFormat.calendar) -> String {
        let fill = LimitForecastFormat.moment(forecast.fillsAt, kind: kind, now: now, calendar: calendar)
        let reset = LimitForecastFormat.moment(forecast.resetsAt, kind: kind, now: now, calendar: calendar)
        return "Bu hızla \(kind.noun) ~\(fill)\(LimitForecastFormat.locativeSuffix(forecast.fillsAt, calendar: calendar)) dolacak, "
            + "yenilenme \(reset) (şu an \(LimitFormat.percent(forecast.usedPercent)))."
    }
}

/// Pencere başına "tahmin uyarısı gönderildi" kaydı (kaynak + tür + yenilenme anı). Her pencerede en çok bir kez.
struct LimitForecastWarnings: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var source: LimitSource
        var kind: LimitWindowKind
        var resetsAt: Date
    }

    var entries: [Entry] = []

    func contains(_ source: LimitSource, _ kind: LimitWindowKind, resetsAt: Date) -> Bool {
        entries.contains { $0.source == source && $0.kind == kind
            && abs($0.resetsAt.timeIntervalSince(resetsAt)) <= LimitAlertTracker.sameWindowTolerance }
    }

    mutating func prune(now: Date) { entries.removeAll { $0.resetsAt < now.addingTimeInterval(-86_400) } }
}

/// Geçmiş + uyarı kaydı. `ingest` yeni değeri geçmişe ekler ve gönderilecek tahmin uyarılarını döner.
struct LimitForecastEngine: Equatable, Sendable {
    private(set) var histories: [String: LimitHistory] = [:]
    var warnings = LimitForecastWarnings()

    private static func key(_ source: LimitSource, _ kind: LimitWindowKind) -> String { "\(source.rawValue).\(kind.rawValue)" }

    func history(_ source: LimitSource, _ kind: LimitWindowKind) -> LimitHistory? { histories[Self.key(source, kind)] }

    /// `alertsEnabled` kapalıyken ya da veri eskiyse geçmiş yine tutulur ama uyarı dönmez.
    mutating func ingest(_ limits: ProviderLimits, sensitivity: LimitForecastSensitivity, alertsEnabled: Bool, now: Date) -> [LimitForecastAlert] {
        warnings.prune(now: now)
        var alerts: [LimitForecastAlert] = []
        for kind in LimitWindowKind.allCases {
            let key = Self.key(limits.source, kind)
            guard let window = limits.window(kind), !window.isReset(now: now) else { histories[key] = nil; continue }
            var history = histories[key] ?? LimitHistory()
            history.add(window, at: limits.observedAt, minSpacing: LimitHistory.minSpacing(kind))
            histories[key] = history
            guard alertsEnabled, !limits.isStale(now: now),
                  let forecast = LimitForecaster.forecast(history, kind: kind, sensitivity: sensitivity),
                  forecast.fillsAt > now,
                  LimitForecaster.shouldWarn(forecast, kind: kind, sensitivity: sensitivity),
                  !warnings.contains(limits.source, kind, resetsAt: forecast.resetsAt) else { continue }
            warnings.entries.append(.init(source: limits.source, kind: kind, resetsAt: forecast.resetsAt))
            alerts.append(LimitForecastAlert(source: limits.source, kind: kind, forecast: forecast))
        }
        return alerts
    }

    /// Kartta gösterilecek tahmin: yalnızca dolma henüz gelmediyse.
    func forecast(_ source: LimitSource, _ kind: LimitWindowKind, sensitivity: LimitForecastSensitivity, now: Date) -> LimitForecast? {
        guard let history = history(source, kind),
              let forecast = LimitForecaster.forecast(history, kind: kind, sensitivity: sensitivity),
              forecast.fillsAt > now else { return nil }
        return forecast
    }
}

enum LimitForecastFormat {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "tr_TR")
        c.timeZone = .current
        return c
    }

    /// 5 saat: "14:20". Haftalık: bugünse "bugün 14:20", yarınsa "yarın 14:20", değilse "Perşembe 14:20".
    static func moment(_ date: Date, kind: LimitWindowKind, now: Date, calendar: Calendar = Self.calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        guard kind == .weekly else { return time }
        if calendar.isDate(date, inSameDayAs: now) { return "bugün \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "yarın \(time)"
        }
        let weekday = calendar.component(.weekday, from: date)
        let names = ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"]
        return "\(names[(weekday - 1) % 7]) \(time)"
    }

    /// Saat okunuşuna göre bulunma eki: 14:20'de, 14:30'da, 14:40'ta, 14:00'te, 12:00'de.
    /// Dakika sıfır değilse son okunan sayı dakikadır, sıfırsa saattir.
    static func locativeSuffix(_ date: Date, calendar: Calendar = Self.calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = parts.minute ?? 0
        return locativeSuffix(number: minute != 0 ? minute : parts.hour ?? 0)
    }

    static func locativeSuffix(number n: Int) -> String {
        if n == 0 { return "'da" }                         // sıfır
        let ones = ["", "'de", "'de", "'te", "'te", "'te", "'da", "'de", "'de", "'da"]  // bir iki üç dört beş altı yedi sekiz dokuz
        if n % 10 != 0 { return ones[n % 10] }
        let tens = ["", "'da", "'de", "'da", "'ta", "'de"]  // on yirmi otuz kırk elli
        return tens[(n / 10) % 6]
    }

    /// Kart satırı: "bu hızla ~14:20'de dolar" (haftalık: "bu hızla ~Perşembe 14:20'de dolar").
    static func cardLine(_ forecast: LimitForecast, kind: LimitWindowKind, now: Date, calendar: Calendar = Self.calendar) -> String {
        "bu hızla ~\(moment(forecast.fillsAt, kind: kind, now: now, calendar: calendar))\(locativeSuffix(forecast.fillsAt, calendar: calendar)) dolar"
    }
}
