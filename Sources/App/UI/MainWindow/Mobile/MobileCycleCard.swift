import SwiftUI

/// Fatura dönemi: kullanım, aylık limit, kalan, dönem sonu tahmini.
struct MobileCycleCard: View {
    let budget: BudgetSnapshot

    private var periodText: String {
        let end = UsageStore.keyCalendar.date(byAdding: .day, value: -1, to: budget.nextCycleStart) ?? budget.nextCycleStart
        return "\(MobileText.day(budget.cycleStart)) – \(MobileText.day(end))"
    }

    var body: some View {
        MobileCard(title: "Fatura dönemi", systemImage: "calendar") {
            Text(periodText)
                .font(.callout)
                .foregroundStyle(.secondary)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                if let cap = budget.monthlyCapBytes {
                    limited(cap: cap)
                } else {
                    unlimited
                }
            }
        }
    }

    private func limited(cap: UInt64) -> some View {
        let used = budget.cycleUsedBytes
        let fraction = cap == 0 ? 0 : min(1, Double(used) / Double(cap))
        let tint: Color = fraction >= 1 ? .red : (fraction >= 0.8 ? .orange : .green)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Format.bytes(used))
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(fraction >= 0.8 ? tint : .primary)
                Text("/ \(Format.bytes(cap)) · \(Format.percent(fraction))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            UsageBar(fraction: fraction, tint: tint, height: 10)
                .accessibilityElement()
                .accessibilityLabel("Dönem mobil kullanımı")
                .accessibilityValue("Dönem kullanımı \(Format.bytes(used)) / \(Format.bytes(cap)), yüzde \(Int(fraction * 100))")
            HStack(alignment: .top, spacing: 16) {
                MobileStat(title: "Kalan", value: Format.bytes(budget.remainingBytes ?? 0), tint: (budget.remainingBytes ?? 0) == 0 ? .red : .primary)
                MobileStat(title: "Kalan gün", value: MobileText.days(budget.daysLeft))
            }
            projection(cap: cap)
        }
    }

    private var unlimited: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Format.bytes(budget.cycleUsedBytes))
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text("bu dönemde")
                    .foregroundStyle(.secondary)
            }
            if let projected = budget.projectedCycleBytes {
                MobileStat(title: "Dönem sonu tahmini", value: "~\(Format.bytes(projected))")
            }
            Label("Aylık limit belirlersen kalan kullanım ve dinamik günlük bütçe hesaplanır.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func projection(cap: UInt64) -> some View {
        if let projected = budget.projectedCycleBytes {
            let over = projected > cap
            Label(over
                  ? "Bu gidişle dönem sonunda ~\(Format.bytes(projected)) olur; aylık limiti aşabilir."
                  : "Bu gidişle dönem sonunda ~\(Format.bytes(projected)) olur; limitin altında kalır.",
                  systemImage: over ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.caption)
                .foregroundStyle(over ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Label("Dönem sonu tahmini için en az bir tam gün kullanım gerekir.", systemImage: "hourglass")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
