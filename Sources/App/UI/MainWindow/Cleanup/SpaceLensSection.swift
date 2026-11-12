import AppKit
import SwiftUI

/// Yer kaplayanlar: klasörün alt öğelerini treemap olarak gösterir. Salt okunurdur (silme yok); yalnızca tıklayınca tarar.
struct SpaceLensSection: View {
    @State private var vm = SpaceLensModel()
    @State private var selectedID: String?
    @State private var message: String?
    @State private var helpReason: AccessReason?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                topRow
                if !vm.trail.isEmpty { breadcrumb }
                if !vm.access.blocked.isEmpty { FilesAccessBanner(access: vm.access, home: vm.home) }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                content
            }
            .padding(.bottom, 8)
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
        .sheet(item: $helpReason) { reason in
            AccessHelpSheet(reason: reason, monitor: vm.access) { helpReason = nil }
        }
    }

    private var topRow: some View {
        HStack(spacing: 10) {
            if vm.phase == .scanning {
                if let fraction = vm.progressFraction { ProgressView(value: fraction).frame(width: 90) } else { ProgressView().controlSize(.small) }
                Text(vm.progressText).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Button("Durdur") { vm.cancel() }
            } else {
                Button("Ev klasörünü tara", systemImage: "magnifyingglass") { startScan(vm.home) }
                    .buttonStyle(.borderedProminent)
                Button("Klasör seç…", systemImage: "folder") { choose() }
                if vm.current != nil { Button("Yeniden tara", systemImage: "arrow.clockwise") { vm.rescan() } }
            }
            Spacer(minLength: 8)
            if vm.current != nil {
                Text("Toplam: \(Format.bytes(vm.totalBytes))").foregroundStyle(.secondary).monospacedDigit()
            }
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
        if vm.current == nil {
            if vm.phase != .scanning {
                ResourceEmptyNote(text: "Klasörlerin ne kadar yer kapladığını görmek için tarayın. Tıklayınca bir klasörün içine girilir. Burada hiçbir şey silinmez. Başka uygulamaların verileri ve iCloud'da duran dosyalar açılmaz.")
            }
        } else if vm.nodes.isEmpty {
            ResourceEmptyNote(text: vm.lastState == .noAccess ? "Bu klasöre erişim yok." : "Bu klasör boş.")
        } else {
            TreemapCanvas(nodes: vm.nodes, otherBytes: vm.otherBytes, selectedID: selectedID, contextPath: vm.current ?? "") { node in
                selectedID = node.id
                if node.isFolder, !vm.isBusy { vm.open(node.path) }
            }
            .frame(height: 340)
            .clipShape(.rect(cornerRadius: 8))
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
        return HStack(spacing: 8) {
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
        .background(node.id == selectedID ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 6))
    }

    private func icon(_ node: SpaceNode) -> String {
        switch node.kind {
        case .folder: "folder"
        case .file: "doc"
        case .locked: "lock"
        case .skipped: "eye.slash"
        }
    }

    private func startScan(_ path: String) {
        selectedID = nil
        message = nil
        vm.start(root: path)
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
