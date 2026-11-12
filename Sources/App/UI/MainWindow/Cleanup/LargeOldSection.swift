import AppKit
import SwiftUI

/// Büyük & eski dosyalar: seçilen klasörlerde eşiğin üstündeki dosyaları listeler; yalnızca tıklayınca tarar.
struct LargeOldSection: View {
    @State private var vm = LargeOldModel()
    @State private var confirmSummary: DeleteSummary?
    @State private var confirmItems: [LargeOldItem] = []

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
            let selected = vm.selectedItems
            FilesDeleteBar(
                summaryText: "Seçili: \(selected.count) dosya · \(Format.bytes(selected.reduce(UInt64(0)) { $0 + $1.bytes }))",
                hasSelection: !selected.isEmpty, isBusy: vm.isBusy, mode: $vm.deleteMode
            ) {
                confirmItems = selected
                confirmSummary = DeleteSummary(
                    count: selected.count, bytes: selected.reduce(UInt64(0)) { $0 + $1.bytes }, mode: vm.deleteMode,
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

    private var controls: some View {
        HStack(spacing: 10) {
            if vm.phase == .scanning {
                ProgressView().controlSize(.small)
                Text(vm.progressText).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Button("Durdur") { vm.cancel() }
            } else {
                Button("Tara", systemImage: "magnifyingglass") { vm.scan() }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isBusy || vm.rootsStore.roots.isEmpty)
            }
            Spacer(minLength: 8)
            Picker("En az", selection: $vm.minBytes) {
                ForEach(LargeOldModel.sizeChoices, id: \.self) { Text("≥ \(Format.bytes($0))").tag($0) }
            }
            .fixedSize().disabled(vm.isBusy).help("Boyut eşiği; değişince yeniden taranır")
            Toggle("Yalnızca eski", isOn: $vm.onlyOld).toggleStyle(.checkbox)
            Picker("Eski sayılır", selection: $vm.oldDays) {
                ForEach(LargeOldModel.ageChoices, id: \.self) { Text("≥ \(FilesText.ageLabel($0))").tag($0) }
            }
            .fixedSize().disabled(!vm.onlyOld)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !vm.hasScanned {
            if vm.phase != .scanning {
                ResourceEmptyNote(text: "Seçili klasörlerdeki büyük dosyaları görmek için Tara'ya basın. Tarama yalnızca siz isteyince yapılır; iCloud'da duran dosyalar indirilmez, uygulama ve kütüphane paketlerinin içine girilmez.")
            }
        } else if vm.visibleItems.isEmpty {
            ResourceEmptyNote(text: vm.items.isEmpty ? "Eşiğin üstünde dosya bulunamadı." : "Bu süzgece uyan dosya yok.")
        } else {
            ResourceCard(title: "\(vm.visibleItems.count) dosya · \(Format.bytes(vm.visibleBytes))", systemImage: "doc.badge.clock") {
                HStack {
                    Button("Hepsini seç") { vm.selectAllVisible(true) }.buttonStyle(.borderless)
                    Button("Seçimi kaldır") { vm.selectAllVisible(false) }.buttonStyle(.borderless)
                    Spacer()
                    Text("Eski = son değiştirilme tarihi").font(.caption).foregroundStyle(.secondary)
                }
                .font(.callout)
                LazyVStack(spacing: 2) {
                    ForEach(vm.visibleItems.prefix(500)) { item in row(item) }
                }
                if vm.visibleItems.count > 500 {
                    Text("En büyük 500 dosya gösteriliyor.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if vm.unreadableDirs > 0 {
                Text("\(vm.unreadableDirs) klasör okunamadı.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ item: LargeOldItem) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { vm.selection.contains(item.id) }, set: { _ in vm.toggle(item) }))
                .toggleStyle(.checkbox).labelsHidden()
                .accessibilityLabel(item.name)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(FolderWatchList.displayPath((item.path as NSString).deletingLastPathComponent, home: vm.home))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(FilesText.ageText(item.modified)).font(.caption).foregroundStyle(.secondary)
            Text(Format.bytes(item.bytes)).monospacedDigit().frame(width: 80, alignment: .trailing)
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) } label: {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.borderless).help("Finder'da göster")
        }
        .font(.callout)
        .padding(.vertical, 2)
    }
}
