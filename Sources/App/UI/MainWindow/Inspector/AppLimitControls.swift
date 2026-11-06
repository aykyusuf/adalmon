import SwiftUI

/// Uygulama hız sınırı ve mobilde engelleme kontrolleri.
struct AppLimitControls: View {
    let model: AppModel
    let appID: String
    let isBlocked: Bool
    let isMobile: Bool
    let onToggleBlock: () -> Void

    var body: some View {
        let limit = model.limit(for: appID)
        InspectorSection(title: "Kontrol") {
            if limit != nil {
                Button("Sınırı kaldır", role: .destructive) { model.setLimit(appID, nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                blockRow
                Divider()
                if let limit {
                    InspectorRatePicker(symbol: "arrow.down", label: "İndirme", value: limit.downBytesPerSec) { v in
                        var l = limit
                        l.downBytesPerSec = v
                        model.setLimit(appID, l)
                    }
                    InspectorRatePicker(symbol: "arrow.up", label: "Yükleme", value: limit.upBytesPerSec) { v in
                        var l = limit
                        l.upBytesPerSec = v
                        model.setLimit(appID, l)
                    }
                    HStack {
                        Text("Yalnızca mobil veride")
                        Spacer(minLength: 8)
                        Toggle("Yalnızca mobil veride", isOn: onlyMobileBinding(limit))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                } else {
                    HStack {
                        Label("Hız sınırı yok", systemImage: "speedometer")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button("Hız sınırı koy") {
                            model.setLimit(appID, AppLimit(downBytesPerSec: ThrottlePreset.defaultDown))
                        }
                    }
                }
                if model.installer.state != .active {
                    Label("Sınırlar ve engeller için ağ filtresinin kurulu olması gerekir.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var blockRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Mobil veride engelle", systemImage: "hand.raised")
                Text(isBlocked
                     ? (isMobile ? "Şu an mobil verideyken engelli." : "Mobil veriye geçince uygulanır.")
                     : "Wi-Fi'de etkilenmez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle("Mobil veride engelle", isOn: blockBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    /// Anahtar durumu `isBlocked`'u yansıtır; açmak onay akışını başlatır (durumu üst görünüm yönetir).
    private var blockBinding: Binding<Bool> {
        Binding(get: { isBlocked }, set: { _ in onToggleBlock() })
    }

    private func onlyMobileBinding(_ limit: AppLimit) -> Binding<Bool> {
        Binding(get: { limit.onlyOnMobile }, set: { on in
            var l = limit
            l.onlyOnMobile = on
            model.setLimit(appID, l)
        })
    }
}
