import AppKit
import SwiftUI

extension UninstallerModel.Tab: CapsuleTabItem {
    var systemImage: String { self == .apps ? "square.grid.2x2" : "questionmark.folder" }
}

/// Kaldırıcı sihirbazı: karşılama → tarama → sonuç (uygulama kartları + "Yetim dosyalar" sekmesi) → bitti.
/// Tarama yalnızca "Uygulamaları listele"ye basınca olur. Silme yalnızca `UninstallerModel.remove` (AppRemover / CleanupDeleter) ve
/// `DeleteConfirmation` ile yapılır; çalışan uygulama kaldırılamaz, App Store / root uygulamaları için Finder'da göster önerilir.
struct UninstallerSection: View {
    @State private var model = UninstallerModel()
    @State private var confirm: ConfirmState?
    @State private var helpReason: AccessReason?
    @State private var showDetails = false
    @State private var showDone = false

    private let accent = CleanupAccent.uninstaller

    init(model: UninstallerModel = UninstallerModel(), startDone: Bool = false) {
        _model = State(initialValue: model)
        _showDone = State(initialValue: startDone)
    }

    private struct ConfirmState: Identifiable {
        let id = UUID()
        var summary: DeleteSummary
        var pending: PendingRemoval
    }

    private var step: CleanupWizardStep {
        if case .scanning = model.phase { return .scanning }
        if !model.hasScanned { return .welcome }
        return showDone ? .done : .result
    }

    var body: some View {
        CleanupWizard(step: step) {
            welcome
        } scanning: {
            scanning
        } result: {
            result
        } done: {
            done
        }
        .onAppear {
            model.access.refreshFullDiskAccess()
            model.refreshRunning()
        }
        .onDisappear {
            model.cancel()
            model.access.stop()
            model.deleteMode = .trash
        }
        .onChange(of: model.phase) { old, new in
            if case .scanning = new { showDone = false }
            if old == .deleting, new == .idle, (model.report?.results ?? []).contains(where: \.isRemoved) { showDone = true }
        }
        .sheet(item: $confirm) { state in
            DeleteConfirmation(summary: state.summary, onConfirm: { mode in
                confirm = nil
                model.remove(state.pending, mode: mode)
            }, onCancel: {
                confirm = nil
                model.deleteMode = .trash
            })
        }
        .sheet(item: $helpReason) { reason in
            AccessHelpSheet(reason: reason, monitor: model.access) { helpReason = nil }
        }
    }

    // MARK: 1. Karşılama

    private var welcome: some View {
        CleanupHero3D(
            symbol: "app.badge.checkmark.fill", accent: accent, badgeSymbol: "trash", title: "Kaldırıcı",
            subtitle: "Uygulamaları artık dosyalarıyla birlikte kaldırın; uygulaması silinmiş yetim dosyaları da bulur. Siz seçmeden hiçbir şey silinmez.",
            primaryTitle: "Uygulamaları listele", primarySymbol: "list.bullet"
        ) { model.scan() }
    }

    // MARK: 2. Tarama

    private var scanning: some View {
        var done = 0
        var total = 0
        if case .scanning(let d, let t) = model.phase { done = d; total = t }
        return CleanupScanProgress(
            accent: accent, symbol: "app.badge.checkmark", fraction: total > 0 ? Double(done) / Double(total) : nil,
            title: "Uygulamalar taranıyor…", detail: total > 0 ? "\(done) / \(total) uygulama" : nil
        ) { model.cancel() }
    }

    // MARK: 3. Sonuç

    private var result: some View {
        VStack(spacing: 0) {
            CapsuleTabBar(selection: $model.tab, accessibilityLabel: "Kaldırıcı bölümü")
                .padding(.bottom, 10)
            toolsRow.padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let issue = model.accessIssue { accessBanner(issue) }
                    if let report = model.report { skippedBanner(report) }
                    header
                    if model.tab == .apps { AppListView(model: model) } else { OrphanListView(model: model) }
                }
                .padding(.bottom, 10)
            }
            if model.deleteMode == .permanent {
                Text("Başlangıç ajanı (LaunchAgent) dosyaları kalıcı modda bile Çöp'e taşınır.")
                    .font(.caption2).foregroundStyle(.secondary).padding(.top, 6)
            }
            actionBar.padding(.top, 8).padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var header: some View {
        if model.tab == .apps {
            let all = model.apps
            CleanupResultHeader(
                bytes: all.reduce(UInt64(0)) { $0 + $1.bytes + $1.leftoverBytes },
                caption: "\(all.count) uygulama ve artıkları", accent: accent
            )
        } else {
            CleanupResultHeader(
                bytes: model.orphans.reduce(UInt64(0)) { $0 + $1.bytes },
                caption: "\(model.orphans.count) yetim grup", accent: accent,
                notes: ["Uygulaması artık kurulu olmayan, kimliği tam bir uygulamaya bağlanamayan dosyalar. Liste tahminidir: emin olmadığınız hiçbir şeyi seçmeyin. Varsayılan olarak hiçbiri seçili değil; 1 MB'tan küçük klasörler listelenmez."]
            )
        }
    }

    private var toolsRow: some View {
        HStack(spacing: 8) {
            if model.tab == .apps {
                FilesPillMenu(title: "Sırala: \(model.sort.title)", systemImage: "arrow.up.arrow.down") {
                    Picker("Sırala", selection: $model.sort) {
                        ForEach(UninstallerModel.Sort.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
                .help("Sıralama")
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Ara", text: $model.search).textFieldStyle(.plain)
                if !model.search.isEmpty {
                    Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help("Aramayı temizle")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .frame(width: 190)
            .background(Color.primary.opacity(0.07), in: .capsule)
        }
    }

    private var actionBar: some View {
        let pending = model.pending
        // Çalışan uygulama seçiliyse kaldırılacak bir şey yoktur (onay kutusu da kapalı görünür): toplam sıfır gösterilir.
        let blocked = model.selectedAppRunning
        let count = blocked ? 0 : (pending?.candidates.count ?? 0)
        let bytes = blocked ? 0 : (pending?.bytes ?? 0)
        return CleanupActionBar(
            countText: "\(count) öğe seçili", bytes: bytes, mode: $model.deleteMode, title: "Kaldır",
            isEnabled: pending != nil && !model.selectedAppRunning, isBusy: model.phase == .deleting, accent: accent
        ) {
            guard let pending else { return }
            confirm = ConfirmState(summary: DeleteSummary(
                count: count, bytes: bytes, mode: model.deleteMode,
                sample: pending.candidates.prefix(5).map { FolderWatchList.displayPath($0.path, home: model.home) }
            ), pending: pending)
        } leading: {
            Button { model.scan() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).disabled(model.isBusy).help("Yeniden tara")
        }
        .help(model.selectedAppRunning ? "Uygulama açık: önce kapatın" : "")
    }

    // MARK: Bantlar

    private func accessBanner(_ reason: AccessReason) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock").foregroundStyle(.orange).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(reason.title)
                Text("Seçiminiz korundu. İzni verdikten sonra Kaldır'a yeniden basın.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let button = reason.buttonTitle {
                Button(button) { model.access.openSettings(for: reason) }
            }
            Button("Nasıl?") { helpReason = reason }.buttonStyle(.borderless)
            Button { model.dismissReport() } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless).help("Kapat")
        }
        .padding(12)
        .background(Color.orange.opacity(0.10), in: .rect(cornerRadius: 12))
    }

    /// Başarılı kaldırmalar "bitti" ekranında gösterilir; burada yalnızca atlananlar (varsa) kalır.
    @ViewBuilder
    private func skippedBanner(_ report: AppRemovalReport) -> some View {
        let removed = report.results.filter(\.isRemoved)
        let others = report.results.filter { !$0.isRemoved }
        if !others.isEmpty {
            let verb = model.lastMode == .trash ? "taşındı" : "kalıcı olarak silindi"
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("\(removed.count) öğe \(verb); \(others.count) öğe atlandı.", systemImage: "exclamationmark.circle")
                    Spacer()
                    Button(showDetails ? "Gizle" : "Ayrıntılar") { showDetails.toggle() }.buttonStyle(.borderless)
                    Button { model.dismissReport() } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless).help("Kapat")
                }
                .font(.callout)
                if showDetails {
                    ForEach(others, id: \.candidate.id) { result in
                        HStack {
                            Text(FolderWatchList.displayPath(result.candidate.path, home: model.home)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(result.reasonText ?? "").foregroundStyle(.secondary).lineLimit(1)
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(12)
            .background(Color.yellow.opacity(0.12), in: .rect(cornerRadius: 12))
        }
    }

    // MARK: 4. Bitti

    private var done: some View {
        let results = model.report?.results ?? []
        let removed = results.filter(\.isRemoved)
        let bytes = removed.reduce(UInt64(0)) { $0 + $1.candidate.bytes }
        let skipped = results.count - removed.count
        let trashed = model.lastMode == .trash
        var detail = "\(removed.count) öğe \(trashed ? "taşındı" : "kalıcı olarak silindi")"
        detail += skipped > 0 ? ", \(skipped) atlandı." : "."
        if trashed { detail += " Disk alanı, Çöp Sepeti'ni boşaltınca açılır." }
        if model.accessIssue != nil { detail += " Bazı öğeler için izin gerekiyor; listeye dönünce ayrıntılar görünür." }
        return CleanupDoneView(
            accent: accent, bytes: bytes, headline: trashed ? "Çöp Sepeti'ne taşındı" : "boşaltıldı", detail: detail,
            primaryTitle: "Listeye dön", primarySymbol: "list.bullet", secondaryTitle: "Yeniden tara",
            onSecondary: { showDone = false; model.scan() }
        ) { showDone = false }
    }
}
