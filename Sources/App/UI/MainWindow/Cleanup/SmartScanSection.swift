import AppKit
import SwiftUI

/// Akıllı tarama: tek tıkla tara, neyin silinebileceğini göster, tek "Temizle" ile sil.
/// Büyük dosyalar, yetimler, kopyalar ve gizlilik izleri yalnızca "İncele →" bağlantısıdır; hiçbir zaman seçilmez.
struct SmartScanSection: View {
    @Bindable var model: SmartScanModel
    var onReview: (CleanupSubsection) -> Void = { _ in }
    @State private var confirmSummary: DeleteSummary?
    @State private var confirmItems: [CleanupItem] = []

    init(model: SmartScanModel, onReview: @escaping (CleanupSubsection) -> Void = { _ in }) {
        self.model = model
        self.onReview = onReview
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.isScanning {
                SmartScanProgressView(model: model)
            } else if !model.hasScanned {
                SmartScanEmptyView { model.scan() }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        SmartScanHero(model: model)
                        if let freed = model.lastFreed { freedBanner(freed) }
                        cleanableCard
                        reviewCard
                    }
                    .padding(.bottom, 8)
                }
                Divider()
                bottomBar.padding(.vertical, 10)
            }
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

    // MARK: Temizlenebilir kategoriler

    private var cleanableCard: some View {
        let steps = SmartScanStep.allCases.filter(\.isCleanable)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(steps) { step in
                SmartScanCategoryRow(step: step, model: model)
                if step != steps.last { Divider().padding(.leading, 48) }
            }
        }
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
    }

    // MARK: Yalnızca incele

    private var reviewCard: some View {
        ResourceCard(title: "Kendiniz inceleyin", systemImage: "eye") {
            Text("Bunlar hiçbir zaman otomatik seçilmez ve buradan silinmez. Kendi bölümünde bakıp karar verirsiniz.")
                .font(.caption).foregroundStyle(.secondary)
            reviewRow(.trash)
            reviewRow(.largeFiles)
            reviewRow(.orphans)
            ForEach(SmartScanReviewKind.allCases) { kind in
                reviewRow(icon: kind.systemImage, title: kind.title, note: kind.note, trailing: nil, subsection: kind.subsection)
            }
        }
    }

    @ViewBuilder
    private func reviewRow(_ step: SmartScanStep) -> some View {
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
        reviewRow(icon: step.systemImage, title: step.title, note: note, trailing: trailing, subsection: step.subsection,
                  openTrash: step == .trash)
    }

    private func reviewRow(icon: String, title: String, note: String, trailing: String?, subsection: CleanupSubsection,
                           openTrash: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let trailing { Text(trailing).monospacedDigit().foregroundStyle(.secondary) }
            if openTrash {
                Button("Finder'da aç") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: CleanupCatalog.trashPath(home: model.home)))
                }
                .buttonStyle(.borderless)
            } else {
                Button("İncele →") { onReview(subsection) }.buttonStyle(.borderless)
            }
        }
    }

    // MARK: Sonuç ve alt çubuk

    private func freedBanner(_ freed: (count: Int, bytes: UInt64, skipped: Int)) -> some View {
        let trashed = model.lastMode == .trash
        return VStack(alignment: .leading, spacing: 4) {
            Label(trashed ? "\(Format.bytes(freed.bytes)) Çöp Sepeti'ne taşındı" : "\(Format.bytes(freed.bytes)) boşaltıldı",
                  systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(.green)
            Text("\(freed.count) öğe \(trashed ? "taşındı" : "kalıcı olarak silindi"), \(freed.skipped) atlandı."
                 + (trashed ? " Disk alanı, Çöp Sepeti'ni boşaltınca açılır." : ""))
                .font(.caption).foregroundStyle(.secondary)
        }
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
            Button("Yeniden tara", systemImage: "arrow.clockwise") { model.scan() }
                .buttonStyle(.borderless).disabled(model.isBusy)
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

// MARK: - Boş durum

/// Sayfa açılınca: ortada büyük tek "Tara" düğmesi.
private struct SmartScanEmptyView: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Button(action: action) {
                VStack(spacing: 6) {
                    Image(systemName: "sparkle.magnifyingglass").font(.system(size: 38, weight: .medium))
                    Text("Tara").font(.title2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 148, height: 148)
                .background(
                    Circle().fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .shadow(color: Color.accentColor.opacity(0.35), radius: 14, y: 6)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Tara")
            VStack(spacing: 6) {
                Text("Neyin silinebileceğine bakalım").font(.title3.bold())
                Text("Önbellekler, günlükler, gereksiz build'ler ve eski proje artıkları taranır. Tarama yalnızca siz basınca yapılır; hiçbir şey kendiliğinden silinmez.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tarama sürüyor

private struct SmartScanProgressView: View {
    @Bindable var model: SmartScanModel

    var body: some View {
        let total = Double(SmartScanStep.allCases.count)
        let done = Double(model.result.completed.count)
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            ZStack {
                Circle().stroke(Color.primary.opacity(0.10), lineWidth: 10)
                Circle().trim(from: 0, to: max(0.02, done / total))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: done)
                VStack(spacing: 2) {
                    Image(systemName: model.currentStep?.systemImage ?? "magnifyingglass")
                        .font(.system(size: 26)).foregroundStyle(.tint)
                    Text("\(Int(done)) / \(Int(total))").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .frame(width: 130, height: 130)
            VStack(spacing: 4) {
                Text("Taranıyor: \(model.currentStep?.title ?? "")…").font(.title3.bold())
                if let detail = model.currentDetail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(SmartScanStep.allCases) { step in progressLine(step) }
            }
            .frame(maxWidth: 380)
            Button("Durdur") { model.cancel() }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func progressLine(_ step: SmartScanStep) -> some View {
        let result = model.result.results[step]
        return HStack(spacing: 8) {
            if result != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if model.currentStep == step {
                ProgressView().controlSize(.small).frame(width: 16)
            } else {
                Image(systemName: "circle").foregroundStyle(.tertiary)
            }
            Text(step.title).foregroundStyle(result == nil && model.currentStep != step ? .tertiary : .primary)
            Spacer()
            if let result, result.state == .scanned {
                Text(Format.bytes(result.displayBytes)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }
}

// MARK: - Sonuç başlığı

private struct SmartScanHero: View {
    @Bindable var model: SmartScanModel

    var body: some View {
        let selected = model.selectedBytes
        let found = model.foundBytes
        VStack(spacing: 6) {
            Text(Format.bytes(selected))
                .font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
            Text(found == 0 ? "Temizlenecek güvenli bir şey bulunamadı" : "temizlenebilir")
                .font(.title3).foregroundStyle(.secondary)
            if found > selected {
                Text("Toplam bulunan \(Format.bytes(found)). Seçilmeyenler: son \(SmartScanSelection.staleDays) günde kullanılan projeler, günlükler ve açık uygulamalar.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if model.result.wasCancelled {
                Label("Tarama durduruldu; yalnızca tamamlanan adımlar sayıldı.", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let at = model.scannedAt {
                Text("Son tarama: \(at.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16))
    }
}

// MARK: - Kategori satırı

private struct SmartScanCategoryRow: View {
    let step: SmartScanStep
    @Bindable var model: SmartScanModel
    private static let shownLimit = 40

    var body: some View {
        let result = model.result.results[step]
        let items = model.items(for: step)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                checkbox(items)
                Image(systemName: step.systemImage).frame(width: 22).foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                    Text(detail(result, items: items)).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    accessNote(result)
                }
                Spacer(minLength: 8)
                if let result, result.state == .scanned || !items.isEmpty {
                    Text(Format.bytes(result.cleanableBytes)).monospacedDigit().foregroundStyle(.secondary)
                }
                if !items.isEmpty {
                    Button {
                        if model.expanded.contains(step) { model.expanded.remove(step) } else { model.expanded.insert(step) }
                    } label: {
                        Image(systemName: model.expanded.contains(step) ? "chevron.down" : "chevron.right").frame(width: 14)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(model.expanded.contains(step) ? "Ayrıntıyı kapat" : "Ayrıntıyı aç")
                }
            }
            if model.expanded.contains(step), !items.isEmpty { itemList(items) }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    /// Üç durumlu onay kutusu: hepsi / bir kısmı / hiçbiri.
    private func checkbox(_ items: [CleanupItem]) -> some View {
        let count = model.selectedCount(for: step)
        let symbol = count == 0 ? "square" : count == items.count ? "checkmark.square.fill" : "minus.square.fill"
        return Button { model.toggleAll(step) } label: {
            Image(systemName: symbol).font(.system(size: 16))
                .foregroundStyle(count == 0 ? Color.secondary : Color.accentColor)
                .frame(width: 16)
        }
        .buttonStyle(.plain)
        .disabled(items.isEmpty || model.isBusy)
        .opacity(items.isEmpty ? 0.35 : 1)
        .accessibilityLabel(step.title)
        .accessibilityValue(count == 0 ? "seçili değil" : count == items.count ? "hepsi seçili" : "bir kısmı seçili")
    }

    private func detail(_ result: SmartScanStepResult?, items: [CleanupItem]) -> String {
        guard let result else { return "Bu adım çalışmadı." }
        if result.state == .noAccess && items.isEmpty { return "Erişim yok. İncele'den izin verin." }
        var parts: [String] = []
        if items.isEmpty {
            parts.append(result.state == .missing ? "Bulunamadı." : "Temizlenecek bir şey yok.")
        } else {
            parts.append(step.note)
            parts.append("\(items.count) öğe, \(model.selectedCount(for: step)) seçili.")
        }
        if !result.runningBrowsers.isEmpty {
            parts.append("\(result.runningBrowsers.joined(separator: ", ")) açık: kapatıp yeniden tarayın.")
        }
        let blocked = result.blockedItems.filter { $0.category != .browserCaches || result.runningBrowsers.isEmpty }
        if !blocked.isEmpty {
            parts.append("\(blocked.count) öğe (\(Format.bytes(blocked.reduce(0) { $0 + $1.bytes }))) açık uygulama yüzünden atlanır.")
        }
        if step == .projectArtifacts {
            let recent = items.filter { SmartScanSelection.isRecent($0, now: model.scannedAt ?? Date()) }
            if !recent.isEmpty { parts.append("\(recent.count) tanesi son \(SmartScanSelection.staleDays) günde kullanılmış, seçilmedi.") }
        }
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private func accessNote(_ result: SmartScanStepResult?) -> some View {
        if let result, !result.deniedRoots.isEmpty {
            let reason = CleanupAccess.reason(for: result.deniedRoots[0], home: model.home)
            HStack(spacing: 6) {
                Label("Erişim yok: \(SmartScanPresentation.deniedText(result.deniedRoots, home: model.home))", systemImage: "lock")
                    .font(.caption).foregroundStyle(.orange)
                if let url = reason.settingsURL, let button = reason.buttonTitle {
                    Button(button) { NSWorkspace.shared.open(url) }.buttonStyle(.borderless).font(.caption)
                }
            }
        }
    }

    private func itemList(_ items: [CleanupItem]) -> some View {
        let now = model.scannedAt ?? Date()
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(items.prefix(Self.shownLimit)) { item in
                HStack(alignment: .top, spacing: 8) {
                    Toggle("", isOn: Binding(get: { model.isSelected(item) }, set: { _ in model.toggle(item) }))
                        .toggleStyle(.checkbox).labelsHidden().disabled(model.isBusy)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(SmartScanPresentation.title(item)).lineLimit(1).truncationMode(.middle)
                        Text(SmartScanPresentation.detail(item, home: model.home, now: now))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Text(Format.bytes(item.bytes)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if items.count > Self.shownLimit {
                Text("…ve \(items.count - Self.shownLimit) öğe daha (üstteki onay kutusu hepsini kapsar)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 56).padding(.top, 2)
    }
}
