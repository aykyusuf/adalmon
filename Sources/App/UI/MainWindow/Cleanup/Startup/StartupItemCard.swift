import AppKit
import SwiftUI

/// Başlangıç öğesi kartı: uygulama simgesi, ad, program yolu, durum, tek anahtar. Ayrıntılı eylemler "…" menüsünde.
/// Yönetici gerektiren (salt okunur) öğelerde anahtar yerine kilit + sudo komutunu kopyala düğmesi vardır; komut asla çalıştırılmaz.
struct StartupItemCard: View {
    let item: StartupItem
    let accent: CleanupAccent
    let isBusy: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void
    let onOpenSettings: () -> Void

    @State private var copied = false
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var permissions: StartupItemPermissions { .evaluate(item) }
    private var isOn: Bool { item.status != .disabled }
    private var adminCommand: String? { StartupItemCommands.adminCommand(for: item) }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon).resizable().scaledToFit().frame(width: 34, height: 34).accessibilityHidden(true)
                .opacity(isOn ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).font(.body.weight(.medium)).lineLimit(1)
                    if item.isBroken { badge("Bozuk", color: .orange) }
                }
                Text(item.program ?? item.plistPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if let problem = item.problem {
                    Label(problem.title, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if isBusy { ProgressView().controlSize(.small) }
            trailing
            moreMenu
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.primary.opacity(hovered ? 0.08 : 0.05), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(item.isBroken ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1))
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
        .contextMenu { menuItems }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var trailing: some View {
        if permissions.canModify {
            Toggle(isOn ? "Devre dışı bırak" : "Etkinleştir", isOn: Binding(get: { isOn }, set: { _ in onToggle() }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
                .tint(accent.base)
                .disabled(isBusy)
                .help(isOn ? "Devre dışı bırak: durdurur ve oturum açınca başlamasını engeller" : "Etkinleştir: yeniden başlatır")
            if item.isBroken {
                Button("Kaldır", role: .destructive, action: onRemove).controlSize(.small).disabled(isBusy)
            }
        } else {
            if let reason = permissions.reason {
                Image(systemName: permissions.needsAdmin ? "lock.fill" : "lock.shield")
                    .font(.callout).foregroundStyle(.tertiary).help(reason).accessibilityLabel(reason)
            }
            badge(item.status.title, color: item.status == .enabled ? .green : .secondary)
            if let adminCommand {
                Button { copy(adminCommand) } label: {
                    Label(copied ? "Kopyalandı" : "sudo komutunu kopyala", systemImage: copied ? "checkmark" : "terminal")
                        .labelStyle(.iconOnly)
                        .symbolEffect(.bounce, value: reduceMotion ? false : copied)
                        .foregroundStyle(copied ? Color.green : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help("Salt okunur. Terminal'de yönetici parolasıyla çalıştırın:\n\(adminCommand)")
            }
        }
    }

    private var moreMenu: some View {
        Menu { menuItems } label: { Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Diğer eylemler")
    }

    @ViewBuilder
    private var menuItems: some View {
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

    private func copy(_ text: String) {
        ProcessActions.copy(text)
        withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text).font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
            .accessibilityLabel(item.isBroken && text == "Bozuk" ? "Bozuk ajan: \(item.problem?.title ?? "")" : "Durum: \(text)")
    }

    private var icon: NSImage {
        if let program = item.program, program.hasPrefix("/") { return NSWorkspace.shared.icon(forFile: AppNaming.outermostApp(of: program)) }
        return NSWorkspace.shared.icon(forFile: item.plistPath)
    }
}

/// Modern giriş öğesi (SMAppService) kartı: salt okunur.
struct StartupBackgroundCard: View {
    let item: BackgroundItem
    let accent: CleanupAccent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind == .agent ? "gearshape.2.fill" : "person.crop.circle.badge.checkmark")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(accent.gradient))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.medium)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(item.isEnabled ? "Açık" : "Kapalı")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background((item.isEnabled ? Color.green : Color.secondary).opacity(0.18), in: .capsule)
                .foregroundStyle(item.isEnabled ? Color.green : Color.secondary)
                .accessibilityLabel("Durum: \(item.isEnabled ? "Açık" : "Kapalı")")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
        .help("\(item.identifier) · Sistem Ayarları › Genel › Giriş Öğeleri'nden yönetilir")
    }

    private var subtitle: String {
        [item.detail, item.kind.title, item.developer ?? "Geliştirici bilgisi yok"].compactMap { $0 }.joined(separator: " · ")
    }
}
