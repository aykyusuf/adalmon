import SwiftUI

/// Genel bakış karosuna tıklayınca açılacak yer: ana pencere sayfası (+ Süreçler sekmesi).
struct OverviewDestination: Equatable, Sendable {
    var section: MainSection
    var processesTab: ProcessesTab?
    /// Doluysa ana pencere sayfası yerine Ayarlar'ın bu bölümü açılır.
    var settings: SettingsSection?

    @MainActor
    func open(_ router: SettingsRouter) {
        if let settings { router.open(settings); return }
        if let processesTab { router.processesTab = processesTab }
        router.selectedMainSection = section
    }
}

/// Genel bakışın üst sırasındaki özet karoları.
enum OverviewTileKind: String, CaseIterable, Identifiable, Sendable {
    case network, mobile, cpu, gpu, memory, disk, limits

    var id: String { rawValue }

    var destination: OverviewDestination {
        switch self {
        case .network: OverviewDestination(section: .network)
        case .mobile: OverviewDestination(section: .mobile)
        case .cpu, .gpu, .memory: OverviewDestination(section: .processes, processesTab: .performance)
        case .disk: OverviewDestination(section: .processes, processesTab: .disk)
        case .limits: OverviewDestination(section: .limits)
        }
    }
}

/// Bir karonun görüntülenecek değerleri (saf; testte sahte veriyle kurulur).
struct OverviewTile: Identifiable {
    enum Accessory {
        case none
        /// Küçük çizgi grafik (0...1 değerler; zaten tutulan geçmişten).
        case sparkline([Double])
        /// Doluluk çubuğu.
        case bar(Double)
        /// Mobil / Wi‑Fi payı.
        case split(mobile: UInt64, wifi: UInt64)
    }

    let kind: OverviewTileKind
    let title: String
    let symbol: String
    /// Büyük değer: "802 MB", "%44".
    let value: String
    /// Tek satırlık ek bilgi: "↓600 MB ↑120 MB", "11:52 biter".
    let secondary: String
    /// Üzerine gelince ayrıntı (eski kartlardaki bilgiler).
    let help: String
    let tint: Color
    let accessory: Accessory
    /// İkincil metnin rengi (ör. dolma tahmini turuncu); nil = ikincil renk.
    var secondaryTint: Color? = nil
    /// Limit karosu: canlı halka kartı gösterilir. Her iki durumda tıklayınca ana pencerenin "Limitler" sayfası açılır.
    var opensDetail = false

    var id: OverviewTileKind { kind }
    var accessibilityHint: String {
        return "\(kind.destination.section.title) sayfasını açar"
    }
    var accessibilityLabel: String { [title, value, secondary].filter { !$0.isEmpty }.joined(separator: ", ") }

    /// Bugün ağ, Mobil kota, CPU, GPU (varsa), RAM, Disk.
    static func all(data: PanelData, today: TodaySummary, budget: BudgetSnapshot, limits: OverviewTile? = nil) -> [OverviewTile] {
        let metrics = Dictionary(uniqueKeysWithValues: SystemMetric.all(data, showTemperatures: true).map { ($0.kind, $0) })
        var out = [network(today), mobile(budget)]
        if let m = metrics[.cpu] { out.append(metric(m, kind: .cpu)) }
        if data.snapshot?.gpu != nil, let m = metrics[.gpu] { out.append(metric(m, kind: .gpu)) }
        if let m = metrics[.memory] { out.append(metric(m, kind: .memory)) }
        if let m = metrics[.disk] { out.append(metric(m, kind: .disk)) }
        if let limits { out.append(limits) }
        return out
    }

    static func network(_ s: TodaySummary) -> OverviewTile {
        var help = ["Bugün toplam \(Format.bytes(s.total)) · indirme ↓\(Format.bytes(s.down)) · yükleme ↑\(Format.bytes(s.up))",
                    "\(MediumStyle.mobileName) \(Format.bytes(s.mobile)) · \(MediumStyle.wifiName) \(Format.bytes(s.wifi))"]
        if let yesterday = s.yesterday, yesterday > 0 {
            help.append("Dün \(Format.bytes(yesterday)) · bugün dünün %\(Int((Double(s.total) * 100 / Double(yesterday)).rounded())) kadarı")
        } else {
            help.append("Dün için kayıt yok")
        }
        return OverviewTile(kind: .network, title: "Bugün", symbol: "arrow.up.arrow.down",
                            value: Format.bytes(s.total), secondary: "↓\(Format.bytes(s.down)) ↑\(Format.bytes(s.up))",
                            help: help.joined(separator: "\n"), tint: .indigo,
                            accessory: s.total > 0 ? .split(mobile: s.mobile, wifi: s.wifi) : .bar(0))
    }

    static func mobile(_ b: BudgetSnapshot) -> OverviewTile {
        let fraction = OverviewBudgetSummary.todayFraction(b)
        let tint: Color = fraction >= 1 ? .red : (fraction >= 0.8 ? .orange : .green)
        var help = ["Bugün \(Format.bytes(b.todayUsedBytes)) / \(Format.bytes(b.effectiveDailyCapBytes)) (\(Format.percent(fraction)))"]
        if let eta = OverviewBudgetSummary.etaText(b) { help.append(eta) }
        if let cap = b.monthlyCapBytes, let cycle = OverviewBudgetSummary.cycleFraction(b) {
            var line = "Bu dönem \(Format.bytes(b.cycleUsedBytes)) / \(Format.bytes(cap)) (\(Format.percent(cycle))) · \(OverviewBudgetSummary.daysText(b))"
            if let projected = b.projectedCycleBytes {
                line += " · tahmin \(Format.bytes(projected))" + (projected > cap ? " (limit aşılır)" : "")
            }
            help.append(line)
        }
        let secondary = OverviewBudgetSummary.shortEtaText(b)
            ?? "\(Format.bytes(b.todayUsedBytes)) / \(Format.bytes(b.effectiveDailyCapBytes))"
        return OverviewTile(kind: .mobile, title: "Mobil", symbol: "antenna.radiowaves.left.and.right",
                            value: Format.percent(fraction), secondary: secondary,
                            help: help.joined(separator: "\n"), tint: tint, accessory: .bar(fraction))
    }

    static func metric(_ m: SystemMetric, kind: OverviewTileKind) -> OverviewTile {
        let accessory: Accessory = if let h = m.history, h.count > 1 { .sparkline(h) } else { .bar(m.fraction) }
        return OverviewTile(kind: kind, title: m.title, symbol: m.systemImage, value: m.value,
                            secondary: m.secondary,
                            help: [m.help, m.detail].filter { !$0.isEmpty }.joined(separator: "\n"),
                            tint: m.tint, accessory: accessory)
    }
}

extension OverviewBudgetSummary {
    /// Karo için kısa tahmin: "11:52 biter", "doldu", "bugün dolmaz"; bilinmiyorsa nil.
    static func shortEtaText(_ b: BudgetSnapshot) -> String? {
        let candidates = [b.etaRecentRate, b.etaBudgetRecentRate].compactMap { $0 }
        if candidates.contains(.reached) { return "doldu" }
        let times = candidates.compactMap { eta -> Date? in
            if case .at(let date) = eta { date } else { nil }
        }
        if let first = times.min() {
            return first.formatted(.dateTime.hour().minute().locale(Locale(identifier: "tr_TR"))) + " biter"
        }
        if candidates.contains(.notToday) { return "bugün dolmaz" }
        return nil
    }
}

extension OverviewAttention.Destination {
    @MainActor
    func open(_ router: SettingsRouter) {
        switch self {
        case .rules: router.selectedMainSection = .rules
        case .filterSettings: router.open(.filter)
        case .app(let app):
            router.selectedAppID = app
            router.selectedMainSection = .network
        }
    }
}
