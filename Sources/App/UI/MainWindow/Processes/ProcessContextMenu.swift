import SwiftUI

/// Satır bağlam menüsü: Görev Yöneticisi sınıfı eylemler. İzin verilmeyenler soluk; nedeni menünün başında yazar.
struct ProcessContextMenu: View {
    let row: LiveRow
    let model: AppModel
    let router: SettingsRouter
    let live: ProcessLiveModel

    var body: some View {
        let permissions = live.permissions(for: row)
        if let reason = permissions.reason {
            Button(reason) {}.disabled(true)
            Divider()
        }
        Button("İşlemi sonlandır…", systemImage: "xmark.circle") { live.requestKill(row) }
            .disabled(!permissions.canControl)
        if !row.isMember {
            Button("Uygulamayı yeniden başlat", systemImage: "arrow.clockwise") { live.restart(row) }
                .disabled(!permissions.canRestart)
        }
        Button(row.isSuspended ? "Devam ettir" : "Askıya al", systemImage: row.isSuspended ? "play.circle" : "pause.circle") {
            live.toggleSuspend(row)
        }
        .disabled(!permissions.canControl)
        Menu("Öncelik", systemImage: "gauge.with.dots.needle.33percent") {
            ForEach(ProcessPriorityPlan.presets, id: \.nice) { preset in
                Button(preset.title + (preset.nice == 0 ? "" : " (nice \(preset.nice))")) { live.setNice(row, to: preset.nice) }
            }
            Divider()
            Button("Önceliği artırmak root gerektirir; yalnızca düşürülebilir.") {}.disabled(true)
        }
        .disabled(!permissions.canControl)
        Button(row.isEfficient ? "Verimlilik modundan çıkar" : "Verimlilik modu", systemImage: row.isEfficient ? "leaf.fill" : "leaf") {
            live.toggleEfficiency(row)
        }
        .disabled(!permissions.canControl)
        Divider()
        Button("Dosya konumunu aç", systemImage: "folder") { if let path = row.path { ProcessActions.reveal(path: path) } }
            .disabled(!permissions.canRevealFile)
        Button("Webde ara", systemImage: "magnifyingglass") { ProcessActions.searchWeb(for: row.name) }
        Button("Bilgi…", systemImage: "info.circle") { live.infoRow = row }
        Divider()
        if !row.isMember {
            Menu("Ağ", systemImage: "network") {
                Button("Ağ kullanımına git", systemImage: "arrow.up.arrow.down") {
                    router.selectedAppID = row.key
                    router.selectedMainSection = .network
                }
                .disabled(!permissions.canNetworkControl)
                Button("Hız sınırı koy…", systemImage: "speedometer") { live.limitRow = row }
                    .disabled(!permissions.canNetworkControl)
                let blocked = model.prefs.blockedOnMobile.contains(row.key)
                Button(blocked ? "Mobil engelini kaldır" : "Mobilde engelle", systemImage: "nosign") { live.toggleBlockOnMobile(row) }
                    .disabled(!permissions.canNetworkControl)
                Button("Bağlantıları yenile", systemImage: "arrow.triangle.2.circlepath") { live.resetConnections(row) }
                    .disabled(!permissions.canNetworkControl)
            }
        }
        Button("Örnek al (sample)", systemImage: "waveform.path.ecg.rectangle") { live.sample(row) }
            .disabled(!permissions.canControl)
        Menu("Kopyala", systemImage: "doc.on.doc") {
            Button("Ad") { ProcessActions.copy(row.name) }
            if let path = row.path { Button("Yol") { ProcessActions.copy(path) } }
            Button(row.isMember ? "PID" : "PID'ler") { ProcessActions.copy(row.pids.map(String.init).joined(separator: ", ")) }
            Button("Tüm bilgi") { ProcessActions.copy(live.infoText(for: row)) }
        }
        if live.canExpand(row) {
            Divider()
            let open = live.expanded.contains(row.key)
            Button(open ? "Süreçleri gizle" : "Süreçleri göster", systemImage: open ? "chevron.up" : "chevron.down") {
                live.setExpanded(row.key, !open, service: model.resources, model: model)
            }
        }
    }
}
