import AppKit
import SwiftUI

/// Kopyalar: aynı içerikli dosyaları gruplar. Her grupta bir dosya korunur (değiştirilebilir); grubun hepsi asla seçilemez.
struct DuplicatesSection: View {
    @State private var vm = DuplicatesModel()
    @State private var confirmSummary: DeleteSummary?
    @State private var confirmFiles: [DuplicateFile] = []

    private static let sizeChoices: [UInt64] = [1 << 20, 10 << 20, 100 << 20]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    FilesRootsBar(store: vm.rootsStore, disabled: vm.isBusy)
                    controls
                    if !vm.access.blocked.isEmpty { FilesAccessBanner(access: vm.access, home: vm.home) }
                    if let result = vm.lastResult { FilesResultBanner(results: result, mode: vm.lastMode, home: vm.home) }
                    content
                }
                .padding(.bottom, 8)
            }
            Divider()
            let selected = vm.selectedFiles
            let bytes = selected.reduce(UInt64(0)) { $0 + $1.allocated }
            FilesDeleteBar(
                summaryText: "Seçili: \(selected.count) kopya · \(Format.bytes(bytes))",
                hasSelection: !selected.isEmpty, isBusy: vm.isBusy, mode: $vm.deleteMode
            ) {
                confirmFiles = selected
                confirmSummary = DeleteSummary(
                    count: selected.count, bytes: bytes, mode: vm.deleteMode,
                    sample: selected.prefix(5).map { FolderWatchList.displayPath($0.path, home: vm.home) }
                )
            }
            .padding(.vertical, 10)
        }
        .onAppear { vm.access.resume() }
        .onChange(of: vm.minBytes) { if vm.hasScanned { vm.scan() } }
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

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if vm.phase == .scanning {
                    if let fraction = vm.progressFraction {
                        ProgressView(value: fraction).frame(width: 90)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(vm.progressText).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Button("Durdur") { vm.cancel() }
                } else {
                    Button("Tara", systemImage: "magnifyingglass") { vm.scan() }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isBusy || vm.rootsStore.roots.isEmpty)
                }
                Spacer(minLength: 8)
                Picker("En küçük", selection: $vm.minBytes) {
                    ForEach(Self.sizeChoices, id: \.self) { Text("≥ \(Format.bytes($0))").tag($0) }
                }
                .fixedSize().disabled(vm.isBusy).help("Boyut eşiği; değişince yeniden taranır")
            }
            Text("Aynı içerik önce boyuta, sonra ilk 64 KB'a, sonra tam SHA-256 özetine göre eşlenir. APFS klonları aynı bloklarla durabilir: bunları silmek gösterilen yerin çoğunu (yaklaşık 0 bayt) açmayabilir.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !vm.hasScanned {
            if vm.phase != .scanning {
                ResourceEmptyNote(text: "Kopya dosyaları bulmak için Tara'ya basın. Tarama yalnızca siz isteyince yapılır; iCloud'da duran dosyalar indirilmez.")
            }
        } else if vm.groups.isEmpty {
            ResourceEmptyNote(text: "Kopya bulunamadı.")
        } else {
            HStack {
                Text("\(vm.groups.count) grup · en çok \(Format.bytes(vm.reclaimableBytes)) açılabilir").foregroundStyle(.secondary)
                Spacer()
                Button("Her gruptan fazlalıkları seç") { vm.selectAllButKeepers() }.buttonStyle(.borderless)
                Button("Seçimi kaldır") { vm.clearSelection() }.buttonStyle(.borderless)
            }
            .font(.callout)
            LazyVStack(spacing: 10) {
                ForEach(vm.groups.prefix(200)) { group in groupCard(group) }
            }
            if vm.groups.count > 200 { Text("En büyük 200 grup gösteriliyor.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func groupCard(_ group: DuplicateGroup) -> some View {
        let keeper = vm.selection.keeper(of: group)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(group.files[0].name).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("\(group.files.count) kopya · \(Format.bytes(group.size)) her biri").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(group.files) { file in
                let isKeeper = file.path == keeper
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(get: { vm.selection.isSelected(file.path) }, set: { _ in vm.toggle(file, in: group) }))
                        .toggleStyle(.checkbox).labelsHidden().disabled(isKeeper)
                        .accessibilityLabel(file.path)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(FolderWatchList.displayPath(file.path, home: vm.home)).lineLimit(1).truncationMode(.middle)
                        Text(file.modified.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if isKeeper {
                        Label("Korunacak", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.green)
                    } else {
                        Button("Bunu koru") { vm.setKeeper(file, in: group) }.buttonStyle(.borderless).font(.caption)
                    }
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)]) } label: {
                        Image(systemName: "magnifyingglass.circle")
                    }
                    .buttonStyle(.borderless).help("Finder'da göster")
                }
                .font(.callout)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
    }
}
