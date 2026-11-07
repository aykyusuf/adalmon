import SwiftUI

/// "İşlemler" araç çubuğu: Yeni görev çalıştır + seçili satır eylemleri. İzin yoksa soluk; ipucu nedeni söyler.
struct ProcessToolbar: ToolbarContent {
    let live: ProcessLiveModel

    var body: some ToolbarContent {
        let row = live.row(id: live.selection)
        let permissions = row.map { live.permissions(for: $0) }
        let denied = permissions?.reason
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Yeni görev çalıştır", systemImage: "plus.app") { ProcessActions.runNewTask() }
                .help("Bir uygulama seçip çalıştır")
            Button("İşlemi sonlandır", systemImage: "xmark.circle") { if let row { live.requestKill(row) } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!(permissions?.canControl ?? false))
                .help(denied ?? "Seçili işlemi sonlandır (⌫ / ⌘⌫)")
            Button("Yeniden başlat", systemImage: "arrow.clockwise") { if let row { live.restart(row) } }
                .disabled(!(permissions?.canRestart ?? false))
                .help(denied ?? "Seçili uygulamayı kapatıp yeniden aç")
            Button(row?.isSuspended == true ? "Devam ettir" : "Askıya al",
                   systemImage: row?.isSuspended == true ? "play.circle" : "pause.circle") { if let row { live.toggleSuspend(row) } }
                .disabled(!(permissions?.canControl ?? false))
                .help(denied ?? "Seçili işlemi askıya al / devam ettir (SIGSTOP / SIGCONT)")
            Button("Verimlilik modu", systemImage: row?.isEfficient == true ? "leaf.fill" : "leaf") { if let row { live.toggleEfficiency(row) } }
                .disabled(!(permissions?.canControl ?? false))
                .help(denied ?? "Seçili işlemi düşük öncelikli (arka plan) çalıştır")
            Button("Bilgi", systemImage: "info.circle") { live.infoRow = row }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(row == nil)
                .help("Seçili işlemin ayrıntıları (⌘I)")
        }
    }
}
