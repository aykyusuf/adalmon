import SwiftUI

/// Ekran koruyucu ("Adalmon Video"): kütüphanedeki videoları Mac boştayken oynatır. Kurulum kullanıcı düzeyindedir
/// (~/Library/Screen Savers), yönetici gerekmez; videolar /Users/Shared/Adalmon/Saver altına klonlanır (aynı birimde ek disk alanı yok).
struct WallpaperSaverCard: View {
    @Bindable var wallpaper: WallpaperService
    @Bindable var saver: SaverService
    @State private var confirmInstall = false
    @State private var confirmClear = false

    private struct RefreshKey: Hashable {
        var settings: SaverSettings
        var itemIDs: [UUID]
        var defaultID: UUID?
        var mode: PlaylistMode
    }

    private var refreshKey: RefreshKey {
        RefreshKey(settings: saver.settings, itemIDs: wallpaper.items.map(\.id), defaultID: wallpaper.settings.defaultItemID, mode: wallpaper.settings.playlistMode)
    }

    /// Oynatma kartındaki ayarların özeti (ekran koruyucu aynısını kullanır).
    private var loopSummary: String {
        let loop = wallpaper.settings.loop
        let transition = loop.transition == .crossfade ? "\(WallpaperPlaybackCard.label(loop.crossfadeSeconds)) çapraz geçiş" : "geçiş kapalı"
        return "Oynatma (Oynatma kartıyla aynı): baştan \(WallpaperPlaybackCard.label(loop.trimStart)) atlanır, sondan \(WallpaperPlaybackCard.label(loop.trimEnd)) kesilir, \(transition)."
    }

    private var eligible: [WallpaperItem] { SaverSelection.eligible(wallpaper.items) }

    var body: some View {
        RulesCard(title: "Ekran koruyucu", systemImage: "sparkles.tv",
                  subtitle: "\"Adalmon Video\": kendi videolarınızı Mac boştayken ekran koruyucu olarak oynatır. 4K HEVC / H.264 dönüştürülmeden çalar.") {
            statusRow
            Picker("Videolar", selection: $saver.settings.source) {
                ForEach(SaverSource.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            if saver.settings.source == .picked { pickList }
            Toggle("Karışık sırayla oynat", isOn: $saver.settings.shuffle)
            Label(loopSummary, systemImage: "repeat").font(.caption).foregroundStyle(.secondary)
            summary
            actions
            if let progress = saver.progress {
                HStack {
                    ProgressView(value: progress)
                    Button("Vazgeç", systemImage: "xmark.circle.fill") { saver.cancel() }
                        .labelStyle(.iconOnly).buttonStyle(.plain)
                }
            }
            if let message = saver.message { Text(message).font(.caption) }
            Divider()
            notes
        }
        .task(id: refreshKey) { await saver.refresh(wallpaper: wallpaper) }
        .onChange(of: wallpaper.settings.loop) { _, new in saver.syncLoop(new.timing) }
        .confirmationDialog("Videolar kopyalansın mı?", isPresented: $confirmInstall) {
            Button(saver.isInstalled ? "Güncelle" : "Kur") { saver.install(wallpaper: wallpaper) }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            if let plan = saver.plan {
                Text("\(plan.bytesToWrite.formatted(.byteCount(style: .file))) kopyalanacak (boş alan \(plan.freeBytes.formatted(.byteCount(style: .file)))). Diskiniz neredeyse doluysa önce yer açın.")
            }
        }
        .confirmationDialog("Kopyalanan videolar silinsin mi?", isPresented: $confirmClear) {
            Button("Sil", role: .destructive) { saver.clearContent(wallpaper: wallpaper) }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Yalnızca /Users/Shared/Adalmon/Saver içindeki kopyalar silinir; özgün videolarınıza dokunulmaz. Ekran koruyucu yeniden hazırlanana kadar boş kalır.")
        }
    }

    // MARK: Parçalar

    private var statusRow: some View {
        HStack(spacing: 8) {
            switch saver.status {
            case .notInstalled:
                Label("Kurulu değil", systemImage: "circle.dashed").foregroundStyle(.secondary)
            case .installed(let fp):
                Label("Kurulu (\(fp.display))", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .updateNeeded(let installed, let available):
                Label("Güncelleme gerekli (\(installed.display) → \(available.display))", systemImage: "arrow.triangle.2.circlepath.circle.fill").foregroundStyle(.orange)
            case .foreign:
                Label("Aynı adlı başka bir paket var", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .unavailable:
                Label("Bu derlemede ekran koruyucu paketi yok", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            }
        }
        .font(.callout.weight(.medium))
    }

    @ViewBuilder private var pickList: some View {
        if eligible.isEmpty {
            Text("Kütüphanede uygun video yok. Önce yukarıdaki Kütüphane'ye bir video ekleyin.").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(eligible) { item in
                    HStack {
                        Toggle(item.name, isOn: pickedBinding(item.id)).lineLimit(1)
                        Spacer(minLength: 8)
                        if let info = item.info {
                            Text(info.qualityText).font(.caption2.weight(.medium))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.quaternary, in: .capsule)
                        }
                        Text(item.byteSize.formatted(.byteCount(style: .file))).font(.caption).foregroundStyle(.secondary)
                        if !item.isOptimized {
                            Button("Pil dostu kopya", systemImage: "leaf") { wallpaper.convert(item.id) }
                                .controlSize(.small)
                                .disabled(wallpaper.conversions[item.id] != nil)
                                .help("1080p HEVC kopya üretir (Kütüphane'ye eklenir); ekran koruyucuda 4K yerine bunu seçebilirsiniz.")
                        }
                    }
                }
            }
        }
    }

    private func pickedBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { saver.settings.pickedIDs.contains(id) },
                set: { on in
                    if on { if !saver.settings.pickedIDs.contains(id) { saver.settings.pickedIDs.append(id) } }
                    else { saver.settings.pickedIDs.removeAll { $0 == id } }
                })
    }

    @ViewBuilder private var summary: some View {
        let count = saver.selection.count
        if count == 0 {
            Label("Seçili video yok", systemImage: "film").font(.caption).foregroundStyle(.secondary)
        } else if let plan = saver.plan {
            let total = plan.totalBytes.formatted(.byteCount(style: .file))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) video · \(total)").font(.caption.weight(.medium))
                if plan.bytesToWrite == 0 {
                    Text(plan.needsCopy ? "Aynı disk biriminde: klonlanır, ek disk alanı gerekmez." : "Videolar zaten hazır.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("\(plan.bytesToWrite.formatted(.byteCount(style: .file))) gerçekten kopyalanacak (boş alan \(plan.freeBytes.formatted(.byteCount(style: .file)))).",
                          systemImage: plan.fits ? "externaldrive.badge.plus" : "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(plan.fits ? Color.secondary : Color.orange)
                }
                if saver.contentIsStale && saver.isInstalled {
                    Label("Seçim değişti; \"Videoları güncelle\" ile uygulayın.", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private var actions: some View {
        HStack {
            Button(saver.isInstalled ? "Ekran koruyucuyu güncelle" : "Ekran koruyucuyu kur", systemImage: "square.and.arrow.down") {
                if let plan = saver.plan, plan.bytesToWrite > 0 { confirmInstall = true } else { saver.install(wallpaper: wallpaper) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(saver.isBusy || saver.selection.isEmpty || saver.status == .unavailable)
            if saver.isInstalled && saver.contentIsStale {
                Button("Videoları güncelle", systemImage: "arrow.triangle.2.circlepath") { saver.updateContent(wallpaper: wallpaper) }
                    .disabled(saver.isBusy)
            }
            Button("Kaldır", systemImage: "trash") { saver.uninstall(wallpaper: wallpaper) }
                .disabled(saver.isBusy || !saver.isInstalled)
            Button("Ayarları aç", systemImage: "gearshape") { saver.openSystemSettings() }
            if saver.storedBytes > 0 {
                Button("Kopyaları sil (\(saver.storedBytes.formatted(.byteCount(style: .file))))", systemImage: "externaldrive.badge.minus") { confirmClear = true }
                    .disabled(saver.isBusy)
            }
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kurduktan sonra Sistem Ayarları > Duvar Kâğıdı > Ekran Koruyucu bölümünde \"Adalmon Video\"yu seçin. Ekran koruyucu yalnızca Mac boştayken çalışır; pil kuralı uygulanmaz ama 4K çözme enerji kullanır, pilde 1080p \"Pil dostu kopya\" önerilir.")
            Text("Ekran koruyucu güncellemesinden sonra eski sürüm açılırsa Terminal'de `killall legacyScreenSaver` çalıştırın ya da oturumu kapatıp açın.")
            Toggle("Bitince ekran koruyucu sürecini kapat (önerilen)", isOn: $saver.settings.hostExitOnStop)
                .toggleStyle(.checkbox)
            Text("macOS 26/27'de ekran koruyucu süreci kapanmayıp bellek ve CPU yiyebiliyor; bu seçenek bitişte süreci sonlandırır. Sorun yaşarsanız kapatın.")
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}
