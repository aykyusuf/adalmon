import AppKit
import SwiftUI

/// "Başlangıç": ~/Library/LaunchAgents ve /Library/LaunchAgents plist'leri (salt okunur).
struct StartupItemsView: View {
    @State private var items: [StartupItem] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !loaded {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
            } else if items.isEmpty {
                ContentUnavailableView("Başlangıç öğesi yok", systemImage: "power",
                                       description: Text("LaunchAgents klasörlerinde plist bulunamadı."))
            } else {
                List(items) { item in
                    StartupItemRow(item: item)
                        .listRowSeparator(.visible)
                }
                .listStyle(.plain)
            }
            HStack {
                Text("Salt okunur liste: yalnızca LaunchAgents. Giriş öğelerini Sistem Ayarları › Genel › Giriş Öğeleri'nden yönetin.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Giriş Öğeleri'ni aç", systemImage: "gearshape") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) }
                }
            }
            .padding(.bottom, 10)
        }
        .task {
            items = await Task.detached(priority: .utility) { StartupItemScanner.scan() }.value
            loaded = true
        }
    }
}

private struct StartupItemRow: View {
    let item: StartupItem

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon).resizable().scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1)
                Text(item.program ?? item.plistPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(item.scope.rawValue).font(.caption).foregroundStyle(.secondary)
            Text(item.status.title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(statusColor.opacity(0.18), in: .capsule)
                .foregroundStyle(statusColor)
            Button("Finder'da göster", systemImage: "folder") { ProcessActions.reveal(path: item.plistPath) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Finder'da göster")
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Finder'da göster", systemImage: "folder") { ProcessActions.reveal(path: item.plistPath) }
            Button("Yolu kopyala", systemImage: "doc.on.doc") { ProcessActions.copy(item.program ?? item.plistPath) }
        }
    }

    private var icon: NSImage {
        if let program = item.program, program.hasPrefix("/") { return NSWorkspace.shared.icon(forFile: AppNaming.outermostApp(of: program)) }
        return NSWorkspace.shared.icon(forFile: item.plistPath)
    }

    private var statusColor: Color {
        switch item.status {
        case .enabled: .green
        case .disabled: .secondary
        case .unknown: .orange
        }
    }
}
