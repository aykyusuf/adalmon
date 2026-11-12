import SwiftUI

struct FilterSettingsTab: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Ağ filtresi") {
                LabeledContent("Durum", value: filterStatus)
                if case .reconnecting = model.filterLink {
                    Button("Filtreyi yeniden bağla", systemImage: "arrow.triangle.2.circlepath") { model.reconnectFilter() }
                        .help("Filtre uzantısıyla bağlantıyı yeniden kurar ve ayarları yeniden gönderir; filtre ayarını değiştirmez.")
                }
                HStack {
                    Button("Kur / Yeniden kur") { model.installer.install() }
                    Button("Kaldır", role: .destructive) { model.installer.uninstall() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var filterStatus: String {
        if model.filterConnected { return "Aktif" }
        switch model.installer.state {
        case .active:
            if case .reconnecting(let since) = model.filterLink {
                return "Kurulu ama uzantıya bağlanılamıyor · yeniden deneniyor (kopma: \(since.formatted(date: .omitted, time: .shortened)))"
            }
            return "Kurulu, bağlanıyor…"
        case .needsApproval: return "Onay bekliyor (Sistem Ayarları)"
        case .installing: return "Kuruluyor…"
        case .failed(let e): return "Hata: \(e)"
        default: return "Kurulu değil"
        }
    }
}
