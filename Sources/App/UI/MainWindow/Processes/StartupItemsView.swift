import AppKit
import SwiftUI

struct StartupItemsView: View {
    @State private var model = StartupItemsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.brokenItems.isEmpty { brokenBanner }
            if !model.loaded {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
            } else if model.items.isEmpty && model.backgroundItems.isEmpty && model.backgroundLoaded {
                ContentUnavailableView("Başlangıç öğesi yok", systemImage: "power",
                                       description: Text("LaunchAgents klasörlerinde plist bulunamadı."))
            } else {
                list
            }
            footer
        }
        .task { await model.load() }
        .confirmationDialog("Başlangıç öğesi kaldırılsın mı?", isPresented: removalPresented, presenting: model.pendingRemoval) { item in
            Button("Çöp Kutusu'na taşı", role: .destructive) { Task { await model.remove(item) } }
            Button("Vazgeç", role: .cancel) {}
        } message: { item in
            Text("\(item.name) durdurulur ve plist dosyası Çöp Kutusu'na taşınır; oturum açınca artık başlamaz. Çöp Kutusu'ndan geri koyabilirsiniz.")
        }
    }

    private var brokenBanner: some View {
        Label("\(model.brokenItems.count) bozuk ajan: programı artık yok, her açılışta başarısız olur. Kullanıcı ajanlarını \"Kaldır\" ile Çöp Kutusu'na taşıyabilirsiniz.",
              systemImage: "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(.orange)
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 8))
    }

    private var removalPresented: Binding<Bool> {
        Binding(get: { model.pendingRemoval != nil }, set: { if !$0 { model.pendingRemoval = nil } })
    }

    private var list: some View {
        List {
            itemSection("Kullanıcı ajanları", scope: .user, subtitle: "~/Library/LaunchAgents")
            itemSection("Tüm kullanıcılar için ajanlar", scope: .allUsers, subtitle: "/Library/LaunchAgents · Salt okunur · sudo komutu kopyalanabilir")
            itemSection("Sistem hizmetleri", scope: .daemon, subtitle: "/Library/LaunchDaemons · Salt okunur · sudo komutu kopyalanabilir")
            Section {
                if !model.backgroundLoaded {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Giriş öğeleri okunuyor…").foregroundStyle(.secondary) }
                } else if model.backgroundItems.isEmpty {
                    Text("Giriş öğeleri okunamadı veya yok. Sistem Ayarları'ndan bakın.").foregroundStyle(.secondary)
                } else {
                    ForEach(model.backgroundItems) { BackgroundItemRow(item: $0).listRowSeparator(.visible) }
                }
            } header: {
                sectionHeader("Giriş öğeleri (Arka planda izin ver)", subtitle: "Sistem Ayarları'ndan yönetilir")
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func itemSection(_ title: String, scope: StartupItem.Scope, subtitle: String) -> some View {
        let rows = model.items.filter { $0.scope == scope }
        if !rows.isEmpty {
            Section {
                ForEach(rows) { item in
                    StartupItemRow(item: item, isBusy: model.busy.contains(item.id),
                                   onToggle: { Task { await model.setEnabled(item.status == .disabled, for: item) } },
                                   onRemove: { model.pendingRemoval = item },
                                   onOpenSettings: Self.openLoginItemsSettings)
                    .listRowSeparator(.visible)
                }
            } header: {
                sectionHeader(title, subtitle: subtitle)
            }
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let notice = model.notice {
                Label(notice.text, systemImage: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(notice.isError ? Color.orange : Color.green).lineLimit(2)
                    .id(notice.id)
                    .task(id: notice.id) {
                        try? await Task.sleep(for: .seconds(6))
                        if model.notice?.id == notice.id { model.notice = nil }
                    }
            } else {
                Text("Apple'ın kendi öğelerine dokunulmaz. Yönetici izni gerektirenleri Sistem Ayarları › Genel › Giriş Öğeleri'nden yönetin.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Giriş Öğeleri'ni aç", systemImage: "gearshape", action: Self.openLoginItemsSettings)
        }
        .padding(.bottom, 10)
    }

    private static func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) }
    }
}
