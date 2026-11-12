import AppKit
import SwiftUI

struct StartupItemRow: View {
    let item: StartupItem
    let isBusy: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void
    let onOpenSettings: () -> Void

    private var permissions: StartupItemPermissions { .evaluate(item) }
    private var isOn: Bool { item.status != .disabled }
    private var adminCommand: String? { StartupItemCommands.adminCommand(for: item) }
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon).resizable().scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1)
                Text(item.program ?? item.plistPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if let problem = item.problem {
                    Label(problem.title, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).lineLimit(1)
                        .help("Bu ajan her açılışta başarısız olur; kaldırmak güvenlidir")
                }
            }
            Spacer(minLength: 8)
            if let reason = permissions.reason {
                Image(systemName: permissions.needsAdmin ? "lock.fill" : "lock.shield")
                    .font(.caption).foregroundStyle(.tertiary)
                    .help(reason)
                    .accessibilityLabel(reason)
            }
            if item.isBroken { brokenBadge }
            statusBadge
            if isBusy { ProgressView().controlSize(.small) }
            actionButtons
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button(isOn ? "Devre dışı bırak" : "Etkinleştir", systemImage: isOn ? "pause.circle" : "play.circle", action: onToggle)
                .disabled(isBusy || !permissions.canModify)
            Button("Kaldır…", systemImage: "trash", role: .destructive, action: onRemove)
                .disabled(isBusy || !permissions.canModify)
            Divider()
            Button("Finder'da göster", systemImage: "folder") { ProcessActions.reveal(path: item.plistPath) }
            Button("Yolu kopyala", systemImage: "doc.on.doc") { ProcessActions.copy(item.program ?? item.plistPath) }
            if let adminCommand {
                Button("sudo komutunu kopyala", systemImage: "terminal") { copy(adminCommand) }
            }
            if permissions.needsAdmin {
                Button("Giriş Öğeleri'ni aç", systemImage: "gearshape", action: onOpenSettings)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            Button(isOn ? "Devre dışı bırak" : "Etkinleştir", systemImage: isOn ? "pause.circle" : "play.circle", action: onToggle)
                .disabled(isBusy || !permissions.canModify)
                .help(permissions.reason ?? (isOn ? "Devre dışı bırak: durdurur ve oturum açınca başlamasını engeller" : "Etkinleştir: yeniden başlatır"))
            if let adminCommand {
                Button(copied ? "Kopyalandı" : "sudo komutunu kopyala", systemImage: copied ? "checkmark" : "terminal") { copy(adminCommand) }
                    .help("Salt okunur. Terminal'de yönetici parolasıyla çalıştırın:\n\(adminCommand)")
            }
            Button("Kaldır", systemImage: "trash", role: .destructive, action: onRemove)
                .disabled(isBusy || !permissions.canModify)
                .foregroundStyle(item.isBroken && permissions.canModify ? Color.red : Color.primary)
                .help(permissions.reason ?? "Kaldır: plist dosyasını Çöp Kutusu'na taşır")
            Button("Finder'da göster", systemImage: "folder") { ProcessActions.reveal(path: item.plistPath) }
                .help("Finder'da göster")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.regular)
    }

    private func copy(_ text: String) {
        ProcessActions.copy(text)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private var brokenBadge: some View {
        Text("Bozuk")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Color.orange.opacity(0.18), in: .capsule)
            .foregroundStyle(Color.orange)
            .accessibilityLabel("Bozuk ajan: \(item.problem?.title ?? "")")
    }

    private var statusBadge: some View {
        Text(item.status.title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(statusColor.opacity(0.18), in: .capsule)
            .foregroundStyle(statusColor)
            .accessibilityLabel("Durum: \(item.status.title)")
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
