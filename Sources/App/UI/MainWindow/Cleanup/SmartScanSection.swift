import AppKit
import SwiftUI

/// Akıllı tarama sihirbazı: karşılama → tarama → sonuç → bitti.
/// Büyük dosyalar, yetimler, kopyalar ve gizlilik izleri yalnızca "İncele →" bağlantısıdır; hiçbir zaman seçilmez.
/// Silme yalnızca `SmartScanModel.deleteSelected` (CleanupDeleter) ve `DeleteConfirmation` üzerinden yapılır.
struct SmartScanSection: View {
    @Bindable var model: SmartScanModel
    var onReview: (CleanupSubsection) -> Void = { _ in }
    @State private var confirmSummary: DeleteSummary?
    @State private var confirmItems: [CleanupItem] = []
    @State private var showDone = false

    private let accent = CleanupAccent.smartScan

    init(model: SmartScanModel, onReview: @escaping (CleanupSubsection) -> Void = { _ in }) {
        self.model = model
        self.onReview = onReview
    }

    /// Önizleme testleri için başlangıç adımı (kutlama ekranını doğrudan göstermek için).
    init(model: SmartScanModel, startDone: Bool, onReview: @escaping (CleanupSubsection) -> Void = { _ in }) {
        self.model = model
        self.onReview = onReview
        _showDone = State(initialValue: startDone)
    }

    private var step: CleanupWizardStep {
        if model.isScanning { .scanning } else if !model.hasScanned { .welcome } else if showDone { .done } else { .result }
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
        .onChange(of: model.phase) { old, new in
            if old == .deleting, new == .idle, (model.lastFreed?.count ?? 0) > 0 { showDone = true }
            if new == .scanning { showDone = false }
        }
        .sheet(isPresented: Binding(get: { confirmSummary != nil }, set: { if !$0 { confirmSummary = nil } })) {
            if let summary = confirmSummary {
                DeleteConfirmation(summary: summary, onConfirm: { mode in
                    let chosen = confirmItems
                    confirmSummary = nil
                    confirmItems = []
                    model.deleteSelected(mode: mode, items: chosen)
                }, onCancel: {
                    confirmSummary = nil
                    confirmItems = []
                    model.deleteMode = .trash
                })
            }
        }
    }

    // MARK: 1. Karşılama

    private var welcome: some View {
        CleanupHero3D(symbol: "sparkle.magnifyingglass", accent: accent, badgeSymbol: "sparkles",
                      title: "Akıllı tarama",
                      subtitle: "Önbellekleri, günlükleri ve eski proje artıklarını bulur. Siz onaylamadan hiçbir şey silinmez.",
                      primaryTitle: "Tara", primarySymbol: "magnifyingglass") { model.scan() }
    }

    // MARK: 2. Tarama

    private var scanning: some View {
        let total = Double(SmartScanStep.allCases.count)
        let done = Double(model.result.completed.count)
        let steps = SmartScanStep.allCases.map { step -> CleanupScanStepInfo in
            let result = model.result.results[step]
            let state: CleanupScanStepInfo.State = result != nil ? .done : (model.currentStep == step ? .active : .pending)
            let trailing = result.flatMap { $0.state == .scanned ? Format.bytes($0.displayBytes) : nil }
            return CleanupScanStepInfo(id: step.id, title: step.title, state: state, trailing: trailing)
        }
        return CleanupScanProgress(
            accent: accent, symbol: model.currentStep?.systemImage ?? "magnifyingglass", fraction: done / total,
            title: "Taranıyor: \(model.currentStep?.title ?? "")…", detail: model.currentDetail, steps: steps
        ) { model.cancel() }
    }

    // MARK: 3. Sonuç

    private var result: some View {
        let found = model.foundBytes
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if found == 0 {
                        CleanupAllCleanView(accent: accent, subtitle: "Temizlenecek güvenli bir şey bulunamadı.",
                                            primaryTitle: "Yeniden tara", onPrimary: { model.scan() }, compact: true)
                        if model.result.wasCancelled { cancelledNote }
                    } else {
                        resultHeader(found: found)
                        ForEach(SmartScanStep.allCases.filter(\.isCleanable)) { step in categoryCard(step) }
                    }
                    reviewSection
                    if let scannedAt = model.scannedAt {
                        Text("Son tarama: \(scannedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 10)
            }
            if found > 0 { actionBar.padding(.top, 8).padding(.bottom, 4) }
        }
    }

    private func resultHeader(found: UInt64) -> some View {
        let selected = model.selectedBytes
        var notes: [String] = []
        if found > selected {
            notes.append("Toplam bulunan \(Format.bytes(found)). Seçilmeyenler: son \(SmartScanSelection.staleDays) günde kullanılan projeler, günlükler ve açık uygulamalar.")
        }
        if let freed = model.lastFreed, freed.skipped > 0 {
            notes.append("Son temizlikte \(freed.skipped) öğe atlandı.")
        }
        return CleanupResultHeader(bytes: selected, caption: "temizlenebilir", accent: accent, notes: notes,
                                   warning: model.result.wasCancelled ? "Tarama durduruldu; yalnızca tamamlanan adımlar sayıldı." : nil)
    }

    private var cancelledNote: some View {
        Label("Tarama durduruldu; yalnızca tamamlanan adımlar sayıldı.", systemImage: "exclamationmark.circle")
            .font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity)
    }

    private var actionBar: some View {
        let selected = model.selectedItems
        let bytes = model.selectedBytes
        return CleanupActionBar(
            countText: "\(selected.count) öğe seçili", bytes: bytes, mode: $model.deleteMode,
            isEnabled: !selected.isEmpty, isBusy: model.phase == .deleting, accent: accent
        ) {
            confirmItems = selected
            confirmSummary = DeleteSummary(
                count: selected.count, bytes: bytes, mode: model.deleteMode,
                sample: selected.prefix(5).map { FolderWatchList.displayPath($0.path, home: model.home) }
            )
        } leading: {
            Button { model.scan() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).disabled(model.isBusy).help("Yeniden tara")
        }
    }

    // MARK: Temizlenebilir kategoriler

    @ViewBuilder
    private func categoryCard(_ step: SmartScanStep) -> some View {
        let result = model.result.results[step]
        let items = model.items(for: step)
        let selectedCount = model.selectedCount(for: step)
        let sizeText = (result.map { $0.state == .scanned || !items.isEmpty } ?? false) ? Format.bytes(result?.cleanableBytes ?? 0) : nil
        if items.isEmpty {
            CleanupResultCard(symbol: step.systemImage, title: step.title, subtitle: emptyText(step, result), sizeText: sizeText,
                              accent: accent, selection: .none, isEnabled: false, onToggle: { }) {
                accessButton(result)
            }
        } else {
            CleanupResultCard(
                symbol: step.systemImage, title: step.title,
                subtitle: "\(step.note) \(items.count) öğe, \(selectedCount) seçili.",
                sizeText: sizeText, accent: accent,
                selection: CleanupSelectionState(selected: selectedCount, total: items.count),
                isEnabled: !model.isBusy, onToggle: { model.toggleAll(step) },
                isExpanded: Binding(get: { model.expanded.contains(step) },
                                    set: { if $0 { model.expanded.insert(step) } else { model.expanded.remove(step) } })
            ) {
                itemList(step, items: items, result: result)
            }
        }
    }

    private func emptyText(_ step: SmartScanStep, _ result: SmartScanStepResult?) -> String {
        guard let result else { return "Bu adım çalışmadı." }
        if result.state == .noAccess { return "Erişim yok. İzin verip yeniden tarayın." }
        return result.state == .missing ? "Bulunamadı." : "Temizlenecek bir şey yok."
    }

    @ViewBuilder
    private func accessButton(_ result: SmartScanStepResult?) -> some View {
        if let result, let first = result.deniedRoots.first {
            let reason = CleanupAccess.reason(for: first, home: model.home)
            if let url = reason.settingsURL, let button = reason.buttonTitle {
                Button(button) { NSWorkspace.shared.open(url) }.buttonStyle(.borderless).font(.caption)
            }
        }
    }

    /// Kartın açılan içeriği: uyarılar + öğe satırları.
    private func itemList(_ step: SmartScanStep, items: [CleanupItem], result: SmartScanStepResult?) -> some View {
        let now = model.scannedAt ?? Date()
        let limit = 40
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(extraNotes(step, items: items, result: result), id: \.self) { note in
                Text(note).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let result, !result.deniedRoots.isEmpty {
                HStack(spacing: 6) {
                    Label("Erişim yok: \(SmartScanPresentation.deniedText(result.deniedRoots, home: model.home))", systemImage: "lock")
                        .font(.caption).foregroundStyle(.orange)
                    accessButton(result)
                }
            }
            ForEach(items.prefix(limit)) { item in
                CleanupItemRow(title: SmartScanPresentation.title(item),
                               subtitle: SmartScanPresentation.detail(item, home: model.home, now: now),
                               sizeText: Format.bytes(item.bytes), isSelected: model.isSelected(item),
                               isEnabled: !model.isBusy) { model.toggle(item) }
            }
            if items.count > limit {
                Text("…ve \(items.count - limit) öğe daha (kartın onay kutusu hepsini kapsar)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func extraNotes(_ step: SmartScanStep, items: [CleanupItem], result: SmartScanStepResult?) -> [String] {
        guard let result else { return [] }
        var notes: [String] = []
        if !result.runningBrowsers.isEmpty {
            notes.append("\(result.runningBrowsers.joined(separator: ", ")) açık: kapatıp yeniden tarayın.")
        }
        let blocked = result.blockedItems.filter { $0.category != .browserCaches || result.runningBrowsers.isEmpty }
        if !blocked.isEmpty {
            notes.append("\(blocked.count) öğe (\(Format.bytes(blocked.reduce(0) { $0 + $1.bytes }))) açık uygulama yüzünden atlanır.")
        }
        if step == .projectArtifacts {
            let recent = items.filter { SmartScanSelection.isRecent($0, now: model.scannedAt ?? Date()) }
            if !recent.isEmpty { notes.append("\(recent.count) tanesi son \(SmartScanSelection.staleDays) günde kullanılmış, seçilmedi.") }
        }
        return notes
    }

    // MARK: Yalnızca incele

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Kendiniz inceleyin").font(.headline)
                Text("Bunlar hiçbir zaman otomatik seçilmez ve buradan silinmez. Kendi bölümünde bakıp karar verirsiniz.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 8).padding(.horizontal, 4)
            reviewCard(.trash)
            reviewCard(.largeFiles)
            reviewCard(.orphans)
            ForEach(SmartScanReviewKind.allCases) { kind in
                CleanupResultCard(symbol: kind.systemImage, title: kind.title, subtitle: kind.note, accent: .smartScan.muted) {
                    Button("İncele →") { onReview(kind.subsection) }.buttonStyle(.borderless)
                }
            }
        }
    }

    private func reviewCard(_ step: SmartScanStep) -> some View {
        let result = model.result.results[step]
        let trailing: String? = {
            guard let result, result.state == .scanned else { return nil }
            switch step {
            case .trash: return Format.bytes(result.trashBytes)
            default: return result.reviewCount == 0 ? "Yok" : "\(result.reviewCount) öğe · \(Format.bytes(result.reviewBytes))"
            }
        }()
        let note: String = {
            guard let result else { return step.note }
            switch result.state {
            case .noAccess: return "Erişim yok. İncele'den izin verin."
            case .missing: return step == .trash ? "Çöp Sepeti boş." : step.note
            case .scanned: return step.note
            }
        }()
        return CleanupResultCard(symbol: step.systemImage, title: step.title, subtitle: note, sizeText: trailing,
                                 accent: .smartScan.muted) {
            if step == .trash {
                Button("Finder'da aç") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: CleanupCatalog.trashPath(home: model.home)))
                }
                .buttonStyle(.borderless)
            } else {
                Button("İncele →") { onReview(step.subsection) }.buttonStyle(.borderless)
            }
        }
    }

    // MARK: 4. Bitti

    private var done: some View {
        let freed = model.lastFreed ?? (count: 0, bytes: 0, skipped: 0)
        let trashed = model.lastMode == .trash
        var detail = "\(freed.count) öğe \(trashed ? "taşındı" : "kalıcı olarak silindi")"
        detail += freed.skipped > 0 ? ", \(freed.skipped) atlandı." : "."
        if trashed { detail += " Disk alanı, Çöp Sepeti'ni boşaltınca açılır." }
        return CleanupDoneView(
            accent: accent, bytes: freed.bytes, headline: trashed ? "Çöp Sepeti'ne taşındı" : "boşaltıldı", detail: detail,
            secondaryTitle: "Sonuçlara dön", onSecondary: { showDone = false }
        ) { model.scan() }
    }
}

private extension CleanupAccent {
    /// Yalnızca-incele kartları için sönük ton.
    var muted: CleanupAccent { CleanupAccent(hue: hue, saturation: saturation * 0.45, brightness: brightness * 0.85) }
}
