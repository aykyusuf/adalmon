import AppKit
import SwiftUI

/// Büyük & eski dosyalar sihirbazı: karşılama (klasörler) → tarama → sonuç → bitti.
/// Sonuç ekranında üstte küçük bir filtre çubuğu (boyut eşiği, "yalnızca eski") bulunur. Tarama yalnızca "Tara"ya basınca olur;
/// iCloud'da duran dosyalar indirilmez. Silme yalnızca `LargeOldModel.deleteSelected` (CleanupDeleter) ve `DeleteConfirmation` ile yapılır.
struct LargeOldSection: View {
    @State private var vm = LargeOldModel()
    @State private var confirmSummary: DeleteSummary?
    @State private var confirmItems: [LargeOldItem] = []
    @State private var showDone = false

    private let accent = CleanupAccent.largeOld
    private let listLimit = 500

    init() {}

    /// Önizleme / test için hazır model ve başlangıç ekranı.
    init(model: LargeOldModel, startDone: Bool = false) {
        _vm = State(initialValue: model)
        _showDone = State(initialValue: startDone)
    }

    private var step: CleanupWizardStep {
        if !vm.hasScanned { return vm.phase == .scanning ? .scanning : .welcome }
        return showDone ? .done : .result
    }

    var body: some View {
        CleanupWizard(step: step) {
            welcome
        } scanning: {
            scanning
        } result: {
            result
        } done: {
            done
        }
        .onAppear { vm.access.resume() }
        .onChange(of: vm.minBytes) { if vm.hasScanned { vm.scan() } }
        .onChange(of: vm.phase) { old, new in
            if new == .scanning { showDone = false }
            if old == .deleting, new == .idle, (vm.lastResult ?? []).contains(where: \.isRemoved) { showDone = true }
        }
        .onDisappear {
            vm.cancel()
            vm.access.stop()
            vm.deleteMode = .trash
        }
        .sheet(isPresented: Binding(get: { confirmSummary != nil }, set: { if !$0 { confirmSummary = nil } })) {
            if let summary = confirmSummary {
                DeleteConfirmation(summary: summary, onConfirm: { mode in
                    let chosen = confirmItems
                    confirmSummary = nil
                    confirmItems = []
                    vm.deleteSelected(mode: mode, items: chosen)
                }, onCancel: {
                    confirmSummary = nil
                    confirmItems = []
                    vm.deleteMode = .trash
                })
            }
        }
    }

    // MARK: 1. Karşılama

    private var welcome: some View {
        CleanupHero3D(
            symbol: "doc.badge.clock.fill", accent: accent, badgeSymbol: "magnifyingglass", title: "Büyük & eski",
            subtitle: "Seçtiğiniz klasörlerdeki büyük ve uzun süredir dokunulmamış dosyaları listeler. Siz seçmeden hiçbir şey silinmez.",
            primaryTitle: "Tara", primarySymbol: "magnifyingglass"
        ) {
            vm.scan()
        } accessory: {
            VStack(spacing: 8) {
                Text("Taranacak klasörler").font(.caption).foregroundStyle(.secondary)
                FilesRootsBar(store: vm.rootsStore, disabled: vm.isBusy, centered: true)
            }
            .frame(maxWidth: 520)
            .padding(.top, 6)
        }
    }

    // MARK: 2. Tarama

    private var scanning: some View {
        CleanupScanProgress(accent: accent, symbol: "doc.badge.clock", title: "Dosyalar taranıyor…",
                            detail: vm.progressText) { vm.cancel() }
    }

    // MARK: 3. Sonuç

    private var result: some View {
        let items = vm.visibleItems
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if items.isEmpty {
                        CleanupAllCleanView(
                            accent: accent,
                            title: vm.items.isEmpty ? "Büyük dosya yok" : "Bu süzgece uyan dosya yok",
                            subtitle: vm.items.isEmpty ? "Eşiğin üstünde dosya bulunamadı. Eşiği düşürmeyi deneyin." : "Süzgeci gevşetince daha fazla dosya görünür.",
                            compact: true
                        )
                        filterBar
                    } else {
                        CleanupResultHeader(bytes: vm.visibleBytes, caption: "\(items.count) dosya", accent: accent,
                                            notes: vm.onlyOld ? ["Eski = son değiştirilme tarihi."] : [])
                        filterBar
                    }
                    if !vm.access.blocked.isEmpty { FilesAccessBanner(access: vm.access, home: vm.home) }
                    if let results = vm.lastResult { FilesResultBanner(results: results, mode: vm.lastMode, home: vm.home) }
                    LazyVStack(spacing: 8) {
                        ForEach(items.prefix(listLimit)) { item in card(item) }
                    }
                    if items.count > listLimit {
                        Text("En büyük \(listLimit) dosya gösteriliyor.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                    if vm.unreadableDirs > 0 {
                        Text("\(vm.unreadableDirs) klasör okunamadı.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 10)
            }
            if !items.isEmpty { actionBar.padding(.top, 8).padding(.bottom, 4) }
        }
    }

    /// Sade filtre çubuğu: boyut eşiği, "yalnızca eski", seçim kısayolları, klasörler, yeniden tara.
    private var filterBar: some View {
        FilesFlowLayout(spacing: 8, centered: true) {
            FilesPillMenu(title: "≥ \(Format.bytes(vm.minBytes))", systemImage: "scalemass", isActive: true, disabled: vm.isBusy) {
                Picker("En az", selection: $vm.minBytes) {
                    ForEach(LargeOldModel.sizeChoices, id: \.self) { Text("≥ \(Format.bytes($0))").tag($0) }
                }
                .pickerStyle(.inline)
            }
            .help("Boyut eşiği; değişince yeniden taranır")
            Button { vm.onlyOld.toggle() } label: {
                FilesPillLabel(title: "Yalnızca eski", systemImage: vm.onlyOld ? "checkmark.circle.fill" : "circle",
                               showsChevron: false, isActive: vm.onlyOld)
            }
            .buttonStyle(.plain)
            if vm.onlyOld {
                FilesPillMenu(title: "≥ \(FilesText.ageLabel(vm.oldDays))", systemImage: "clock", isActive: true) {
                    Picker("Eski sayılır", selection: $vm.oldDays) {
                        ForEach(LargeOldModel.ageChoices, id: \.self) { Text("≥ \(FilesText.ageLabel($0))").tag($0) }
                    }
                    .pickerStyle(.inline)
                }
            }
            FilesPillMenu(title: "Seç", systemImage: "checkmark.square", disabled: vm.isBusy) {
                Button("Hepsini seç") { vm.selectAllVisible(true) }
                Button("Seçimi kaldır") { vm.selectAllVisible(false) }
            }
            FilesRootsPopoverButton(store: vm.rootsStore, disabled: vm.isBusy)
            if vm.phase == .scanning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Taranıyor…").font(.callout).foregroundStyle(.secondary)
                    Button("Durdur") { vm.cancel() }.controlSize(.small)
                }
            } else {
                Button { vm.scan() } label: { FilesPillLabel(title: "Yeniden tara", systemImage: "arrow.clockwise", showsChevron: false) }
                    .buttonStyle(.plain)
                    .disabled(vm.isBusy || vm.rootsStore.roots.isEmpty)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func card(_ item: LargeOldItem) -> some View {
        let folder = FolderWatchList.displayPath((item.path as NSString).deletingLastPathComponent, home: vm.home)
        return CleanupResultCard(
            symbol: FilesText.symbol(forPath: item.path), title: item.name,
            subtitle: "\(folder) · \(FilesText.ageText(item.modified))",
            sizeText: Format.bytes(item.bytes), accent: accent,
            selection: vm.selection.contains(item.id) ? .all : .none,
            isEnabled: !vm.isBusy, onToggle: { vm.toggle(item) }
        ) {
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) } label: {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.borderless).help("Finder'da göster")
        }
    }

    private var actionBar: some View {
        let selected = vm.selectedItems
        let bytes = selected.reduce(UInt64(0)) { $0 + $1.bytes }
        return CleanupActionBar(
            countText: "\(selected.count) dosya seçili", bytes: bytes, mode: $vm.deleteMode,
            isEnabled: !selected.isEmpty, isBusy: vm.phase == .deleting, accent: accent
        ) {
            confirmItems = selected
            confirmSummary = DeleteSummary(
                count: selected.count, bytes: bytes, mode: vm.deleteMode,
                sample: selected.prefix(5).map { FolderWatchList.displayPath($0.path, home: vm.home) }
            )
        }
    }

    // MARK: 4. Bitti

    private var done: some View {
        let results = vm.lastResult ?? []
        let removed = results.filter(\.isRemoved)
        let bytes = removed.reduce(UInt64(0)) { $0 + $1.candidate.bytes }
        let skipped = results.count - removed.count
        let trashed = vm.lastMode == .trash
        var detail = "\(removed.count) dosya \(trashed ? "taşındı" : "kalıcı olarak silindi")"
        detail += skipped > 0 ? ", \(skipped) atlandı." : "."
        if trashed { detail += " Disk alanı, Çöp Sepeti'ni boşaltınca açılır." }
        return CleanupDoneView(
            accent: accent, bytes: bytes, headline: trashed ? "Çöp Sepeti'ne taşındı" : "boşaltıldı", detail: detail,
            primaryTitle: "Listeye dön", primarySymbol: "list.bullet", secondaryTitle: "Yeniden tara",
            onSecondary: { showDone = false; vm.scan() }
        ) { showDone = false }
    }
}
