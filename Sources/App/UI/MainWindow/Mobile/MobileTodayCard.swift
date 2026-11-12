import SwiftUI

/// Bugünün mobil kullanımı: bütçe ilerlemesi, kalan, limit dolma tahmini, hotspot durumu.
struct MobileTodayCard: View {
    let budget: BudgetSnapshot
    let ladder: LadderStatus
    let dailyCapBytes: UInt64
    let isMobile: Bool
    let forceMobile: Bool

    private var used: UInt64 { budget.todayUsedBytes }
    private var cap: UInt64 { budget.effectiveDailyCapBytes }
    private var fraction: Double { cap == 0 ? 0 : min(1, Double(used) / Double(cap)) }
    private var tint: Color { fraction >= 1 ? .red : (fraction >= 0.8 ? .orange : .green) }
    /// Aylık dinamik bütçe günlük limitten düşükse etkin limit odur.
    /// Aylık tempo günlük limitten düşükse bilgi satırı gösterilir (bütçeyi değiştirmez).
    private var usesDynamicBudget: Bool { (budget.dynamicDailyBudgetBytes ?? .max) < dailyCapBytes }

    var body: some View {
        MobileCard(title: "Bugün", systemImage: "antenna.radiowaves.left.and.right") {
            MobileLadderBadge(status: ladder)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Format.bytes(used))
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(fraction >= 0.8 ? tint : .primary)
                        .contentTransition(.numericText())
                    Text("/ \(Format.bytes(cap)) günlük limit · \(Format.percent(fraction))")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                UsageBar(fraction: fraction, tint: tint, height: 10)
                    .accessibilityElement()
                    .accessibilityLabel("Günlük mobil kullanım")
                    .accessibilityValue("Mobil veri \(Format.bytes(used)) / \(Format.bytes(cap)), yüzde \(Int(fraction * 100))")
                HStack(alignment: .top, spacing: 16) {
                    MobileStat(title: "Bugün kalan", value: Format.bytes(budget.todayRemainingBytes),
                               tint: budget.todayRemainingBytes == 0 ? .red : .primary)
                    MobileStat(title: "Günlük limit", value: Format.bytes(dailyCapBytes),
                               help: "Ayarlar › Mobil veri bölümünden değiştirilir")
                    MobileStat(title: "Aylık tempo (bilgi)",
                               value: budget.dynamicDailyBudgetBytes.map(Format.bytes) ?? "–",
                               help: "(Aylık limit − bugünden önceki kullanım) ÷ kalan gün")
                }
                if usesDynamicBudget {
                    Label("Aylık limiti aşmamak için kalan günlerde günde ~\(budget.dynamicDailyBudgetBytes.map(Format.bytes) ?? "–") yeterli; bu yalnızca bilgi, bugünün bütçesi günlük limit.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                etaSection
                connectionRow
            }
        }
    }

    @ViewBuilder
    private var etaSection: some View {
        let recent = usesDynamicBudget ? (budget.etaBudgetRecentRate ?? budget.etaRecentRate) : budget.etaRecentRate
        let average = usesDynamicBudget ? (budget.etaBudgetAverageRate ?? budget.etaAverageRate) : budget.etaAverageRate
        let limitName = usesDynamicBudget ? "Bütçe" : "Limit"
        VStack(alignment: .leading, spacing: 6) {
            Label(MobileText.eta(recent, basis: "Son 15 dk hızıyla", limitName: limitName), systemImage: "clock")
                .font(.callout.weight(.medium))
            Label(MobileText.eta(average, basis: "Gün ortalamasıyla", limitName: limitName), systemImage: "chart.line.uptrend.xyaxis")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var connectionRow: some View {
        Label(connectionText, systemImage: "personalhotspot")
            .font(.caption)
            .foregroundStyle(isMobile ? Color.orange : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var connectionText: String {
        if forceMobile { return "Bu ağ mobil veri sayılıyor (Ayarlar › Mobil veri). Kullanım sayılıyor." }
        return isMobile
            ? "Şu an hotspot / mobil veri üzerindesin; kullanım sayılıyor."
            : "Şu an mobil veride değilsin; sayaç yalnızca hotspot / mobil veride artar."
    }
}
