import SwiftUI

/// Uygulama bazlı hız sınırı ayarları: sınırlı uygulamalar, ↓/↑ sınırları, "sadece mobilde" ve ekleme.
struct ThrottleSettingsPane: View {
    let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    var body: some View {
        Form {
            Section {
                if model.limitedApps.isEmpty {
                    Text("Henüz sınır yok. Aşağıdan bir uygulama ekle.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.limitedApps, id: \.self) { app in
                        ThrottleAppRow(model: model, app: app)
                    }
                }
            } header: {
                Text("Hız sınırları")
            } footer: {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Uygulama ekle") {
                let candidates = model.usage.today.map(\.app).filter { model.limit(for: $0) == nil }
                if candidates.isEmpty {
                    Text("Bugün trafik üreten başka uygulama yok.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(candidates.prefix(15), id: \.self) { app in
                        HStack {
                            ThrottleAppLabel(app: app)
                            Spacer()
                            Button("Uygulama ekle") {
                                model.setLimit(app, AppLimit(downBytesPerSec: ThrottlePreset.defaultDown))
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        var parts: [String] = []
        if model.installer.state != .active {
            parts.append("Sınırlar için ağ filtresinin kurulu olması gerekir (Filtre bölümü).")
        } else if let e = model.installer.proxyError {
            parts.append("Hız sınırlayıcı başlatılamadı: \(e)")
        } else if model.throttleActive {
            parts.append("Hız sınırlayıcı açık.")
        }
        parts.append("Sınır yeni bağlantılara uygulanır; açık bağlantılar için uygulamayı yeniden başlat. "
                     + "Sınırlı uygulamaların QUIC (UDP 443) trafiği kesilir, tarayıcı TCP'ye döner.")
        return parts.joined(separator: " ")
    }
}

/// Hazır hız değerleri (byte/sn, 1024 tabanlı).
enum ThrottlePreset {
    static let values: [Int] = [250 * 1024, 500 * 1024, 1024 * 1024, 3 * 1024 * 1024, 5 * 1024 * 1024]
    static let defaultDown = 1024 * 1024
}

private struct ThrottleAppLabel: View {
    let app: String

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: AppCatalog.shared.icon(for: app))
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(AppCatalog.shared.name(for: app))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct ThrottleAppRow: View {
    let model: AppModel
    let app: String

    private var limit: AppLimit { model.limit(for: app) ?? AppLimit() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ThrottleAppLabel(app: app)
                Spacer()
                Button("Kaldır", role: .destructive) { model.setLimit(app, nil) }
            }
            HStack(spacing: 16) {
                RatePicker(symbol: "arrow.down", label: "İndirme", value: limit.downBytesPerSec) { v in
                    var l = limit
                    l.downBytesPerSec = v
                    model.setLimit(app, l)
                }
                RatePicker(symbol: "arrow.up", label: "Yükleme", value: limit.upBytesPerSec) { v in
                    var l = limit
                    l.upBytesPerSec = v
                    model.setLimit(app, l)
                }
                Spacer()
                Toggle("Sadece mobilde", isOn: Binding(
                    get: { limit.onlyOnMobile },
                    set: { on in
                        var l = limit
                        l.onlyOnMobile = on
                        model.setLimit(app, l)
                    }))
                    .toggleStyle(.checkbox)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Hazır değerler + "Sınırsız" + özel değer (KB/s).
private struct RatePicker: View {
    let symbol: String
    let label: String
    let value: Int?
    let onChange: (Int?) -> Void

    @State private var showCustom = false
    @State private var customKB = ""

    var body: some View {
        Menu {
            Button("Sınırsız") { onChange(nil) }
            Divider()
            ForEach(ThrottlePreset.values, id: \.self) { v in
                Button(AppModel.rateText(v)) { onChange(v) }
            }
            Divider()
            Button("Özel…") {
                customKB = value.map { String($0 / 1024) } ?? ""
                showCustom = true
            }
        } label: {
            Label(value.map(AppModel.rateText) ?? "Sınırsız", systemImage: symbol)
                .monospacedDigit()
        }
        .fixedSize()
        .accessibilityLabel("\(label) sınırı")
        .popover(isPresented: $showCustom, arrowEdge: .bottom) {
            HStack {
                TextField("KB/s", text: $customKB)
                    .frame(width: 80)
                    .onSubmit(applyCustom)
                Text("KB/s")
                Button("Uygula", action: applyCustom)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    private func applyCustom() {
        let kb = Int(customKB.trimmingCharacters(in: .whitespaces)) ?? 0
        onChange(kb > 0 ? kb * 1024 : nil)
        showCustom = false
    }
}
