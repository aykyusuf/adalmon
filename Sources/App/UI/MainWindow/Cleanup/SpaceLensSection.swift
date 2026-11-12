import AppKit
import SwiftUI

/// Yer kaplayanlar sihirbazı: karşılama (kök seç) → tarama → harita → bitti.
/// Haritada tıklamak klasörün içine girer. Temizlik için karo seçilir: üstüne gelince çıkan onay kutusu, ⌘-tık ya da sağ tık
/// "Temizlik listesine ekle"; alttaki sabit çubuktan "Temizle". Silme yalnızca `SpaceLensModel.deleteMarked` (CleanupDeleter,
/// tarama köküne bağlı kapsam) ve `DeleteConfirmation` ile yapılır; varsayılan Çöp, kalıcı silmede 2 onay.
struct SpaceLensSection: View {
    @State private var vm = SpaceLensModel()
    @State private var selectedID: String?
    @State private var message: String?
    @State private var helpReason: AccessReason?
    @State private var deleteMode: DeleteMode = .trash
    @State private var confirmSummary: DeleteSummary?
    @State private var showDone = false

    private let accent = CleanupAccent.spaceLens

    init() {}

    /// Önizleme / test için hazır model ve başlangıç ekranı.
    init(model: SpaceLensModel, startDone: Bool = false) {
        _vm = State(initialValue: model)
        _showDone = State(initialValue: startDone)
    }

    private var step: CleanupWizardStep {
        if vm.current == nil { return vm.phase == .scanning ? .scanning : .welcome }
        return showDone ? .done : .result
    }

    var body: some View {
        CleanupWizard(step: step) {
            welcome
        } scanning: {
            scanning
        } result: {
            explorer
        } done: {
            done
        }
        .onAppear {
            vm.access.resume()
            vm.setVisible(true)
        }
        .onDisappear {
            vm.setVisible(false)
            vm.cancel()
            vm.access.stop()
        }
        .onChange(of: vm.phase) { old, new in
            guard old == .deleting, new == .idle else { return }
            if (vm.lastFreed?.count ?? 0) > 0 { showDone = true }
            if let result = vm.lastResult?.first(where: { !$0.isRemoved }), let reason = result.reasonText {
                let failed = vm.lastResult?.filter { !$0.isRemoved }.count ?? 0
                message = "\(failed) öğe silinemedi: \(reason)."
            }
        }
        .sheet(item: $helpReason) { reason in
            AccessHelpSheet(reason: reason, monitor: vm.access) { helpReason = nil }
        }
        .sheet(isPresented: Binding(get: { confirmSummary != nil }, set: { if !$0 { confirmSummary = nil } })) {
            if let summary = confirmSummary {
                DeleteConfirmation(summary: summary, onConfirm: { mode in
                    confirmSummary = nil
                    deleteMode = .trash
                    selectedID = nil
                    vm.deleteMarked(mode: mode)
                }, onCancel: {
                    confirmSummary = nil
                    deleteMode = .trash
                })
            }
        }
    }

    // MARK: 1. Karşılama

    private var welcome: some View {
        CleanupHero3D(
            symbol: "chart.pie.fill", accent: accent, badgeSymbol: "magnifyingglass", title: "Yer kaplayanlar",
            subtitle: "Diskinizi neyin doldurduğunu harita olarak görün. İsterseniz klasörleri seçip buradan temizleyin.",
            primaryTitle: "Ev klasörünü tara", primarySymbol: "house"
        ) {
            startScan(vm.home)
        } accessory: {
            Button("Başka klasör seç…", systemImage: "folder") { choose() }.buttonStyle(.borderless)
        }
    }

    // MARK: 2. Tarama

    private var scanning: some View {
        CleanupScanProgress(accent: accent, symbol: "chart.pie", fraction: vm.progressFraction, title: "Taranıyor…",
                            detail: vm.progressText) { vm.cancel() }
    }

    // MARK: 3. Harita

    private var explorer: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    topRow
                    breadcrumb
                    if !vm.access.blocked.isEmpty { FilesAccessBanner(access: vm.access, home: vm.home) }
                    if let message { Text(message).font(.caption).foregroundStyle(.orange) }
                    content
                }
                .padding(.bottom, 8)
            }
            if !vm.selection.isEmpty || vm.phase == .deleting {
                actionBar.padding(.top, 8).padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.1), value: vm.selection.isEmpty)
    }

    private var topRow: some View {
        HStack(spacing: 10) {
            if vm.phase == .scanning {
                if let fraction = vm.progressFraction { ProgressView(value: fraction).frame(width: 90) } else { ProgressView().controlSize(.small) }
                Text(vm.progressText).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Button("Durdur") { vm.cancel() }
            } else {
                Button("Yeniden tara", systemImage: "arrow.clockwise") { vm.rescan() }.disabled(vm.isBusy)
                Button("Başka klasör", systemImage: "folder") { newScan() }.disabled(vm.isBusy)
            }
            Spacer(minLength: 8)
            Text("Toplam: \(Format.bytes(vm.totalBytes))").font(.headline).monospacedDigit()
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Button { vm.back() } label: { Image(systemName: "chevron.left") }
                .disabled(!vm.canGoBack || vm.isBusy).help("Geri")
            ForEach(Array(vm.trail.enumerated()), id: \.offset) { index, path in
                if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                Button(index == 0 ? FolderWatchList.displayPath(path, home: vm.home) : (path as NSString).lastPathComponent) { vm.go(to: index) }
                    .buttonStyle(.borderless)
                    .fontWeight(index == vm.trail.count - 1 ? .semibold : .regular)
                    .disabled(vm.isBusy)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var content: some View {
        if vm.nodes.isEmpty {
            ResourceEmptyNote(text: vm.lastState == .noAccess ? "Bu klasöre erişim yok." : "Bu klasör boş.")
        } else {
            TreemapCanvas(nodes: vm.nodes, otherBytes: vm.otherBytes, selectedID: selectedID, contextPath: vm.current ?? "",
                          markedIDs: Set(vm.selection.marks.keys), canMark: { vm.canMark($0) && !vm.isCovered($0.path) },
                          onToggleMark: { toggle($0) }) { node in
                selectedID = node.id
                message = nil
                if node.isFolder, !vm.isBusy { vm.open(node.path) }
            }
            .frame(height: 340)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                // Önbellekte olmayan (tembel) seviye açılırken yerinde küçük bir gösterge.
                if vm.phase == .scanning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Taranıyor…").font(.caption)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.regularMaterial, in: .capsule)
                    .padding(8)
                }
            }
            TreemapLegend(nodes: vm.nodes)
            Text("Tıklayınca klasöre girilir. Temizlemek için karonun köşesindeki kutuyu işaretleyin, ⌘-tıklayın ya da sağ tıklayın.")
                .font(.caption).foregroundStyle(.secondary)
            nodeList
        }
    }

    private var nodeList: some View {
        ResourceCard(title: "İçindekiler", systemImage: "list.bullet") {
            LazyVStack(spacing: 2) {
                ForEach(vm.nodes.prefix(100)) { node in row(node) }
            }
            if vm.nodes.count > 100 { Text("En büyük 100 öğe listeleniyor.").font(.caption).foregroundStyle(.secondary) }
            if vm.otherCount > 0 {
                Text("Küçük \(vm.otherCount) öğe (\(Format.bytes(vm.otherBytes))) tek tek gösterilmiyor.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ node: SpaceNode) -> some View {
        let total = max(1, vm.totalBytes)
        let covered = vm.isCovered(node.path)
        let refusal = vm.markRefusal(for: node)
        let marked = vm.isMarked(node.path) || covered
        return HStack(spacing: 8) {
            if node.isMeasured {
                Toggle(node.name, isOn: Binding(get: { marked }, set: { _ in toggle(node) }))
                    .toggleStyle(.checkbox).labelsHidden()
                    .disabled(refusal != nil || covered || vm.isBusy)
                    .help(refusal ?? (covered ? "Üst klasör zaten seçili" : "Temizlik listesine ekle"))
            } else {
                Color.clear.frame(width: 16, height: 1)
            }
            Image(systemName: icon(node)).foregroundStyle(node.isMeasured ? Color.secondary : Color.orange).frame(width: 18).accessibilityHidden(true)
            Text(node.name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            switch node.kind {
            case .locked(let reason):
                Button("Erişim gerekli") { helpReason = reason }.buttonStyle(.borderless).foregroundStyle(.orange)
            case .skipped(let reason):
                if let reason, reason != .systemProtected {
                    Button("Taranmadı") { helpReason = reason }.buttonStyle(.borderless).foregroundStyle(.secondary)
                } else {
                    Text("Taranmadı").foregroundStyle(.secondary)
                }
            default:
                if refusal != nil, node.isMeasured {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.tertiary).help(refusal ?? "")
                }
                Text(String(format: "%.1f%%", Double(node.bytes) / Double(total) * 100)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Text(Format.bytes(node.bytes)).monospacedDigit().frame(width: 80, alignment: .trailing)
            }
            if node.isMeasured {
                if node.isFolder {
                    Button { vm.open(node.path) } label: { Image(systemName: "arrow.right.circle") }
                        .buttonStyle(.borderless).help("İçine gir").disabled(vm.isBusy)
                    Button { addToLargeOld(node) } label: { Image(systemName: "doc.badge.plus") }
                        .buttonStyle(.borderless).help("Büyük & eski'ye ekle")
                }
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)]) } label: {
                    Image(systemName: "magnifyingglass.circle")
                }
                .buttonStyle(.borderless).help("Finder'da göster")
            }
        }
        .font(.callout)
        .padding(.vertical, 2)
        .background(marked ? accent.base.opacity(0.14) : (node.id == selectedID ? Color.accentColor.opacity(0.12) : .clear),
                    in: .rect(cornerRadius: 6))
    }

    private func icon(_ node: SpaceNode) -> String {
        switch node.kind {
        case .folder: "folder"
        case .file: "doc"
        case .locked: "lock"
        case .skipped: "eye.slash"
        }
    }

    // MARK: Temizlik çubuğu

    private var actionBar: some View {
        CleanupActionBar(
            countText: "\(vm.selection.count) öğe seçili", bytes: vm.markedBytes, mode: $deleteMode,
            isEnabled: !vm.selection.isEmpty, isBusy: vm.phase == .deleting, accent: accent
        ) {
            let items = vm.selection.items
            confirmSummary = DeleteSummary(
                count: items.count, bytes: vm.markedBytes, mode: deleteMode,
                sample: items.prefix(5).map { FolderWatchList.displayPath($0.path, home: vm.home) }
            )
        } leading: {
            Button { vm.clearSelection() } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless).disabled(vm.isBusy).help("Seçimi temizle")
        }
    }

    // MARK: 4. Bitti

    private var done: some View {
        let freed = vm.lastFreed ?? (count: 0, bytes: 0, skipped: 0)
        let trashed = vm.lastMode == .trash
        var detail = "\(freed.count) öğe \(trashed ? "taşındı" : "kalıcı olarak silindi")"
        detail += freed.skipped > 0 ? ", \(freed.skipped) atlandı." : "."
        detail += " Harita güncellendi; yeniden taramak gerekmez."
        if trashed { detail += " Disk alanı, Çöp Sepeti'ni boşaltınca açılır." }
        return CleanupDoneView(
            accent: accent, bytes: freed.bytes, headline: trashed ? "Çöp Sepeti'ne taşındı" : "boşaltıldı", detail: detail,
            primaryTitle: "Haritaya dön", primarySymbol: "chart.pie", secondaryTitle: "Yeniden tara",
            onSecondary: { showDone = false; vm.rescan() }
        ) { showDone = false }
    }

    // MARK: Eylemler

    private func toggle(_ node: SpaceNode) {
        if case .blocked(let reason) = vm.toggleMark(node) { message = reason } else { message = nil }
    }

    private func startScan(_ path: String) {
        selectedID = nil
        message = nil
        showDone = false
        vm.start(root: path)
    }

    /// Karşılama ekranına dön (başka klasör seçmek için).
    private func newScan() {
        vm.reset()
        selectedID = nil
        message = nil
        showDone = false
    }

    private func addToLargeOld(_ node: SpaceNode) {
        let result = FileRootsStore.shared.add(node.path)
        message = result == .added ? "\(node.name) Büyük & eski klasörlerine eklendi." : (result.message ?? "")
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Tara"
        panel.directoryURL = URL(fileURLWithPath: vm.home)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in startScan(url.path) }
        }
    }
}
