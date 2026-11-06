import SwiftUI

/// Ağ kullanımı tablosunun sağ detay paneli. Depo verisi seçim değişince bir kez yüklenir;
/// canlı değerler (bugün, son 60 sn) üst görünümden gelir.
struct AppInspectorView: View {
    let appID: String
    let usage: AppUsage?
    let last60Bytes: UInt64
    let isBlocked: Bool
    let isMobile: Bool
    let model: AppModel
    let actions: PanelActions
    let onToggleBlock: () -> Void

    @State private var detail: AppDetail?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AppInspectorHeader(appID: appID, isBlocked: isBlocked, limit: model.limit(for: appID))
                AppInspectorUsage(total: usage?.bytes ?? 0, mobile: usage?.mobileBytes ?? 0, last60: last60Bytes)
                Divider()
                InspectorSection(title: "Son 7 gün") {
                    if let detail {
                        Text(Format.bytes(detail.weekTotal))
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                } content: {
                    if let detail {
                        AppDailyBarChart(days: detail.days)
                    } else {
                        loading
                    }
                }
                InspectorSection("Bugün, saat saat") {
                    if let detail {
                        AppHourlyChart(hours: detail.hours, dayStart: detail.dayStart,
                                       emptyMessage: detail.hourlyEmptyMessage(hasTraffic: (usage?.bytes ?? 0) > 0))
                    } else {
                        loading
                    }
                }
                if let detail {
                    AppDomainList(detail: detail, hasTraffic: (usage?.bytes ?? 0) > 0 || detail.weekTotal > 0)
                }
                Divider()
                AppLimitControls(model: model, appID: appID, isBlocked: isBlocked, isMobile: isMobile, onToggleBlock: onToggleBlock)
                AppRuleCauses(model: model, appID: appID)
                Divider()
                AppInspectorActions(appID: appID, actions: actions)
            }
            .padding(16)
        }
        .task(id: appID) {
            detail = nil
            let loaded = await model.appDetail(for: appID)
            guard !Task.isCancelled else { return }
            detail = loaded
        }
    }

    private var loading: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
