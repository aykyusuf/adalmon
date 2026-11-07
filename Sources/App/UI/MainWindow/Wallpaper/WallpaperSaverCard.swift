import AppKit
import SwiftUI

/// Ekran koruyucu ve kilit ekranı: tek kart. Kullanıcı yalnızca "aynı mı, farklı mı" seçer; videoların hazırlanması, güncellenmesi
/// ve paketin yenilenmesi kendiliğinden olur. Nadir kullanılan şeyler "Gelişmiş" altındadır.
struct WallpaperSaverCard: View {
    @Bindable var wallpaper: WallpaperService
    @Bindable var saver: SaverService
    @State private var showAdvanced: Bool
    @State private var confirmInstall = false

    init(wallpaper: WallpaperService, saver: SaverService, startExpanded: Bool = false) {
        self.wallpaper = wallpaper
        self.saver = saver
        _showAdvanced = State(initialValue: startExpanded)
    }

    /// Bu değerlerden biri değişince videolar/oynatma listesi ~2 sn sonra (art arda değişiklikler tek işe inerek) eşitlenir.
    private struct SyncKey: Hashable {
        var settings: SaverSettings
        var itemIDs: [UUID]
        var defaultID: UUID?
        var mode: PlaylistMode
        var loop: LoopSettings
    }

    private var syncKey: SyncKey {
        SyncKey(settings: saver.settings, itemIDs: wallpaper.items.map(\.id), defaultID: wallpaper.settings.defaultItemID,
                mode: wallpaper.settings.playlistMode, loop: wallpaper.settings.loop)
    }

    var body: some View {
        RulesCard(title: "Ekran koruyucu ve kilit ekranı", systemImage: "sparkles.tv",
                  subtitle: "Mac boştayken videolarınız oynar. Değişiklikler kendiliğinden uygulanır.") {
            statusSection
            sourcePicker
            if saver.settings.source == .picked {
                WallpaperSaverPicker(wallpaper: wallpaper, saver: saver)
                Toggle("Karışık sırayla oynat", isOn: $saver.settings.shuffle)
            }
            progressSection
            Divider()
            WallpaperLockScreenSection(service: wallpaper)
            Divider()
            WallpaperSaverAdvanced(wallpaper: wallpaper, saver: saver, isExpanded: $showAdvanced)
        }
        .task(id: syncKey) { await saver.refresh(wallpaper: wallpaper) }
        .onChange(of: syncKey, initial: true) { saver.scheduleAutoSync(wallpaper: wallpaper) }
        .onChange(of: saver.settings.source) { _, source in preselectPicked(source) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await saver.refreshSelectedState() }
        }
        .confirmationDialog("Videolar kopyalansın mı?", isPresented: $confirmInstall) {
            Button("Kopyala ve etkinleştir") { saver.activate(wallpaper: wallpaper) }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            if let plan = saver.plan {
                Text("\(plan.bytesToWrite.formatted(.byteCount(style: .file))) kopyalanacak (boş alan \(plan.freeBytes.formatted(.byteCount(style: .file)))).")
            }
        }
    }

    // MARK: Durum

    private var statusSection: some View {
        let line = saver.statusLine
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(line.text, systemImage: line.systemImage)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(color(for: line.tone))
                if line.offersSettings {
                    Button("Ayarları aç") { saver.openSystemSettings() }.buttonStyle(.link)
                }
            }
            if saver.status == .notInstalled {
                Button("Ekran koruyucuyu etkinleştir", systemImage: "play.rectangle", action: activate)
                    .buttonStyle(.borderedProminent)
                    .disabled(saver.isBusy || saver.selection.isEmpty)
                Text(saver.selection.isEmpty ? "Önce kütüphaneye bir video ekleyin." : "Sistem Ayarları açılır; listeden \"Adalmon Video\"yu seçin.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if line.showsPickHint {
                Text("Listeden \"Adalmon Video\"yu seçin.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func color(for tone: SaverStatusLine.Tone) -> Color {
        switch tone {
        case .ok: .green
        case .warning: .orange
        case .error: .red
        case .neutral: .secondary
        }
    }

    // MARK: Kaynak

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Ekran koruyucu", selection: $saver.settings.source) {
                ForEach(SaverSource.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 460)
            Text(sourceCaption).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var sourceCaption: String {
        switch saver.settings.source {
        case .picked:
            "Yalnızca seçtiğiniz videolar oynar."
        case .sameAsWallpaper:
            wallpaper.settings.playlistMode == .single ? "Seçili duvar kâğıdı videosu oynar." : "Duvar kâğıdı çalma listesindeki videolar oynar."
        }
    }

    @ViewBuilder private var progressSection: some View {
        if let progress = saver.progress {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress) { Text("Videolar hazırlanıyor…").font(.caption) }
            }
            .frame(maxWidth: 360)
        }
        if let message = saver.message {
            Label(message, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
        }
    }

    // MARK: Eylemler

    private func activate() {
        if let plan = saver.plan, plan.bytesToWrite > 0 { confirmInstall = true } else { saver.activate(wallpaper: wallpaper) }
    }

    /// "Farklı videolar"a ilk geçişte mevcut seçimle başlar: kullanıcı sıfırdan seçmek zorunda kalmaz.
    private func preselectPicked(_ source: SaverSource) {
        guard source == .picked, saver.settings.pickedIDs.isEmpty else { return }
        let same = SaverSelection.resolve(settings: SaverSettings(), wallpaper: wallpaper.settings, items: wallpaper.items)
        saver.settings.pickedIDs = same.map(\.id)
    }
}
