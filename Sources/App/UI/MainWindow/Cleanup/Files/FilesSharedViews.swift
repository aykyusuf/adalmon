import AppKit
import SwiftUI

/// Satırlara saran basit yerleşim (klasör çipleri dar pencerede alt satıra iner). `centered`: her satır ortalanır.
struct FilesFlowLayout: Layout {
    var spacing: CGFloat = 6
    var centered = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arranged = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in arranged.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        // Önce satırlara böl, sonra (isteğe bağlı) satırı ortala.
        var rows: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((index, size))
            x += size.width + spacing
        }
        var origins = [CGPoint](repeating: .zero, count: subviews.count)
        var y: CGFloat = 0
        var maxWidth: CGFloat = 0
        for row in rows where !row.isEmpty {
            let rowWidth = row.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(row.count - 1)
            let rowHeight = row.map(\.size.height).max() ?? 0
            var cursor: CGFloat = centered && width.isFinite ? max(0, (width - rowWidth) / 2) : 0
            for item in row {
                origins[item.index] = CGPoint(x: cursor, y: y + (rowHeight - item.size.height) / 2)
                cursor += item.size.width + spacing
            }
            maxWidth = max(maxWidth, rowWidth)
            y += rowHeight + spacing
        }
        return (CGSize(width: maxWidth, height: max(0, y - spacing)), origins)
    }
}

/// Taranan klasörler: çipler (çıkarma düğmeli), "Klasör ekle…" (NSOpenPanel) ve varsayılana dönüş.
struct FilesRootsBar: View {
    let store: FileRootsStore
    let disabled: Bool
    var centered = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FilesFlowLayout(spacing: 6, centered: centered) {
                if store.roots.isEmpty { Text("Hiç klasör yok").font(.callout).foregroundStyle(.orange) }
                ForEach(store.roots, id: \.self) { root in
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(FolderWatchList.displayPath(root, home: store.home)).lineLimit(1).truncationMode(.middle)
                        Button { store.remove(root) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).disabled(disabled).foregroundStyle(.secondary)
                            .accessibilityLabel("\(FolderWatchList.displayPath(root, home: store.home)) klasörünü çıkar")
                    }
                    .font(.caption)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.primary.opacity(0.08), in: .capsule)
                }
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

/// Sonuç ekranındaki filtre çubuğunda "Klasörler" düğmesi: tıklayınca klasör çiplerini açılır pencerede gösterir.
struct FilesRootsPopoverButton: View {
    let store: FileRootsStore
    let disabled: Bool
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            FilesPillLabel(title: "\(store.roots.count) klasör", systemImage: "folder", showsChevron: false)
        }
        .buttonStyle(.plain)
        .help("Taranan klasörler")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Taranan klasörler").font(.headline)
                FilesRootsBar(store: store, disabled: disabled)
                Text("Değişiklik, sonraki taramada uygulanır.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(width: 340)
        }
    }
}

/// Filtre çubuğundaki küçük kapsül etiketi (menü ve düğmeler için ortak görünüm).
struct FilesPillLabel: View {
    let title: String
    var systemImage: String?
    var showsChevron = true
    var isActive = false

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.caption) }
            Text(title).font(.callout)
            if showsChevron { Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary) }
        }
        .foregroundStyle(isActive ? Color.primary : Color.secondary)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color.primary.opacity(isActive ? 0.12 : 0.07), in: .capsule)
        .contentShape(.capsule)
    }
}

/// Filtre çubuğu: seçenekleri menüden seçtirir.
struct FilesPillMenu<Content: View>: View {
    let title: String
    var systemImage: String?
    var isActive = false
    var disabled = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu(content: content) {
            FilesPillLabel(title: title, systemImage: systemImage, isActive: isActive)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(disabled)
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

/// Silme sonrası atlanan dosyalar (başarılı olanlar "bitti" ekranında gösterilir). Atlanan yoksa hiçbir şey çizilmez.
struct FilesResultBanner: View {
    let results: [CleanupResult]
    let mode: DeleteMode
    let home: String
    @State private var showDetails = false

    var body: some View {
        let moved = results.filter(\.isRemoved)
        let skipped = results.filter { !$0.isRemoved }
        if !skipped.isEmpty {
            let verb = mode == .trash ? "Çöp Sepeti'ne taşındı" : "kalıcı olarak silindi"
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("\(moved.count) dosya \(verb); \(skipped.count) dosya atlandı.", systemImage: "exclamationmark.circle")
                    Spacer()
                    Button(showDetails ? "Gizle" : "Ayrıntılar") { showDetails.toggle() }.buttonStyle(.borderless)
                }
                .font(.callout)
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
            .background(Color.yellow.opacity(0.12), in: .rect(cornerRadius: 12))
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
    /// Dosya uzantısına göre kart simgesi.
    static func symbol(forPath path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "mov", "mp4", "m4v", "mkv", "avi", "webm": "film"
        case "mp3", "m4a", "wav", "aiff", "flac": "music.note"
        case "jpg", "jpeg", "png", "heic", "gif", "tiff", "raw", "psd": "photo"
        case "zip", "gz", "tar", "rar", "7z", "xz": "doc.zipper"
        case "dmg", "iso", "pkg": "externaldrive"
        case "pdf": "doc.richtext"
        case "key", "pptx", "ppt": "rectangle.on.rectangle"
        default: "doc"
        }
    }

    static func ageText(_ date: Date, now: Date = Date()) -> String {
        let days = max(0, Int(now.timeIntervalSince(date) / 86_400))
        if days < 60 { return "\(days) gün önce" }
        if days < 730 { return "\(days / 30) ay önce" }
        return "\(days / 365) yıl önce"
    }
}
