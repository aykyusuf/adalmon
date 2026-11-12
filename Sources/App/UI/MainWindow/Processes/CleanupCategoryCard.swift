import AppKit
import SwiftUI

/// Temizlik kategorisi kartı: üç durumlu seçim kutusu, toplam boyut, açılır satırlar (en çok 200).
struct CleanupCategoryCard: View {
    let vm: CleanupViewModel
    let category: CleanupCategory
    let state: CleanupRootState?
    var onHelp: (AccessReason) -> Void = { _ in }
    @State private var expanded = false
    @State private var folderError: String?

    private static let rowCap = 200

    var body: some View {
        let items = vm.items(in: category)
        let selectable = items.filter { $0.blockedReason == nil }
        let selectedCount = selectable.filter { vm.selection.contains($0.id) }.count
        let total = items.reduce(UInt64(0)) { $0 + $1.bytes }
        ResourceCard(title: category.title, systemImage: category.systemImage) {
            if category.needsExplicitScan {
                HStack(spacing: 8) {
                    Button(category.scanButtonTitle, systemImage: "magnifyingglass") {
                        vm.scan([category])
                    }
                    .disabled(vm.isBusy || (category == .projectArtifacts && vm.projectFolders.isEmpty))
                    Text("Yalnızca listelenir, otomatik seçilmez.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if category == .projectArtifacts { projectFolderEditor }
            if let note = category.note {
                Text(note).font(.caption).foregroundStyle(category == .iosBackups ? Color.orange : Color.secondary)
            }
            if category == .browserCaches, items.contains(where: { $0.blockedReason != nil }) {
                Label("Önce tarayıcıyı kapatın", systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
            if state == .noAccess {
                let reason = vm.accessReason(for: category) ?? .fullDiskAccess
                HStack(spacing: 8) {
                    Label(reason.title, systemImage: "lock").foregroundStyle(.orange)
                    if let button = reason.buttonTitle {
                        Button(button) { vm.access.openSettings(for: reason) }
                    }
                    Button("Nasıl?") { onHelp(reason) }.buttonStyle(.borderless)
                }
            } else if state == .missing, vm.scannedCategories.contains(category), category != .projectArtifacts {
                ResourceEmptyNote(text: "Bulunamadı.")
            } else if vm.scannedCategories.contains(category), items.isEmpty {
                ResourceEmptyNote(text: "Listelenecek öğe yok.")
            }
            if !items.isEmpty {
                HStack(spacing: 8) {
                    Button {
                        vm.setCategory(category, selected: selectedCount < selectable.count)
                    } label: {
                        Image(systemName: selectedCount == 0 ? "square" : selectedCount == selectable.count ? "checkmark.square.fill" : "minus.square.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectable.isEmpty)
                    .accessibilityLabel("Tümünü seç: \(category.title)")
                    Text("\(items.count) öğe · \(Format.bytes(total))").monospacedDigit()
                    Spacer()
                    Button(expanded ? "Gizle" : "Göster") { expanded.toggle() }.buttonStyle(.borderless)
                }
                if expanded {
                    ForEach(items.prefix(Self.rowCap)) { item in row(item) }
                    if items.count > Self.rowCap {
                        Text("+\(items.count - Self.rowCap) daha").font(.caption).foregroundStyle(.secondary)
                    }
                }
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
                Button("Klasör ekle…", systemImage: "plus") { chooseFolders() }.disabled(vm.isBusy)
                if vm.projectFolders.isEmpty {
                    Text("Henüz proje klasörü yok.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let folderError { Text(folderError).font(.caption).foregroundStyle(.red) }
        }
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
        return HStack(spacing: 8) {
            Button { vm.toggle(item) } label: {
                Image(systemName: vm.selection.contains(item.id) && item.blockedReason == nil ? "checkmark.square.fill" : "square")
            }
            .buttonStyle(.borderless)
            .disabled(item.blockedReason != nil)
            Text(shown).lineLimit(1).truncationMode(.middle)
            if let badge = item.blockedReason {
                Text(badge).font(.caption2).padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.orange.opacity(0.2), in: .capsule)
            }
            Spacer(minLength: 8)
            if category == .downloads || category == .projectArtifacts, let modified = item.modified {
                Text(modified.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            }
            Text(Format.bytes(item.bytes)).monospacedDigit().foregroundStyle(.secondary)
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
