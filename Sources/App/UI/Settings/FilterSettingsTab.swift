import SwiftUI

struct FilterSettingsTab: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Ağ filtresi") {
                LabeledContent("Durum", value: filterStatus)
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
        case .active: return "Kurulu, bağlanıyor…"
        case .needsApproval: return "Onay bekliyor (Sistem Ayarları)"
        case .installing: return "Kuruluyor…"
        case .failed(let e): return "Hata: \(e)"
        default: return "Kurulu değil"
        }
    }
}
