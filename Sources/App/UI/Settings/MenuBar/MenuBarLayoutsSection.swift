import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Onay bekleyen, düzeni değiştiren ya da silen işlem (MENUBAR-03).
struct LayoutConfirmation: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var confirmLabel: String
    var action: () -> Void

    /// Şu anki düzeni toptan değiştiren işlemler için ortak metin: ne kaybolur + güvence.
    @MainActor
    static func replacing(_ store: MenuBarConfigStore, with what: String, confirmLabel: String,
                          action: @escaping () -> Void) -> LayoutConfirmation {
        let current = MenuBarLayoutEntry(name: "", date: .now, config: store.config).summary
        return LayoutConfirmation(
            title: "Menü çubuğu düzeni değişsin mi?",
            message: "Şu anki düzen (\(current)) yerine \(what) gelecek; sıra, renkler ve eşikler değişir. "
                + "Onaylarsan şu anki düzen önce otomatik yedeklenir, ardından “Geri al” ile hemen dönebilirsin.",
            confirmLabel: confirmLabel, action: action)
    }
}

extension View {
    func layoutConfirmation(_ pending: Binding<LayoutConfirmation?>) -> some View {
        confirmationDialog(pending.wrappedValue?.title ?? "", isPresented: Binding(
            get: { pending.wrappedValue != nil },
            set: { if !$0 { pending.wrappedValue = nil } }
        ), titleVisibility: .visible, presenting: pending.wrappedValue) { item in
            Button(item.confirmLabel, role: .destructive) { item.action() }
            Button("Vazgeç", role: .cancel) {}
        } message: { item in
            Text(item.message)
        }
    }
}

/// Toptan değişiklikten sonra çıkan "Geri al" şeridi.
struct MenuBarUndoSection: View {
    @Bindable var store: MenuBarConfigStore

    var body: some View {
        if let undo = store.undo {
            Section {
                HStack {
                    Label("\(undo.label) uygulandı. Önceki düzen yedeklendi.", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Button("Geri al", systemImage: "arrow.uturn.backward") { store.undoLastReplace() }
                        .buttonStyle(.glass)
                    Button("Kapat", systemImage: "xmark") { store.dismissUndo() }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        .help("Bu şeridi kapat (yedek otomatik yedeklerde kalır)")
                }
            }
        }
    }
}

/// Kayıtlı düzenler + otomatik yedekler + dışa/içe aktarma (MENUBAR-02).
struct MenuBarLayoutsSection: View {
    @Bindable var store: MenuBarConfigStore
    @Binding var pending: LayoutConfirmation?
    @State private var newName = ""
    @State private var showsAutomatic = false
    @State private var message: String?

    private var archive: MenuBarLayoutArchive { store.archive }

    var body: some View {
        Section {
            HStack {
                TextField("Düzen adı", text: $newName, prompt: Text("Örn. Çalışma düzenim"))
                    .onSubmit(saveCurrent)
                Button("Şu anki düzeni kaydet", systemImage: "square.and.arrow.down", action: saveCurrent)
            }
            ForEach(archive.saved) { entry in
                row(entry, automatic: false)
            }
            DisclosureGroup("Otomatik yedekler (\(archive.automatic.count))", isExpanded: $showsAutomatic) {
                if archive.automatic.isEmpty {
                    Text("Henüz otomatik yedek yok.").foregroundStyle(.secondary)
                }
                ForEach(archive.automatic) { entry in
                    row(entry, automatic: true)
                }
            }
            HStack {
                Button("İçe aktar…", systemImage: "square.and.arrow.down.on.square", action: importLayout)
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Kayıtlı düzenler")
        } footer: {
            Text("Sıfırlama, hazır düzen ve geri yüklemeden önce şu anki düzen otomatik yedeklenir (açılışta ve düzenlerken saatte bir de). Son \(MenuBarLayoutArchive.maxAutomatic) otomatik yedek tutulur.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ entry: MenuBarLayoutEntry, automatic: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                Text(entry.date.formatted(date: .abbreviated, time: .shortened) + " · " + entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if entry.config.isSameLayout(as: store.config) {
                Text("Şu anki").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Geri yükle") {
                    pending = .replacing(store, with: "“\(entry.name)” düzeni", confirmLabel: "Geri yükle") {
                        store.restore(entry)
                    }
                }
            }
            Menu {
                if automatic {
                    Button("Kalıcı olarak sakla", systemImage: "pin") {
                        archive.keep(entry.id, name: "Yedek – " + entry.date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Button("Dışa aktar…", systemImage: "square.and.arrow.up") { export(entry) }
                if !automatic {
                    Divider()
                    Button("Sil…", systemImage: "trash", role: .destructive) {
                        pending = LayoutConfirmation(
                            title: "“\(entry.name)” silinsin mi?",
                            message: "Kayıtlı düzen listeden kaldırılır; menü çubuğundaki şu anki düzen değişmez. Silmeden önce dışa aktarabilirsin.",
                            confirmLabel: "Sil") { archive.delete(entry.id) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func saveCurrent() {
        let entry = store.saveCurrentLayout(name: newName)
        newName = ""
        message = archive.lastWriteFailed ? "Kaydedilemedi: dosyaya yazılamadı (disk dolu olabilir)." : "“\(entry.name)” kaydedildi."
    }

    private func export(_ entry: MenuBarLayoutEntry) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Adalmon menü çubuğu – \(entry.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MenuBarLayoutArchive.exportData(entry).write(to: url, options: .atomic)
            message = "Dışa aktarıldı: \(url.lastPathComponent)"
        } catch {
            message = "Dışa aktarılamadı: \(error.localizedDescription)"
        }
    }

    private func importLayout() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let entry = try archive.importLayout(Data(contentsOf: url))
            message = "“\(entry.name)” içe aktarıldı; uygulamak için Geri yükle'ye bas."
        } catch {
            message = error.localizedDescription
        }
    }
}
