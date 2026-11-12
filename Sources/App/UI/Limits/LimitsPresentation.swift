import Foundation

// Abonelik limitleri ekranlarının (Genel bakış kartı, Limitler sayfası, panel kartı) ortak, saf gösterim mantığı.
// Veri modeli (SubscriptionLimits / LimitForecast) değişmez; burası yalnızca okur ve ekranlara hazır metin/oran üretir.

/// Halka/çubuk rengi için sade ton. Renge çevirmek görünüm katmanının işi (LimitStyle).
enum LimitTone: Equatable, Sendable {
    case normal, warning, critical
    /// Bayat ya da yenilenmiş pencere: soluk gösterilir.
    case muted
}

extension LimitWindowKind {
    /// Pencere uzunluğu (geçen süre oranı için).
    var duration: TimeInterval {
        switch self {
        case .fiveHour: 5 * 3600
        case .weekly: 7 * 86_400
        }
    }

    /// Kart başlığı: "5 saatlik pencere" / "Haftalık pencere".
    var windowTitle: String {
        switch self {
        case .fiveHour: "5 saatlik pencere"
        case .weekly: "Haftalık pencere"
        }
    }

    /// Dar yerler için: "5 sa" / "Haftalık".
    var shortLabel: String {
        switch self {
        case .fiveHour: "5 sa"
        case .weekly: "Haftalık"
        }
    }
}

/// Tek bir pencerenin ekrana hazır hali.
struct LimitWindowDisplay: Equatable, Identifiable, Sendable {
    var kind: LimitWindowKind
    var usedPercent: Double
    var resetsAt: Date?
    /// Yenilenme anı geçti: eski yüzde geçersiz.
    var isReset: Bool
    var isStale: Bool
    var level: LimitLevel
    var warnAt: Double
    var criticalAt: Double
    var forecast: LimitForecast?
    /// Sunucu "limit doldu" bildirdi (Codex `rateLimitReachedType`): yüzde %100'ün altında görünse de pencere dolu sayılır.
    var reached = false

    var id: LimitWindowKind { kind }

    /// Halka/çubuk doluluğu 0...1 (yenilenmişse 0).
    var fraction: Double { isReset ? 0 : min(1, max(0, usedPercent / 100)) }

    /// Kullanım %100'e ulaştı ve pencere henüz yenilenmedi: limit doldu.
    var isFull: Bool { !isReset && (usedPercent >= 100 || reached) }

    /// Bayat veri de geçerli sayılır (yenilenme anı gelecekte olduğundan değer düşemez); yalnızca yenilenmiş pencere soluk çizilir.
    var tone: LimitTone {
        if isReset { return .muted }
        if isFull { return .critical }
        return switch level {
        case .critical: .critical
        case .warning: .warning
        case .normal: .normal
        }
    }

    /// "%62"; yenilenmişse (yeni veri gelene dek) "%0".
    var percentText: String { isReset ? LimitFormat.percent(0) : LimitFormat.percent(usedPercent) }
    /// Halkanın içi için işaretsiz sayı: "62".
    var numberText: String { isReset ? "0" : "\(Int(usedPercent.rounded()))" }

    var statusText: String {
        if isReset { return "Yenilendi · yeni veri bekleniyor" }
        if isFull { return "Limit doldu" }
        return switch level {
        case .critical: "Kritik"
        case .warning: "Uyarı"
        case .normal: "Normal"
        }
    }

    /// Yenilenmeye kalan süre: "2 sa 10 dk"; yenilenmişse nil.
    func countdownText(now: Date) -> String? {
        guard let resetsAt, !isReset else { return nil }
        let minutes = max(1, Int((resetsAt.timeIntervalSince(now) / 60).rounded(.up)))
        return LimitFormat.duration(minutes: minutes)
    }

    /// Dolu pencerenin açılış saati: "15:00'te açılır" (haftalık: "Perşembe 15:00'te açılır"); dolu değilse ya da zaman bilinmiyorsa nil.
    func opensAtText(now: Date) -> String? {
        guard isFull, let resetsAt else { return nil }
        return "\(LimitForecastFormat.moment(resetsAt, kind: kind, now: now))\(LimitForecastFormat.locativeSuffix(resetsAt)) açılır"
    }

    /// Dolma tahmini yokken kısa not: veri bayatsa "Tahmin için yeni kullanım gerekiyor"; dolu/yenilenmiş pencerede ya da tahmin varken nil.
    var forecastNote: String? {
        guard forecast == nil, isStale, !isReset, !isFull else { return nil }
        return "Tahmin için yeni kullanım gerekiyor"
    }

    /// Pencerenin ne kadarının geçtiği (0...1); yenilenme anı bilinmiyorsa nil.
    func elapsedFraction(now: Date) -> Double? {
        guard let resetsAt else { return nil }
        if isReset { return 1 }
        let remaining = resetsAt.timeIntervalSince(now)
        return min(1, max(0, 1 - remaining / kind.duration))
    }

    /// "Bu hızla ~14:20'de dolar" (haftalık: "Bu hızla ~Perşembe 14:20'de dolar"); tahmin yoksa nil.
    func forecastText(now: Date) -> String? {
        guard let forecast else { return nil }
        let moment = LimitForecastFormat.moment(forecast.fillsAt, kind: kind, now: now)
        return "Bu hızla ~\(moment)\(LimitForecastFormat.locativeSuffix(forecast.fillsAt)) dolar"
    }

    /// Pencerenin başladığı an (yenilenme anı − pencere uzunluğu); yenilenme anı bilinmiyorsa nil.
    var startsAt: Date? { resetsAt?.addingTimeInterval(-kind.duration) }

    /// Dolma tahmininin çizelgedeki yeri (0...1); tahmin yoksa ya da dolma yenilenmeden sonraysa nil.
    var forecastFraction: Double? {
        guard let forecast, let startsAt else { return nil }
        let fraction = forecast.fillsAt.timeIntervalSince(startsAt) / kind.duration
        return (0...1).contains(fraction) ? fraction : nil
    }

    /// Kullanım ile geçen süre karşılaştırması: "Süreden hızlı" / "Dengeli" / "Rahat". Süre bilinmiyorsa nil.
    func paceText(now: Date) -> String? {
        guard !isReset, !isStale, let elapsed = elapsedFraction(now: now) else { return nil }
        let delta = usedPercent - elapsed * 100
        if delta > 12 { return "Süreden hızlı gidiyor" }
        if delta < -12 { return "Rahat gidiyor" }
        return "Dengeli gidiyor"
    }

    /// Kullanım hızı: "%12/sa" (yalnızca tahmin varken).
    var rateText: String? {
        guard let rate = forecast?.ratePerHour, rate.isFinite, rate > 0 else { return nil }
        let text = rate.formatted(.number.precision(.fractionLength(rate < 10 ? 1 : 0)).locale(Locale(identifier: "tr_TR")))
        return "%\(text)/sa"
    }
}

/// Bir sağlayıcının (Claude / Codex) ekrana hazır hali.
struct LimitProviderDisplay: Equatable, Identifiable, Sendable {
    var source: LimitSource
    var windows: [LimitWindowDisplay]
    var observedAt: Date
    var isStale: Bool
    var creditsBalance: Double?
    /// Değer `codex app-server`'dan (canlı) geldi.
    var isLive = false
    /// Ücretsiz sıfırlama hakları (yalnızca bilgi; hiçbir eylem yok).
    var resetCreditCount: Int?
    var resetCredits: [LimitResetCredit] = []

    var id: LimitSource { source }

    func window(_ kind: LimitWindowKind) -> LimitWindowDisplay? { windows.first { $0.kind == kind } }

    /// En yüksek kullanımlı (yenilenmemiş) pencere.
    var headline: LimitWindowDisplay? {
        windows.filter { !$0.isReset }.max { $0.usedPercent < $1.usedPercent }
    }

    func ageText(now: Date) -> String { LimitFormat.ageText(observedAt, now: now) }

    /// Bir pencere doldu: son verinin yaşı önemsizleşir (küçük gri gösterilir).
    var hasFullWindow: Bool { windows.contains { $0.isFull } }

    /// "Canlı · şimdi" (app-server) / "Güncel · şimdi" / "Son veri 3 sa önce".
    func freshnessText(now: Date) -> String {
        if isStale { return "Son veri \(ageText(now: now))" }
        return "\(isLive ? "Canlı" : "Güncel") · \(ageText(now: now))"
    }

    /// "1 ücretsiz sıfırlama hakkı"; hak yoksa nil.
    var resetCreditsChipText: String? {
        guard let count = resetCreditCount, count > 0 else { return nil }
        return "\(count) ücretsiz sıfırlama hakkı"
    }
}

enum LimitEmptyReason: Equatable, Sendable {
    case agentsDisabled, claudeNotConnected, claudeWaiting, codexDisabled, codexNoData

    var title: String {
        switch self {
        case .agentsDisabled: "Claude ajanları kapalı"
        case .claudeNotConnected: "Claude bağlı değil"
        case .claudeWaiting: "Claude'dan veri bekleniyor"
        case .codexDisabled: "Codex limitleri kapalı"
        case .codexNoData: "Codex verisi bulunamadı"
        }
    }

    var detail: String {
        switch self {
        case .agentsDisabled:
            "Claude limitleri için Ayarlar › Claude ajanları'ndan özelliği açın."
        case .claudeNotConnected:
            "5 saatlik ve haftalık limitlerini görmek için Claude Code'u bağlayın. Ayarlar'dan tek tıkla bağlanır; settings.json yedeklenir."
        case .claudeWaiting:
            "Bağlantı hazır. Claude Code ilk yanıtını verince değerler burada görünür."
        case .codexDisabled:
            "Codex limitlerini göstermek için Ayarlar › Claude ajanları › Abonelik limitleri'nden açın."
        case .codexNoData:
            "Henüz bir Codex oturumu bulunamadı. Codex'i kullandığınızda değerler burada görünür."
        }
    }

    /// Boş durumdaki eylem düğmesi (Ayarlar'a yönlendirir); gerek yoksa nil.
    var actionTitle: String? {
        switch self {
        case .claudeNotConnected: "Bağla"
        case .agentsDisabled, .codexDisabled: "Ayarlar'ı aç"
        case .claudeWaiting, .codexNoData: nil
        }
    }
}

enum LimitSectionState: Equatable, Sendable {
    case data(LimitProviderDisplay)
    case empty(LimitEmptyReason)
}

struct LimitSection: Equatable, Identifiable, Sendable {
    var source: LimitSource
    var state: LimitSectionState

    var id: LimitSource { source }
    var display: LimitProviderDisplay? {
        if case .data(let display) = state { display } else { nil }
    }
}

/// Sayfanın/kartın tek seferlik görüntüsü (saf değer; testte ve önizlemede sahte veriyle kurulur).
struct LimitsSnapshot: Equatable, Sendable {
    var sections: [LimitSection]
    var thresholds: LimitAlertThresholds
    var now: Date
    /// Sağlayıcı başına plan rozeti (bilinmiyorsa yok).
    var plans: [LimitSource: LimitPlan] = [:]
    /// Sağlayıcı başına model bazında kullanım (hesaplanmadıysa yok).
    var modelUsage: [LimitSource: ProviderModelUsage] = [:]

    /// En az bir sağlayıcıda verisi gelen pencere türleri (hiç veri yoksa ikisi de). Gelmeyen pencere hiçbir yerde çizilmez.
    var visibleKinds: [LimitWindowKind] {
        let present = LimitWindowKind.allCases.filter { kind in sections.contains { $0.display?.window(kind) != nil } }
        return present.isEmpty ? LimitWindowKind.allCases : present
    }

    var featured: (source: LimitSource, window: LimitWindowDisplay)? { LimitsPresentation.featured(sections) }
    var hasData: Bool { sections.contains { $0.display != nil } }
}

enum LimitsPresentation {
    /// Her zaman Claude + Codex bölümleri (veri yoksa boş durum nedeniyle). Ajanlar kapalıyken Claude "kapalı" olur,
    /// Codex yine okunabilir (karoyla aynı kural).
    static func sections(providers: [ProviderLimits], claudeConnected: Bool, agentsEnabled: Bool, codexEnabled: Bool,
                         thresholds: LimitAlertThresholds, now: Date,
                         forecast: (ProviderLimits, LimitWindowKind) -> LimitForecast?) -> [LimitSection] {
        func display(_ limits: ProviderLimits) -> LimitProviderDisplay {
            let stale = limits.isStale(now: now)
            var windows = LimitWindowKind.allCases.compactMap { kind -> LimitWindowDisplay? in
                guard let window = limits.window(kind) else { return nil }
                let reset = window.isReset(now: now)
                let warn = kind == .fiveHour ? thresholds.fiveHourWarn : thresholds.weeklyWarn
                let critical = kind == .fiveHour ? thresholds.fiveHourCritical : thresholds.weeklyCritical
                return LimitWindowDisplay(kind: kind, usedPercent: window.usedPercent, resetsAt: window.resetsAt, isReset: reset,
                                          isStale: stale, level: thresholds.level(for: window.usedPercent, kind: kind),
                                          warnAt: min(warn, critical), criticalAt: max(warn, critical),
                                          forecast: reset || stale ? nil : forecast(limits, kind))
            }
            // "Limit doldu" bildirimi en dolu (yenilenmemiş) pencereye işlenir.
            if limits.limitReached == true,
               let index = windows.indices.filter({ !windows[$0].isReset }).max(by: { windows[$0].usedPercent < windows[$1].usedPercent }) {
                windows[index].reached = true
            }
            return LimitProviderDisplay(source: limits.source, windows: windows, observedAt: limits.observedAt, isStale: stale,
                                        creditsBalance: limits.creditsBalance, isLive: limits.isLive == true,
                                        resetCreditCount: limits.resetCreditCount, resetCredits: limits.resetCredits ?? [])
        }
        let claudeState: LimitSectionState
        if !agentsEnabled {
            claudeState = .empty(.agentsDisabled)
        } else if let claude = providers.first(where: { $0.source == .claude }) {
            claudeState = .data(display(claude))
        } else {
            claudeState = .empty(claudeConnected ? .claudeWaiting : .claudeNotConnected)
        }
        let codexState: LimitSectionState
        if !codexEnabled {
            codexState = .empty(.codexDisabled)
        } else if let codex = providers.first(where: { $0.source == .codex }) {
            codexState = .data(display(codex))
        } else {
            codexState = .empty(.codexNoData)
        }
        return [LimitSection(source: .claude, state: claudeState), LimitSection(source: .codex, state: codexState)]
    }

    /// Öne çıkan pencere: yenilenmemiş pencereler arasında en yüksek kullanım; taze veri varsa bayatlar elenir. Eşitlikte ilk.
    static func featured(_ sections: [LimitSection]) -> (source: LimitSource, window: LimitWindowDisplay)? {
        let all = sections.flatMap { section -> [(source: LimitSource, window: LimitWindowDisplay)] in
            (section.display?.windows ?? []).filter { !$0.isReset }.map { (section.source, $0) }
        }
        let pool = all.contains { !$0.window.isStale } ? all.filter { !$0.window.isStale } : all
        var best: (source: LimitSource, window: LimitWindowDisplay)?
        for entry in pool where best == nil || entry.window.usedPercent > best!.window.usedPercent { best = entry }
        return best
    }

    /// Genel bakış kartının tek satırlık açıklaması: "Claude ~14:20'de dolar", "Claude 5 sa · 2 sa 10 dk", "Claude 5 sa doldu · 15:00'te açılır", "Son veri 3 sa önce".
    static func cardCaption(_ snapshot: LimitsSnapshot) -> String? {
        guard let (source, window) = snapshot.featured, let provider = snapshot.sections.first(where: { $0.source == source })?.display else {
            return nil
        }
        if window.isFull {
            return "\(source.displayName) \(window.kind.shortLabel) doldu" + (window.opensAtText(now: snapshot.now).map { " · \($0)" } ?? "")
        }
        if window.isStale { return "Son veri \(provider.ageText(now: snapshot.now))" }
        if let forecast = window.forecast {
            let moment = LimitForecastFormat.moment(forecast.fillsAt, kind: window.kind, now: snapshot.now)
            return "\(source.displayName) ~\(moment)\(LimitForecastFormat.locativeSuffix(forecast.fillsAt)) dolar"
        }
        if let countdown = window.countdownText(now: snapshot.now) { return "\(source.displayName) \(window.kind.shortLabel) · \(countdown)" }
        return "\(source.displayName) \(window.kind.shortLabel)"
    }

    /// Zaman çizelgesi satırları: yalnızca verisi gelen, yenilenmemiş ve yenilenme anı bilinen pencereler.
    static func timelineRows(_ snapshot: LimitsSnapshot) -> [(source: LimitSource, window: LimitWindowDisplay)] {
        snapshot.sections.flatMap { section -> [(source: LimitSource, window: LimitWindowDisplay)] in
            (section.display?.windows ?? []).filter { !$0.isReset && $0.resetsAt != nil }.map { (section.source, $0) }
        }
    }

    /// Plan satırının alt metni: "Stripe aboneliği · Ek kullanım kapalı"; hiçbiri yoksa nil.
    static func planDetail(_ plan: LimitPlan) -> String? {
        var parts: [String] = []
        if let billing = plan.billing { parts.append(billing) }
        if let extra = plan.extraUsage { parts.append(extra ? "Ek kullanım açık" : "Ek kullanım kapalı") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Eşik özeti: "Uyarı %80 · Kritik %95".
    static func thresholdText(_ window: LimitWindowDisplay) -> String {
        "Uyarı \(LimitFormat.percent(window.warnAt)) · Kritik \(LimitFormat.percent(window.criticalAt))"
    }
}

@MainActor
extension SubscriptionLimitsModel {
    /// Ekranlar için tek seferlik görüntü (yalnızca okur).
    func snapshot(agentsEnabled: Bool, now: Date) -> LimitsSnapshot {
        LimitsSnapshot(
            sections: LimitsPresentation.sections(
                providers: providers, claudeConnected: claudeConnected, agentsEnabled: agentsEnabled, codexEnabled: codexEnabled,
                thresholds: thresholds, now: now, forecast: { forecast(for: $0, $1, now: now) }),
            thresholds: thresholds, now: now, plans: plans, modelUsage: modelUsage)
    }
}
