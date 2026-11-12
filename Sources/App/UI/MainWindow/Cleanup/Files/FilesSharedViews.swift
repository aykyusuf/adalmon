import AppKit
import SwiftUI

/// Taranan klasörler: çipler (çıkarma düğmeli), "Klasör ekle…" (NSOpenPanel) ve varsayılana dönüş.
struct FilesRootsBar: View {
    let store: FileRootsStore
    let disabled: Bool
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Klasörler:").foregroundStyle(.secondary)
                if store.roots.isEmpty { Text("Hiç klasör yok").foregroundStyle(.orange) }
                ForEach(store.roots, id: \.self) { root in
                    HStack(spacing: 4) {
                        Text(FolderWatchList.displayPath(root, home: store.home)).lineLimit(1).truncationMode(.middle)
                        Button { store.remove(root) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).disabled(disabled)
                            .accessibilityLabel("\(FolderWatchList.displayPath(root, home: store.home)) klasörünü çıkar")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08), in: .capsule)
                }
                Spacer(minLength: 8)
                Button("Klasör ekle…", systemImage: "plus") { choose() }.controlSize(.small).disabled(disabled)
                if !store.isDefault {
                    Button("Varsayılan") { store.resetToDefaults() }.controlSize(.small).disabled(disabled)
                }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.orange) }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Ekle"
        panel.directoryURL = URL(fileURLWithPath: store.home)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in message = store.add(url.path).message }
        }
    }
}

/// Erişilemeyen kökler için mevcut erişim akışı (CleanupAccess + AccessHelpSheet).
struct FilesAccessBanner: View {
    let access: CleanupAccessMonitor
    let home: String
    @State private var helpReason: AccessReason?

    var body: some View {
        Group {
            if !access.blocked.isEmpty {
                let reasons = Array(Set(access.blocked.values)).sorted { $0.title < $1.title }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(reasons) { reason in
                        let paths = access.blocked.filter { $0.value == reason }.keys.sorted().map { FolderWatchList.displayPath($0, home: home) }
                        HStack(spacing: 8) {
                            Image(systemName: "lock").foregroundStyle(.orange).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(reason.title)
                                Text(paths.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            if let button = reason.buttonTitle { Button(button) { access.openSettings(for: reason) } }
                            Button("Nasıl?") { helpReason = reason }.buttonStyle(.borderless)
                        }
                    }
                    if access.suggestRestart {
                        HStack(spacing: 8) {
                            Text("Ayarlardan döndünüz ama erişim hâlâ yok. macOS bazen izni yeniden açılışta uygular.")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Button("Adalmon'u yeniden başlat") { CleanupAccessMonitor.relaunch() }
                        }
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.10), in: .rect(cornerRadius: 12))
            }
        }
        .sheet(item: $helpReason) { reason in
            AccessHelpSheet(reason: reason, monitor: access) { helpReason = nil }
        }
    }
}

struct FilesResultBanner: View {
    let results: [CleanupResult]
    let mode: DeleteMode
    let home: String
    @State private var showDetails = false

    var body: some View {
        let moved = results.filter(\.isRemoved)
        let skipped = results.filter { !$0.isRemoved }
        let bytes = moved.reduce(UInt64(0)) { $0 + $1.candidate.bytes }
        let verb = mode == .trash ? "Çöp Sepeti'ne taşındı" : "kalıcı olarak silindi"
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("\(moved.count) dosya \(verb) (\(Format.bytes(bytes))). \(skipped.count) atlandı.", systemImage: "checkmark.circle")
                Spacer()
                if !skipped.isEmpty { Button(showDetails ? "Gizle" : "Ayrıntılar") { showDetails.toggle() }.buttonStyle(.borderless) }
            }
            if showDetails {
                ForEach(skipped, id: \.candidate.id) { r in
                    HStack {
                        Text(FolderWatchList.displayPath(r.candidate.path, home: home)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(r.reasonText ?? "").foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.10), in: .rect(cornerRadius: 12))
    }
}

/// Alt çubuk: seçim özeti, silme yöntemi (Çöp varsayılan) ve silme düğmesi.
struct FilesDeleteBar: View {
    let summaryText: String
    let hasSelection: Bool
    let isBusy: Bool
    @Binding var mode: DeleteMode
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text(summaryText).monospacedDigit().foregroundStyle(.secondary)
            Spacer()
            if isBusy { ProgressView().controlSize(.small) }
            Picker("Silme yöntemi", selection: $mode) {
                Text("Çöp'e taşı").tag(DeleteMode.trash)
                Text("Kalıcı sil").tag(DeleteMode.permanent)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().disabled(isBusy)
            .help("Kalıcı silme yalnızca bu işlem içindir; sonra Çöp'e taşımaya döner.")
            Button(mode == .trash ? "Çöp Sepeti'ne taşı…" : "Kalıcı olarak sil…", systemImage: mode == .trash ? "trash" : "xmark.bin", action: onDelete)
                .tint(mode == .trash ? nil : .red)
                .disabled(!hasSelection || isBusy)
        }
    }
}

enum FilesText {
    static func sizeLabel(_ bytes: UInt64) -> String { Format.bytes(bytes) }
    static func ageLabel(_ days: Int) -> String {
        switch days {
        case 90: "3 ay"
        case 180: "6 ay"
        case 365: "1 yıl"
        case 730: "2 yıl"
        default: "\(days) gün"
        }
    }
    static func ageText(_ date: Date, now: Date = Date()) -> String {
        let days = max(0, Int(now.timeIntervalSince(date) / 86_400))
        if days < 60 { return "\(days) gün önce" }
        if days < 730 { return "\(days / 30) ay önce" }
        return "\(days / 365) yıl önce"
    }
}
