import AppKit
import SwiftUI

struct StartupCleanupView: View {
    @State private var model: StartupItemsModel

    private let accent = CleanupAccent.startup

    init(model: StartupItemsModel = StartupItemsModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        content
            .overlay(alignment: .bottom) { noticeToast }
            .task { await model.load() }
            .confirmationDialog("Başlangıç öğesi kaldırılsın mı?", isPresented: removalPresented, presenting: model.pendingRemoval) { item in
                Button("Çöp Kutusu'na taşı", role: .destructive) { Task { await model.remove(item) } }
                Button("Vazgeç", role: .cancel) {}
            } message: { item in
                Text("\(item.name) durdurulur ve plist dosyası Çöp Kutusu'na taşınır; oturum açınca artık başlamaz. Çöp Kutusu'ndan geri koyabilirsiniz.")
            }
    }

    private var removalPresented: Binding<Bool> {
        Binding(get: { model.pendingRemoval != nil }, set: { if !$0 { model.pendingRemoval = nil } })
    }

    @ViewBuilder
    private var content: some View {
        if !model.loaded {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Başlangıç öğeleri okunuyor…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.items.isEmpty && model.backgroundItems.isEmpty && model.backgroundLoaded {
            CleanupAllCleanView(accent: accent, title: "Başlangıç öğesi yok",
                                subtitle: "LaunchAgents klasörlerinde plist bulunamadı.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    itemSection("Kullanıcı ajanları", scope: .user, subtitle: "Oturum açınca sizin için başlar")
                    itemSection("Tüm kullanıcılar için ajanlar", scope: .allUsers, subtitle: "Salt okunur · sudo komutu kopyalanabilir")
                    itemSection("Sistem hizmetleri", scope: .daemon, subtitle: "Salt okunur · sudo komutu kopyalanabilir")
                    backgroundSection
                    footer
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: Kahraman başlık

    private var hero: some View {
        let total = model.items.count + model.backgroundItems.count
        let broken = model.brokenItems.count
        let active = model.items.filter { $0.status != .disabled }.count + model.backgroundItems.filter(\.isEnabled).count
        return HStack(spacing: 18) {
            CleanupHeroArtwork(symbol: "power", accent: accent, badgeSymbol: broken > 0 ? "exclamationmark" : nil, size: 92)
                .frame(width: 124, height: 124)
            VStack(alignment: .leading, spacing: 6) {
                Text("Başlangıç").font(.largeTitle.weight(.bold))
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(total)").font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(LinearGradient(colors: [accent.light, accent.deep], startPoint: .top, endPoint: .bottom))
                    Text("öğe").font(.title3).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    chip("\(active) açık", color: .green)
                    if broken > 0 { chip("\(broken) bozuk", color: .orange) }
                }
                Text(broken > 0
                     ? "Bozuk ajanların programı artık yok, her açılışta başarısız olur. Kullanıcı ajanlarını kaldırmak güvenlidir."
                     : "Oturum açınca kendiliğinden başlayan öğeler. Apple'ın kendi öğelerine dokunulmaz.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text).font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(color.opacity(0.16), in: .capsule)
            .foregroundStyle(color)
    }

    // MARK: Bölümler

    @ViewBuilder
    private func itemSection(_ title: String, scope: StartupItem.Scope, subtitle: String) -> some View {
        let rows = model.items.filter { $0.scope == scope }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(title, subtitle: subtitle)
                ForEach(rows) { item in
                    StartupItemCard(item: item, accent: accent, isBusy: model.busy.contains(item.id),
                                    onToggle: { Task { await model.setEnabled(item.status == .disabled, for: item) } },
                                    onRemove: { model.pendingRemoval = item },
                                    onOpenSettings: Self.openLoginItemsSettings)
                }
            }
        }
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Giriş öğeleri", subtitle: "Sistem Ayarları'ndan yönetilir")
            if !model.backgroundLoaded {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Giriş öğeleri okunuyor…").foregroundStyle(.secondary) }
                    .padding(.horizontal, 4)
            } else if model.backgroundItems.isEmpty {
                Text("Giriş öğeleri okunamadı veya yok. Sistem Ayarları'ndan bakın.").font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            } else {
                ForEach(model.backgroundItems) { StartupBackgroundCard(item: $0, accent: accent) }
            }
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Yönetici izni gerektirenleri Sistem Ayarları › Genel › Giriş Öğeleri'nden yönetin.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Giriş Öğeleri'ni aç", systemImage: "gearshape", action: Self.openLoginItemsSettings).controlSize(.regular)
        }
        .padding(.horizontal, 4)
    }

    // MARK: Bildirim

    @ViewBuilder
    private var noticeToast: some View {
        if let notice = model.notice {
            Label(notice.text, systemImage: notice.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.callout).foregroundStyle(notice.isError ? Color.orange : Color.green).lineLimit(2)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: .capsule)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                .padding(.bottom, 12)
                .id(notice.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: notice.id) {
                    try? await Task.sleep(for: .seconds(6))
                    if model.notice?.id == notice.id { model.notice = nil }
                }
        }
    }

    private static func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) }
    }
}
