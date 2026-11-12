import AppKit
import SwiftUI

/// Temizlik kategorisi kartı (sihirbazın sonuç ekranı): üç durumlu onay kutusu, toplam boyut, açılır öğe satırları (en çok 200).
/// Açıkça taranan kategoriler (İndirilenler, iOS yedekleri, proje artıkları) kendi tarama düğmesini taşır.
struct CleanupCategoryCard: View {
    let vm: CleanupViewModel
    let category: CleanupCategory
    let state: CleanupRootState?
    let accent: CleanupAccent
    var onHelp: (AccessReason) -> Void = { _ in }
    @State private var expanded: Bool
    @State private var folderError: String?

    private static let rowCap = 200

    init(vm: CleanupViewModel, category: CleanupCategory, state: CleanupRootState?, accent: CleanupAccent,
         onHelp: @escaping (AccessReason) -> Void = { _ in }) {
        self.vm = vm
        self.category = category
        self.state = state
        self.accent = accent
        self.onHelp = onHelp
        _expanded = State(initialValue: category == .projectArtifacts && vm.projectFolders.isEmpty)
    }

    var body: some View {
        let items = vm.items(in: category)
        let selectable = items.filter { $0.blockedReason == nil }
        let selectedCount = selectable.filter { vm.selection.contains($0.id) }.count
        let total = items.reduce(UInt64(0)) { $0 + $1.bytes }
        CleanupResultCard(
            symbol: category.systemImage, title: category.title,
            subtitle: subtitle(items: items, selectedCount: selectedCount),
            sizeText: items.isEmpty ? nil : Format.bytes(total), accent: accent,
            selection: CleanupSelectionState(selected: selectedCount, total: selectable.count),
            isEnabled: !selectable.isEmpty && !vm.isBusy,
            onToggle: items.isEmpty ? nil : { vm.setCategory(category, selected: selectedCount < selectable.count) },
            isExpanded: $expanded,
            accessory: { accessory(items: items) },
            detail: { details(items: items) }
        )
    }

    private var scanningThis: Bool { vm.phase == .scanning(category) }

    private var shortNote: String? {
        switch category {
        case .iosBackups: "Yedeği silmek geri yükleme noktasını kaldırır. Otomatik seçilmez."
        case .projectArtifacts: "Silinirse yeniden derlemede oluşur. Otomatik seçilmez."
        default: category.defaultSelected ? nil : "Otomatik seçilmez."
        }
    }

    private func subtitle(items: [CleanupItem], selectedCount: Int) -> String {
        if state == .noAccess { return (vm.accessReason(for: category) ?? .fullDiskAccess).title }
        if items.isEmpty {
            if !vm.scannedCategories.contains(category) {
                if category == .projectArtifacts && vm.projectFolders.isEmpty { return "Henüz proje klasörü yok. Önce klasör ekleyin." }
                return "Yalnızca isteyince taranır. \(shortNote ?? "")"
            }
            if state == .missing, category != .projectArtifacts { return "Bulunamadı." }
            return "Listelenecek öğe yok."
        }
        if category == .browserCaches, items.contains(where: { $0.blockedReason != nil }) {
            return "\(items.count) öğe. Tarayıcı açık: önce kapatıp yeniden tarayın."
        }
        return ["\(items.count) öğe, \(selectedCount) seçili.", shortNote].compactMap { $0 }.joined(separator: " ")
    }

    @ViewBuilder
    private func accessory(items: [CleanupItem]) -> some View {
        if scanningThis {
            ProgressView().controlSize(.small)
        } else if state == .noAccess {
            let reason = vm.accessReason(for: category) ?? .fullDiskAccess
            HStack(spacing: 6) {
                if let button = reason.buttonTitle {
                    Button(button) { vm.access.openSettings(for: reason) }.controlSize(.small)
                }
                Button("Nasıl?") { onHelp(reason) }.buttonStyle(.borderless)
            }
        } else if category.needsExplicitScan {
            if category == .projectArtifacts && vm.projectFolders.isEmpty {
                Button("Klasör ekle…", systemImage: "plus") { chooseFolders() }.controlSize(.small).disabled(vm.isBusy)
            } else if vm.scannedCategories.contains(category) {
                Button { vm.scan([category]) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(vm.isBusy)
                    .help(category.scanButtonTitle).accessibilityLabel(category.scanButtonTitle)
            } else {
                Button(category.scanButtonTitle, systemImage: "magnifyingglass") { vm.scan([category]) }
                    .controlSize(.small).disabled(vm.isBusy)
            }
        } else if category == .browserCaches, items.contains(where: { $0.blockedReason != nil }) {
            Label("Tarayıcıyı kapatın", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func details(items: [CleanupItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let note = category.note {
                Text(note).font(.caption).foregroundStyle(category == .iosBackups ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if category == .browserCaches, items.contains(where: { $0.blockedReason != nil }) {
                Label("Önce tarayıcıyı kapatın", systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
            if category == .projectArtifacts { projectFolderEditor }
            ForEach(items.prefix(Self.rowCap)) { item in row(item) }
            if items.count > Self.rowCap {
                Text("+\(items.count - Self.rowCap) daha").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Proje klasörleri listesi: ekle (NSOpenPanel) ve çıkar. Seçim yalnızca bu uygulamanın küçük listesine yazılır.
    private var projectFolderEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(vm.projectFolders, id: \.self) { folder in
                HStack(spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(FolderWatchList.displayPath(folder, home: vm.home)).lineLimit(1).truncationMode(.middle)
                    if vm.state(of: .projectArtifacts) != nil, vm.rootStates[folder] == .missing {
                        Text("Bulunamadı").font(.caption2).foregroundStyle(.orange)
                    }
                    Spacer(minLength: 8)
                    Button { vm.removeProjectFolder(folder) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .disabled(vm.isBusy)
                        .help("Listeden çıkar (klasöre dokunulmaz)")
                        .accessibilityLabel("Listeden çıkar: \(folder)")
                }
                .font(.callout)
            }
            HStack(spacing: 8) {
                Button("Klasör ekle…", systemImage: "plus") { chooseFolders() }.controlSize(.small).disabled(vm.isBusy)
                if vm.projectFolders.isEmpty {
                    Text("Henüz proje klasörü yok.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let folderError { Text(folderError).font(.caption).foregroundStyle(.red) }
        }
        .padding(.bottom, 4)
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = false
        panel.prompt = "Ekle"
        panel.message = "Taranacak proje klasörlerini seçin (ev klasörünün kendisi seçilemez)."
        panel.begin { response in
            guard response == .OK else { return }
            folderError = panel.urls.compactMap { vm.addProjectFolder($0.path) }.first
        }
    }

    private func row(_ item: CleanupItem) -> some View {
        let shown = FolderWatchList.displayPath(item.path, home: vm.home)
        var parts: [String] = []
        if let badge = item.blockedReason { parts.append("\(badge): seçilemez, silinmez") }
        if category == .downloads || category == .projectArtifacts, let modified = item.modified {
            parts.append("Son değişiklik: \(modified.formatted(date: .abbreviated, time: .omitted))")
        }
        return HStack(spacing: 8) {
            CleanupItemRow(title: shown, subtitle: parts.isEmpty ? nil : parts.joined(separator: " · "),
                           sizeText: Format.bytes(item.bytes),
                           isSelected: vm.selection.contains(item.id) && item.blockedReason == nil,
                           isEnabled: item.blockedReason == nil && !vm.isBusy) { vm.toggle(item) }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            } label: { Image(systemName: "magnifyingglass.circle") }
                .buttonStyle(.borderless)
                .help("Finder'da göster")
                .accessibilityLabel("Finder'da göster: \(shown)")
        }
        .font(.callout)
    }
}
