import SwiftUI

/// Genel bakışın altındaki ince durum şeridi: dikkat çipleri (varsa), ajanlar, açık kalma süresi, bağlantı rozeti.
struct OverviewStatusStrip: View {
    let attention: [OverviewAttention]
    /// Ajan özelliği kapalıysa nil.
    let agents: AgentSummary?
    let data: PanelData
    let router: SettingsRouter
    var boot: Date? = UptimeSummary.systemBoot

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                chips
                Spacer(minLength: 8)
                status
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { chips }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    status
                }
            }
        }
        .font(.caption)
    }

    @ViewBuilder private var chips: some View {
        ForEach(attention) { item in
            let tint = Self.tint(item.severity)
            Button { item.destination.open(router) } label: {
                Label(item.title, systemImage: item.symbol)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(tint)
                    .background(tint.opacity(0.14), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .help(item.detail)
            .accessibilityLabel("\(item.title). \(item.detail)")
        }
    }

    @ViewBuilder private var status: some View {
        HStack(spacing: 12) {
            if let agents, agents.sessions > 0 {
                Button { router.selectedMainSection = .agentOffice } label: {
                    Label(agents.working > 0 ? "\(agents.working) ajan çalışıyor" : "\(agents.sessions) ajan oturumu",
                          systemImage: "person.2.fill")
                        .foregroundStyle(agents.working > 0 ? AnyShapeStyle(.purple) : AnyShapeStyle(.secondary))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("\(agents.sessions) açık oturum · Ajan ofisini açar")
            }
            if boot != nil {
                TimelineView(.everyMinute) { context in
                    if let summary = UptimeSummary.make(boot: boot, now: context.date) {
                        Label("açık \(summary.shortDuration)", systemImage: "power")
                            .foregroundStyle(.secondary)
                            .help("Açık kalma süresi \(summary.duration) · Son açılış \(summary.boot)")
                    }
                }
            }
            ConnectionBadge(medium: data.medium, isMobile: data.isMobile, interfaceName: data.interfaceName)
        }
        .lineLimit(1)
        .fixedSize()
    }

    static func tint(_ severity: OverviewAttention.Severity) -> Color {
        switch severity {
        case .info: .blue
        case .warning: .orange
        case .critical: .red
        }
    }
}
