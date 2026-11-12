import AppKit
import SwiftUI

// Sistem çöpü / Geliştirici sonuç ekranının yardımcı parçaları: Tam Disk Erişimi rozeti, erişim uyarısı,
// silme özeti, Çöp Sepeti kartı ve son işlemler. Mantık `CleanupViewModel`dedir; burası yalnızca görünümdür.

/// Tam Disk Erişimi durumu; kapalıysa tıklayınca nasıl açılacağını gösterir.
struct CleanupFullDiskBadge: View {
    let vm: CleanupViewModel
    let onHelp: (AccessReason) -> Void

    var body: some View {
        if let granted = vm.access.fullDiskAccess {
            Button {
                if !granted { onHelp(.fullDiskAccess) }
            } label: {
                Label("Tam Disk Erişimi: \(granted ? "açık" : "kapalı")", systemImage: granted ? "checkmark.shield" : "shield.slash")
                    .font(.caption)
                    .foregroundStyle(granted ? Color.secondary : Color.orange)
            }
            .buttonStyle(.borderless)
            .disabled(granted)
            .help(granted ? "Adalmon Tam Disk Erişimi'ne sahip" : "Tam Disk Erişimi nasıl açılır?")
        }
    }
}

/// Erişilemeyen kökler: neden başına bir satır, ilgili ayar düğmesi ve yardım.
struct CleanupAccessBanner: View {
    let vm: CleanupViewModel
    let onHelp: (AccessReason) -> Void

    var body: some View {
        let reasons = Array(Set(vm.access.blocked.values)).sorted { $0.title < $1.title }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(reasons) { reason in
                let paths = vm.access.blocked.filter { $0.value == reason }.keys.sorted()
                    .map { FolderWatchList.displayPath($0, home: vm.home) }
                HStack(spacing: 8) {
                    Image(systemName: "lock").foregroundStyle(.orange).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(reason.title)
                        Text(paths.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    if let button = reason.buttonTitle {
                        Button(button) { vm.access.openSettings(for: reason) }
                    }
                    Button("Nasıl?") { onHelp(reason) }.buttonStyle(.borderless)
                }
            }
            if vm.access.suggestRestart {
                HStack(spacing: 8) {
                    Text("Ayarlardan döndünüz ama erişim hâlâ yok. macOS bazen izni yeniden açılışta uygular.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Adalmon'u yeniden başlat") { CleanupAccessMonitor.relaunch() }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: .rect(cornerRadius: 16))
    }
}

/// Son silme işleminin özeti; atlananlar için ayrıntı açılır.
struct CleanupDeletionBanner: View {
    let results: [CleanupResult]
    let mode: DeleteMode
    let home: String
    @State private var showDetails = false

    var body: some View {
        let moved = results.filter(\.isRemoved)
        let skipped = results.filter { !$0.isRemoved }
        let bytes = moved.reduce(UInt64(0)) { $0 + $1.candidate.bytes }
        let verb = mode == .trash ? "taşındı" : "kalıcı olarak silindi"
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("\(moved.count) öğe \(verb) (\(Format.bytes(bytes))). \(skipped.count) atlandı.", systemImage: "checkmark.circle")
                Spacer()
                if !skipped.isEmpty {
                    Button(showDetails ? "Gizle" : "Ayrıntılar") { showDetails.toggle() }.buttonStyle(.borderless)
                }
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.10), in: .rect(cornerRadius: 16))
    }
}

/// Çöp Sepeti: yalnızca boyut ve Finder bağlantısı; buradan boşaltılmaz, seçilmez.
struct CleanupTrashCard: View {
    let vm: CleanupViewModel
    let accent: CleanupAccent
    let onHelp: (AccessReason) -> Void

    var body: some View {
        let state = vm.trashState
        CleanupResultCard(
            symbol: "trash", title: "Çöp Sepeti", subtitle: subtitle(state?.state), sizeText: sizeText(state),
            accent: accent
        ) {
            HStack(spacing: 8) {
                if state == nil {
                    Button("Hesapla") { vm.measureTrash() }.controlSize(.small).disabled(vm.isBusy)
                } else if state?.state == .noAccess {
                    Button("Nasıl?") { onHelp(CleanupAccess.reason(for: CleanupCatalog.trashPath(home: vm.home), home: vm.home)) }
                        .buttonStyle(.borderless)
                }
                Button("Finder'da aç", systemImage: "folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: CleanupCatalog.trashPath(home: vm.home)))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func subtitle(_ state: CleanupRootState?) -> String {
        switch state {
        case .scanned?: "Taşınanlar burada durur; Çöp boşaltılınca disk alanı açılır."
        case .noAccess?: "Erişim yok: Tam Disk Erişimi gerekiyor."
        case .missing?: "Çöp Sepeti boş."
        case nil: "Boyutunu görmek için Hesapla'ya basın."
        }
    }

    private func sizeText(_ state: (state: CleanupRootState, bytes: UInt64)?) -> String? {
        guard let state, state.state == .scanned else { return nil }
        return Format.bytes(state.bytes)
    }
}

/// Son 20 işlem (denetim günlüğü).
struct CleanupLogCard: View {
    let vm: CleanupViewModel
    let accent: CleanupAccent
    @State private var expanded = false

    var body: some View {
        CleanupResultCard(symbol: "clock", title: "Son işlemler", subtitle: "Son 20 işlem", accent: accent, isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                if vm.log.isEmpty {
                    Text("Henüz işlem yok.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(vm.log) { entry in entryRow(entry) }
                }
            }
        }
        .onChange(of: expanded) { if expanded { vm.reloadLog() } }
    }

    private func entryRow(_ entry: CleanupLogEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.result == "moved" ? "arrow.right.circle" : entry.result == "deleted" ? "xmark.circle" : "minus.circle")
                .foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(FolderWatchList.displayPath(entry.path, home: vm.home)).lineLimit(1).truncationMode(.middle)
                Text([entry.date?.formatted(date: .abbreviated, time: .shortened), entry.result == "deleted" ? "kalıcı silindi" : nil, entry.reason]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(Format.bytes(entry.bytes)).monospacedDigit().foregroundStyle(.secondary)
            if let to = entry.trashedTo {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: to)])
                } label: { Image(systemName: "magnifyingglass.circle") }
                    .buttonStyle(.borderless)
                    .help("Çöp Sepeti'nde göster")
                    .accessibilityLabel("Çöp Sepeti'nde göster")
            }
        }
        .font(.callout)
    }
}
