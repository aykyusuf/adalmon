import AppKit
import SwiftUI

/// Kopyalar sihirbazı: karşılama (klasörler) → tarama → sonuç (grup kartları) → bitti.
/// Her grupta bir dosya korunur (değiştirilebilir, rozetli); grubun hepsi asla seçilemez. Tarama yalnızca "Kopyaları bul"a basınca olur.
/// Silme yalnızca `DuplicatesModel.deleteSelected` (CleanupDeleter) ve `DeleteConfirmation` ile yapılır.
struct DuplicatesSection: View {
    @State private var vm = DuplicatesModel()
    @State private var confirmSummary: DeleteSummary?
    @State private var confirmFiles: [DuplicateFile] = []
    @State private var expanded: Set<String> = []
    @State private var showDone = false

    private let accent = CleanupAccent.duplicates
    private let groupLimit = 200
    private static let sizeChoices: [UInt64] = [1 << 20, 10 << 20, 100 << 20]

    init() {}

    /// Önizleme / test için hazır model ve başlangıç ekranı.
    init(model: DuplicatesModel, startDone: Bool = false, expanded: Set<String> = []) {
        _vm = State(initialValue: model)
        _showDone = State(initialValue: startDone)
        _expanded = State(initialValue: expanded)
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
                    let chosen = confirmFiles
                    confirmSummary = nil
                    confirmFiles = []
                    vm.deleteSelected(mode: mode, files: chosen)
                }, onCancel: {
                    confirmSummary = nil
                    confirmFiles = []
                    vm.deleteMode = .trash
                })
            }
        }
    }

    // MARK: 1. Karşılama

    private var welcome: some View {
        CleanupHero3D(
            symbol: "doc.on.doc.fill", accent: accent, badgeSymbol: "magnifyingglass", title: "Kopyalar",
            subtitle: "Aynı içerikli dosyaları bulur. Her gruptan bir dosya her zaman korunur; siz seçmeden hiçbir şey silinmez.",
            primaryTitle: "Kopyaları bul", primarySymbol: "magnifyingglass"
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
        CleanupScanProgress(accent: accent, symbol: "doc.on.doc", fraction: vm.progressFraction, title: "Kopyalar aranıyor…",
                            detail: vm.progressText) { vm.cancel() }
    }

    // MARK: 3. Sonuç

    private var result: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if vm.groups.isEmpty {
                        CleanupAllCleanView(accent: accent, title: "Kopya yok", subtitle: "Aynı içerikli dosya bulunamadı.", compact: true)
                        filterBar
                    } else {
                        CleanupResultHeader(
                            bytes: vm.reclaimableBytes, caption: "\(vm.groups.count) grupta açılabilir", accent: accent,
                            notes: ["Aynı içerik tam SHA-256 özetiyle eşlenir. APFS klonlarını silmek gösterilen yerin çoğunu (yaklaşık 0 bayt) açmayabilir."]
                        )
                        filterBar
                    }
                    if !vm.access.blocked.isEmpty { FilesAccessBanner(access: vm.access, home: vm.home) }
                    if let results = vm.lastResult { FilesResultBanner(results: results, mode: vm.lastMode, home: vm.home) }
                    LazyVStack(spacing: 8) {
                        ForEach(vm.groups.prefix(groupLimit)) { group in groupCard(group) }
                    }
                    if vm.groups.count > groupLimit {
                        Text("En büyük \(groupLimit) grup gösteriliyor.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                    if vm.unreadableDirs > 0 {
                        Text("\(vm.unreadableDirs) klasör okunamadı.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 10)
            }
            if !vm.groups.isEmpty { actionBar.padding(.top, 8).padding(.bottom, 4) }
        }
    }

    /// Sade filtre çubuğu: boyut eşiği, seçim kısayolları, klasörler, yeniden tara.
    private var filterBar: some View {
        FilesFlowLayout(spacing: 8, centered: true) {
            FilesPillMenu(title: "≥ \(Format.bytes(vm.minBytes))", systemImage: "scalemass", isActive: true, disabled: vm.isBusy) {
                Picker("En küçük", selection: $vm.minBytes) {
                    ForEach(Self.sizeChoices, id: \.self) { Text("≥ \(Format.bytes($0))").tag($0) }
                }
                .pickerStyle(.inline)
            }
            .help("Boyut eşiği; değişince yeniden taranır")
            if !vm.groups.isEmpty {
                FilesPillMenu(title: "Seç", systemImage: "checkmark.square", disabled: vm.isBusy) {
                    Button("Her gruptan fazlalıkları seç") { vm.selectAllButKeepers() }
                    Button("Seçimi kaldır") { vm.clearSelection() }
                }
            }
            FilesRootsPopoverButton(store: vm.rootsStore, disabled: vm.isBusy)
            if vm.phase == .scanning {
                HStack(spacing: 6) {
                    if let fraction = vm.progressFraction {
                        ProgressView(value: fraction).frame(width: 60)
                    } else {
                        ProgressView().controlSize(.small)
                    }
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

    private func groupCard(_ group: DuplicateGroup) -> some View {
        let keeperPath = vm.selection.keeper(of: group)
        let others = group.files.filter { $0.path != keeperPath }
        let selectedCount = others.filter { vm.selection.isSelected($0.path) }.count
        return CleanupResultCard(
            symbol: FilesText.symbol(forPath: group.files[0].path), title: group.files[0].name,
            subtitle: "\(group.files.count) kopya · her biri \(Format.bytes(group.size))",
            sizeText: Format.bytes(others.reduce(UInt64(0)) { $0 + $1.allocated }), accent: accent,
            selection: CleanupSelectionState(selected: selectedCount, total: others.count),
            isEnabled: !vm.isBusy, onToggle: { toggleGroup(group, others: others, selectedCount: selectedCount) },
            isExpanded: Binding(get: { expanded.contains(group.id) },
                                set: { if $0 { expanded.insert(group.id) } else { expanded.remove(group.id) } })
        ) {
            keeperBadge
        } detail: {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.files) { file in fileRow(file, in: group, keeperPath: keeperPath) }
            }
        }
    }

    /// Kartın onay kutusu: fazlalıkların hepsi seçili değilse hepsini seçer, aksi halde hepsini kaldırır. Korunan dosya asla seçilmez.
    private func toggleGroup(_ group: DuplicateGroup, others: [DuplicateFile], selectedCount: Int) {
        let selectAll = selectedCount < others.count
        for file in others where vm.selection.isSelected(file.path) != selectAll { vm.toggle(file, in: group) }
    }

    private var keeperBadge: some View {
        Label("Biri korunur", systemImage: "checkmark.shield.fill")
            .font(.caption2.weight(.medium)).foregroundStyle(.green)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color.green.opacity(0.14), in: .capsule)
    }

    private func fileRow(_ file: DuplicateFile, in group: DuplicateGroup, keeperPath: String) -> some View {
        let isKeeper = file.path == keeperPath
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { vm.selection.isSelected(file.path) }, set: { _ in vm.toggle(file, in: group) }))
                .toggleStyle(.checkbox).labelsHidden().disabled(isKeeper || vm.isBusy)
                .accessibilityLabel(file.path)
            VStack(alignment: .leading, spacing: 1) {
                Text(FolderWatchList.displayPath(file.path, home: vm.home)).lineLimit(1).truncationMode(.middle)
                Text(file.modified.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isKeeper {
                Label("Korunacak", systemImage: "checkmark.shield.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(.green)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.green.opacity(0.14), in: .capsule)
            } else {
                Button("Bunu koru") { vm.setKeeper(file, in: group) }.buttonStyle(.borderless).font(.caption).disabled(vm.isBusy)
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)]) } label: {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.borderless).help("Finder'da göster")
        }
        .font(.callout)
    }

    private var actionBar: some View {
        let selected = vm.selectedFiles
        let bytes = selected.reduce(UInt64(0)) { $0 + $1.allocated }
        return CleanupActionBar(
            countText: "\(selected.count) kopya seçili", bytes: bytes, mode: $vm.deleteMode,
            isEnabled: !selected.isEmpty, isBusy: vm.phase == .deleting, accent: accent
        ) {
            confirmFiles = selected
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
        var detail = "\(removed.count) kopya \(trashed ? "taşındı" : "kalıcı olarak silindi")"
        detail += skipped > 0 ? ", \(skipped) atlandı." : "."
        if trashed { detail += " Disk alanı, Çöp Sepeti'ni boşaltınca açılır." }
        return CleanupDoneView(
            accent: accent, bytes: bytes, headline: trashed ? "Çöp Sepeti'ne taşındı" : "boşaltıldı", detail: detail,
            primaryTitle: "Listeye dön", primarySymbol: "list.bullet", secondaryTitle: "Yeniden tara",
            onSecondary: { showDone = false; vm.scan() }
        ) { showDone = false }
    }
}
