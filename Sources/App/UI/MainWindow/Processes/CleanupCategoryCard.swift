import AppKit
import SwiftUI

/// Temizlik kategorisi kartı: üç durumlu seçim kutusu, toplam boyut, açılır satırlar (en çok 200).
struct CleanupCategoryCard: View {
    let vm: CleanupViewModel
    let category: CleanupCategory
    let state: CleanupRootState?
    var onHelp: (AccessReason) -> Void = { _ in }
    @State private var expanded = false

    private static let rowCap = 200

    var body: some View {
        let items = vm.items(in: category)
        let selectable = items.filter { $0.blockedReason == nil }
        let selectedCount = selectable.filter { vm.selection.contains($0.id) }.count
        let total = items.reduce(UInt64(0)) { $0 + $1.bytes }
        ResourceCard(title: category.title, systemImage: category.systemImage) {
            if category.needsExplicitScan {
                HStack(spacing: 8) {
                    Button(category == .downloads ? "İndirilenleri tara" : "Yedekleri tara", systemImage: "magnifyingglass") {
                        vm.scan([category])
                    }
                    .disabled(vm.isBusy)
                    Text("Yalnızca listelenir, otomatik seçilmez.").font(.caption).foregroundStyle(.secondary)
                }
                if category == .iosBackups {
                    Text("Yedeği silmek o cihazın geri yükleme noktasını kaldırır.").font(.caption).foregroundStyle(.orange)
                }
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
            } else if state == .missing, vm.scannedCategories.contains(category) {
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
            if category == .downloads, let modified = item.modified {
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
