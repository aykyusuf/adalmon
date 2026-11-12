import AppKit
import SwiftUI

/// Seçili uygulama kartının açılan içeriği: uyarılar, "uygulamanın kendisi" ve artıklar (onay kutularıyla).
/// Tam bundle kimliği eşleşenler seçili gelir; ada göre eşleşenler seçili gelmez (model karar verir).
struct AppLeftoverDetail: View {
    @Bindable var model: UninstallerModel
    let app: InstalledApp

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            notes
            bundleRow
            leftoverGroups
            HStack {
                Spacer()
                Button("Finder'da göster", systemImage: "magnifyingglass") { reveal(app.path) }
                    .buttonStyle(.borderless).font(.caption)
            }
        }
    }

    @ViewBuilder
    private var notes: some View {
        if model.isRunning(app) {
            noteBox(icon: "exclamationmark.triangle.fill", color: .orange,
                    text: "\(app.name) şu an açık. Kaldırmak için önce uygulamayı kapatın; açıkken hiçbir şeye dokunulmaz.") {
                Button("Yeniden denetle") { model.refreshRunning() }
            }
        }
        if let block = app.removalBlock {
            noteBox(icon: "lock.fill", color: .secondary, text: block.note) {
                Button("Finder'da göster") { reveal(app.path) }
            }
        }
    }

    private var bundleRow: some View {
        let allowed = app.removalBlock == nil && !model.isRunning(app)
        return Toggle(isOn: Binding(get: { model.includeBundle && allowed }, set: { model.includeBundle = $0 })) {
            HStack {
                Text("Uygulamanın kendisi").font(.callout.weight(.medium))
                Spacer(minLength: 8)
                Text(Format.bytes(app.bytes)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .toggleStyle(.checkbox)
        .disabled(!allowed)
    }

    @ViewBuilder
    private var leftoverGroups: some View {
        if app.leftovers.isEmpty {
            Text("Bu uygulamaya ait artık dosya bulunamadı. Yalnızca tam bundle kimliği ya da tam uygulama adı eşleşenler listelenir.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            HStack {
                Text("Artıklar · \(app.leftovers.count) öğe · \(Format.bytes(app.leftoverBytes))")
                    .font(.callout.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button("Tümünü seç") { model.leftoverSelection = Set(app.leftovers.map(\.path)) }.buttonStyle(.borderless)
                Button("Hiçbiri") { model.leftoverSelection = [] }.buttonStyle(.borderless)
            }
            .font(.caption)
            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(group.items) { item in
                        LeftoverRow(item: item, home: model.home, isOn: Binding(
                            get: { model.leftoverSelection.contains(item.path) },
                            set: { if $0 { model.leftoverSelection.insert(item.path) } else { model.leftoverSelection.remove(item.path) } }
                        ))
                    }
                }
            }
        }
    }

    private var groups: [(title: String, items: [DeletionCandidate])] {
        var order: [String] = []
        var map: [String: [DeletionCandidate]] = [:]
        for item in app.leftovers {
            let title = LeftoverLocation(kind: item.kind)?.title ?? "Diğer"
            if map[title] == nil { order.append(title) }
            map[title, default: []].append(item)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private func noteBox<Action: View>(icon: String, color: Color, text: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).accessibilityHidden(true)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            action()
        }
        .padding(10)
        .background(color.opacity(0.10), in: .rect(cornerRadius: 10))
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

/// Artık / yetim satırı: onay kutusu, ad, kısaltılmış yol, boyut, Finder'da göster.
struct LeftoverRow: View {
    let item: DeletionCandidate
    let home: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.displayName).lineLimit(1).truncationMode(.middle)
                    Text(FolderWatchList.displayPath(item.path, home: home))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            .toggleStyle(.checkbox)
            Spacer(minLength: 8)
            Text(Format.bytes(item.bytes)).foregroundStyle(.secondary).monospacedDigit()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            } label: { Image(systemName: "magnifyingglass.circle") }
                .buttonStyle(.borderless)
                .help("Finder'da göster")
        }
        .font(.callout)
    }
}
