import AppKit
import SwiftUI

@MainActor @Observable
final class SmartScanModel {
    enum Phase: Equatable { case idle, scanning(SmartScanStep?), deleting }

    let home: String
    var phase: Phase = .idle
    var result = SmartScanResult()
    var hasScanned = false
    /// Temizle'ye girecek adımlar (tarama sonrası hepsi açık; riskli tür yoktur).
    var enabledSteps: Set<SmartScanStep> = Set(SmartScanStep.allCases.filter(\.isCleanable))
    var deleteMode: DeleteMode = .trash
    var lastResult: [CleanupResult]?
    var lastMode: DeleteMode = .trash
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    /// Geç gelen eski tarama bildirimlerini yok saymak için.
    @ObservationIgnored private var scanID = UUID()

    init(home: String = NSHomeDirectory()) { self.home = home }

    var isBusy: Bool { phase != .idle }

    var selectedItems: [CleanupItem] { result.cleanableItems(steps: enabledSteps) }
    var selectedBytes: UInt64 { selectedItems.reduce(0) { $0 + $1.bytes } }

    func scan() {
        guard !isBusy else { return }
        let running = CleanupViewModel.runningBundleIDs()
        let home = home
        phase = .scanning(nil)
        lastResult = nil
        result = SmartScanResult()
        let id = UUID()
        scanID = id
        scanTask = Task.detached(priority: .utility) { [weak self] in
            let out = SmartScanAggregator.run(
                home: home, runningBundleIDs: running, isCancelled: { Task.isCancelled },
                stepStarted: { step in Task { @MainActor [weak self] in
                    if self?.scanID == id, case .scanning = self?.phase { self?.phase = .scanning(step) }
                } },
                stepFinished: { partial in Task { @MainActor [weak self] in
                    guard self?.scanID == id else { return }
                    self?.result.results[partial.step] = partial
                    self?.result.completed.append(partial.step)
                } }
            )
            await self?.finish(out, id: id)
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        scanID = UUID()
        if case .scanning = phase {
            result.wasCancelled = true
            phase = .idle
            hasScanned = true
        }
    }

    private func finish(_ out: SmartScanResult, id: UUID) {
        guard scanID == id, case .scanning = phase else { return }
        result = out
        hasScanned = true
        phase = .idle
        scanTask = nil
    }

    func toggle(_ step: SmartScanStep) {
        if enabledSteps.contains(step) { enabledSteps.remove(step) } else { enabledSteps.insert(step) }
    }

    func deleteSelected(mode: DeleteMode, items chosen: [CleanupItem]) {
        guard !chosen.isEmpty, !isBusy else {
            deleteMode = .trash
            return
        }
        let roots = CleanupCatalog.roots(home: home)
        let candidates = chosen.map { DeletionCandidate(item: $0, roots: roots) }
        let deleter = CleanupDeleter(home: home)
        phase = .deleting
        Task.detached(priority: .utility) { [weak self] in
            let results = deleter.delete(candidates, mode: mode)
            await MainActor.run { [weak self] in
                guard let self else { return }
                let removed = Set(results.filter(\.isRemoved).map(\.candidate.id))
                for (step, var stepResult) in result.results {
                    stepResult.items.removeAll { removed.contains($0.id) }
                    result.results[step] = stepResult
                }
                lastResult = results
                lastMode = mode
                deleteMode = .trash
                phase = .idle
            }
        }
    }
}

/// Akıllı tarama: tek tıkla yalnızca güvenli önbellekleri tarar, toplamı gösterir, temizler.
/// Riskli türler (yetimler, büyük dosyalar, kopyalar, gizlilik, proje artıkları) taranmaz ve seçilmez: yalnızca "İncele" kartı.
struct SmartScanSection: View {
    var onReview: (CleanupSubsection) -> Void = { _ in }
    @State private var model = SmartScanModel()
    @State private var confirmSummary: DeleteSummary?
    @State private var confirmItems: [CleanupItem] = []

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    if let results = model.lastResult { banner(results) }
                    if model.hasScanned || model.isBusy { safeRows }
                    reviewCards
                }
                .padding(.bottom, 8)
            }
            Divider()
            bottomBar.padding(.vertical, 10)
        }
        .onDisappear {
            model.cancel()
            model.deleteMode = .trash
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

    // MARK: Özet

    private var hero: some View {
        VStack(spacing: 10) {
            switch model.phase {
            case .scanning(let step):
                ProgressView(value: Double(model.result.completed.count), total: Double(SmartScanStep.allCases.count))
                    .frame(maxWidth: 320)
                Text("Taranıyor: \(step?.title ?? "")…").foregroundStyle(.secondary)
                Button("Durdur") { model.cancel() }
            case .deleting:
                ProgressView().controlSize(.regular)
                Text("Temizleniyor…").foregroundStyle(.secondary)
            case .idle:
                if model.hasScanned {
                    let bytes = model.result.cleanableBytes()
                    Text(Format.bytes(bytes))
                        .font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(bytes == 0 ? "Temizlenecek güvenli bir şey bulunamadı" : "temizlenebilir")
                        .font(.title3).foregroundStyle(.secondary)
                    if model.result.wasCancelled {
                        Label("Tarama durduruldu; yalnızca tamamlanan adımlar sayıldı.", systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Button("Yeniden tara", systemImage: "arrow.clockwise") { model.scan() }
                } else {
                    Image(systemName: "wand.and.stars").font(.system(size: 34)).foregroundStyle(.tint).accessibilityHidden(true)
                    Text("Güvenli önbellekleri tek tıkla tara").font(.title3.bold())
                    Text("Uygulama, tarayıcı ve geliştirici önbellekleri ile Çöp Sepeti boyutu taranır. Riskli türler taranmaz, hiçbir şey kendiliğinden silinmez.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Button("Tara", systemImage: "magnifyingglass") { model.scan() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
    }

    // MARK: Güvenli satırlar

    private var safeRows: some View {
        ResourceCard(title: "Güvenli önbellekler", systemImage: "checkmark.shield") {
            ForEach(SmartScanStep.allCases) { step in
                SmartScanRow(step: step, model: model, onReview: onReview)
                if step != SmartScanStep.allCases.last { Divider() }
            }
        }
    }

    // MARK: Riskli türler

    private var reviewCards: some View {
        ResourceCard(title: "Kendiniz inceleyin", systemImage: "eye") {
            Text("Bunlar taranmaz ve hiçbir zaman otomatik seçilmez. Her biri kendi bölümünde, siz isteyince taranır.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(SmartScanReviewKind.allCases) { kind in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: kind.systemImage).frame(width: 22).foregroundStyle(.secondary).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                        Text(kind.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button("İncele") { onReview(kind.subsection) }.buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: Sonuç ve alt çubuk

    private func banner(_ results: [CleanupResult]) -> some View {
        let moved = results.filter(\.isRemoved)
        let skipped = results.count - moved.count
        let bytes = moved.reduce(UInt64(0)) { $0 + $1.candidate.bytes }
        let verb = model.lastMode == .trash ? "taşındı" : "kalıcı olarak silindi"
        return Label("\(moved.count) öğe \(verb) (\(Format.bytes(bytes))). \(skipped) atlandı.", systemImage: "checkmark.circle")
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.10), in: .rect(cornerRadius: 12))
    }

    private var bottomBar: some View {
        let selected = model.selectedItems
        let bytes = model.selectedBytes
        return HStack {
            Text("Seçili: \(selected.count) öğe · \(Format.bytes(bytes))").monospacedDigit().foregroundStyle(.secondary)
            Spacer()
            Picker("Silme yöntemi", selection: $model.deleteMode) {
                Text("Çöp'e taşı").tag(DeleteMode.trash)
                Text("Kalıcı sil").tag(DeleteMode.permanent)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .disabled(model.isBusy)
            .help("Kalıcı silme yalnızca bu işlem içindir; sonra Çöp'e taşımaya döner.")
            Button(model.deleteMode == .trash ? "Temizle…" : "Kalıcı olarak temizle…",
                   systemImage: model.deleteMode == .trash ? "sparkles" : "xmark.bin") {
                confirmItems = selected
                confirmSummary = DeleteSummary(
                    count: selected.count, bytes: bytes, mode: model.deleteMode,
                    sample: selected.prefix(5).map { FolderWatchList.displayPath($0.path, home: model.home) }
                )
            }
            .tint(model.deleteMode == .trash ? nil : .red)
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty || model.isBusy)
        }
    }
}

private struct SmartScanRow: View {
    let step: SmartScanStep
    @Bindable var model: SmartScanModel
    let onReview: (CleanupSubsection) -> Void

    var body: some View {
        let result = model.result.results[step]
        HStack(alignment: .top, spacing: 10) {
            if step.isCleanable {
                Toggle("", isOn: Binding(get: { model.enabledSteps.contains(step) }, set: { _ in model.toggle(step) }))
                    .toggleStyle(.checkbox).labelsHidden()
                    .disabled(result == nil || result?.cleanableItems.isEmpty != false)
            } else {
                Color.clear.frame(width: 16)
            }
            Image(systemName: step.systemImage).frame(width: 22).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                Text(detail(result)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing(result)
            Button("İncele") { onReview(step.subsection) }.buttonStyle(.borderless)
        }
    }

    private func detail(_ result: SmartScanStepResult?) -> String {
        guard let result else {
            if case .scanning(let current) = model.phase, current == step { return "Taranıyor…" }
            return model.phase == .idle ? "Tarama durduruldu, bu adım çalışmadı." : "Sırada"
        }
        switch result.state {
        case .noAccess: return "Erişim yok. İncele'den izin verin."
        case .missing: return "Bulunamadı."
        case .scanned: break
        }
        var parts = [step.note]
        if !result.runningBrowsers.isEmpty {
            parts.append("\(result.runningBrowsers.joined(separator: ", ")) açık: kapatıp yeniden tarayın.")
        }
        let blocked = result.blockedItems.filter { $0.category != .browserCaches || result.runningBrowsers.isEmpty }
        if !blocked.isEmpty {
            parts.append("\(blocked.count) öğe (\(Format.bytes(blocked.reduce(0) { $0 + $1.bytes }))) açık uygulama yüzünden atlanır.")
        }
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private func trailing(_ result: SmartScanStepResult?) -> some View {
        if let result, result.state == .scanned {
            Text(Format.bytes(result.displayBytes)).monospacedDigit().foregroundStyle(.secondary)
            if step == .trash {
                Button("Finder'da aç") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: CleanupCatalog.trashPath(home: model.home)))
                }
                .buttonStyle(.borderless)
            }
        } else if result == nil, case .scanning(let current) = model.phase, current == step {
            ProgressView().controlSize(.small)
        }
    }
}
