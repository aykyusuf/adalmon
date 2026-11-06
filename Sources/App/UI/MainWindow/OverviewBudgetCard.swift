import SwiftUI

/// Mobil kota mini kartı: günlük bütçe, (varsa) aylık dönem ve dolma tahmini. Tıklayınca "Mobil veri"ye gider.
struct OverviewBudgetCard: View {
    let budget: BudgetSnapshot
    let router: SettingsRouter

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Mobil kota", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                QuotaGauge(title: "Bugün", used: budget.todayUsedBytes, cap: budget.effectiveDailyCapBytes,
                           detail: OverviewBudgetSummary.etaText(budget))
                if let monthly = budget.monthlyCapBytes {
                    QuotaGauge(title: "Bu dönem", used: budget.cycleUsedBytes, cap: monthly,
                               detail: periodDetail)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Mobil veri sayfasını açar")
    }

    private var periodDetail: String {
        var parts = [OverviewBudgetSummary.daysText(budget)]
        if let projected = budget.projectedCycleBytes, let cap = budget.monthlyCapBytes {
            parts.append("tahmin \(Format.bytes(projected))" + (projected > cap ? " (limit aşılır)" : ""))
        }
        return parts.joined(separator: " · ")
    }

    private func open() {
        router.selectedMainSection = .mobile
    }
}
