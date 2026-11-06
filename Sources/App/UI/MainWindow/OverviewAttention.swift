import Foundation

/// Genel bakıştaki koşullu "Dikkat" kartının maddeleri.
struct OverviewAttention: Identifiable, Equatable, Sendable {
    enum Severity: Sendable { case info, warning, critical }
    enum Destination: Hashable, Sendable {
        case rules
        case filterSettings
        case app(String)
    }

    let id: String
    let severity: Severity
    let symbol: String
    let title: String
    let detail: String
    let destination: Destination

    /// Maddeleri üretir: etkin kurallar, kademeli limit seviyesi, kapalı filtre, son 1 dk'da yüksek tüketim.
    @MainActor
    static func items(data: PanelData, rules: [UsageRule], statuses: [RuleStatus], ladder: LadderStatus,
                      burstThreshold: UInt64) -> [OverviewAttention] {
        var out: [OverviewAttention] = []
        for status in statuses where status.phase == .active {
            guard let rule = rules.first(where: { $0.id == status.id }) else { continue }
            let app = AppCatalog.shared.name(for: rule.app)
            var detail = RuleText.action(rule.action) + " · " + RuleText.scope(rule.scope)
            if let left = status.secondsUntilReset { detail += " · \(RuleText.duration(left)) sonra" }
            out.append(OverviewAttention(id: "rule-\(status.id)", severity: .warning, symbol: "shield.lefthalf.filled",
                                         title: "\(RuleText.title(rule)): \(app) için kural devrede", detail: detail, destination: .rules))
        }
        if ladder.enabled, ladder.level != .none {
            let (name, severity): (String, Severity) = switch ladder.level {
            case .warn: ("uyarı", .info)
            case .slow: ("yavaşlatma", .warning)
            default: ("kesme", .critical)
            }
            var detail = "Mobil günlük/dönem kullanımı %\(ladder.percent)"
            if !ladder.throttledApps.isEmpty { detail += " · \(ladder.throttledApps.count) uygulama yavaşlatıldı" }
            if !ladder.blockedApps.isEmpty { detail += " · \(ladder.blockedApps.count) uygulama engellendi" }
            out.append(OverviewAttention(id: "ladder", severity: severity, symbol: "chart.line.uptrend.xyaxis",
                                         title: "Kademeli limit: \(name) seviyesi", detail: detail, destination: .rules))
        }
        if data.showsFilterCallout {
            out.append(OverviewAttention(id: "filter", severity: .warning, symbol: "line.3.horizontal.decrease.circle",
                                         title: "Ağ filtresi kapalı", detail: "Uygulama bazlı ölçüm, kurallar ve hız sınırları çalışmaz.",
                                         destination: .filterSettings))
        }
        if let burst = data.last60.max(by: { $0.bytes < $1.bytes }), burst.bytes >= burstThreshold {
            let name = AppCatalog.shared.name(for: burst.app)
            out.append(OverviewAttention(id: "burst", severity: .warning, symbol: "bolt.fill",
                                         title: "Son 1 dakikada yüksek tüketim", detail: "\(name): \(Format.bytes(burst.bytes))",
                                         destination: .app(burst.app)))
        }
        return out
    }
}
