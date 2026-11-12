import AppKit
import SwiftUI

/// Gizlilik sihirbazı: karşılama → tarama → tarayıcı kartları (geçmiş / çerezler seçimi) → bitti.
/// Chrome, Edge ve Safari; yalnızca Tara'ya basınca okur. Açık tarayıcı reddedilir, yer imleri ve kayıtlı parolalar
/// hiçbir koşulda listelenmez ya da silinmez. Silme Çöp Sepeti'ne gider (kalıcı silme işlem başına, iki onayla).
struct PrivacySection: View {
    @State private var vm: BrowserPrivacyViewModel
    @State private var confirm: PrivacyConfirmRequest?
    @State private var helpReason: AccessReason?
    @State private var isRunning = false
    @State private var runTask: Task<Void, Never>?
    @State private var freed: PrivacyFreed?
    @State private var showDone = false
    @State private var showSkipped = false
    private let forceScanning: Bool

    private let accent = CleanupAccent.privacy

    init() {
        _vm = State(initialValue: BrowserPrivacyViewModel())
        forceScanning = false
    }

    /// Önizleme testleri için: modeli ve başlangıç adımını (tarama ya da bitti) doğrudan verir.
    init(vm: BrowserPrivacyViewModel, startFreed: PrivacyFreed? = nil, forceScanning: Bool = false) {
        _vm = State(initialValue: vm)
        _freed = State(initialValue: startFreed)
        _showDone = State(initialValue: startFreed != nil)
        self.forceScanning = forceScanning
    }

    private var step: CleanupWizardStep {
        if forceScanning { .scanning }
        else if showDone { .done }
        else if vm.phase == .scanning && !isRunning { .scanning }
        else if !vm.hasScanned { .welcome }
        else { .result }
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
        .onAppear { vm.access.resume() }
        .onDisappear {
            runTask?.cancel()
            vm.cancel()
            vm.access.stop()
            vm.resetMode()
        }
        .sheet(item: $confirm) { request in
            PrivacyConfirmSheet(request: request, mode: vm.deleteMode, home: vm.home, onConfirm: { mode in
                confirm = nil
                start(request, mode: mode)
            }, onCancel: {
                confirm = nil
                vm.resetMode()
            })
        }
        .sheet(item: $helpReason) { reason in
            AccessHelpSheet(reason: reason, monitor: vm.access) { helpReason = nil }
        }
    }

    // MARK: 1. Karşılama

    private var welcome: some View {
        CleanupHero3D(symbol: "hand.raised.fill", accent: accent, badgeSymbol: "lock.fill",
                      title: "Gizlilik",
                      subtitle: "Chrome, Edge ve Safari'deki geçmişi ve çerezleri temizler. Yer imleri ve kayıtlı parolalar listelenmez, silinmez.",
                      primaryTitle: "Tara", primarySymbol: "magnifyingglass") { vm.scan() }
        accessory: {
            Text("Tarama yalnızca siz isteyince yapılır. Tarayıcılar açıksa önce kapatmanız gerekir.")
                .font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
    }

    // MARK: 2. Tarama

    private var scanning: some View {
        CleanupScanProgress(accent: accent, symbol: "hand.raised.fill", title: "Tarayıcılar taranıyor…",
                            detail: PrivacyBrowser.allCases.map(\.shortName).joined(separator: ", ")) { vm.cancel() }
    }

    // MARK: 3. Sonuç

    private var result: some View {
        let shown = PrivacyBrowser.allCases.compactMap { browser in vm.scan(for: browser).map { (browser, $0) } }
        let found = shown.reduce(UInt64(0)) { $0 + ($1.1.state == .scanned ? $1.1.files.reduce(0) { $0 + $1.bytes } : 0) }
        let hasProblem = shown.contains { $0.1.state == .running || $0.1.state == .noAccess }
        let anyData = shown.contains { $0.1.state != .notFound }
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if found == 0 && !hasProblem {
                        CleanupAllCleanView(
                            accent: accent,
                            subtitle: anyData ? "Silinecek geçmiş ya da çerez bulunamadı." : "Desteklenen bir tarayıcı bulunamadı.",
                            primaryTitle: "Yeniden tara", onPrimary: { vm.scan() }, compact: true)
                    } else {
                        CleanupResultHeader(bytes: found, caption: "tarayıcı izi bulundu", accent: accent,
                                            notes: ["Silmek istediklerinizi seçin. Yer imleri ve kayıtlı parolalar listelenmez, silinmez."])
                    }
                    ForEach(shown, id: \.0) { browser, scan in
                        PrivacyBrowserGroup(vm: vm, browser: browser, scan: scan, isBusy: isBusyNow,
                                            onHelp: { helpReason = $0 })
                    }
                    if let freed, !freed.skipped.isEmpty { skippedCard(freed.skipped) }
                }
                .padding(.bottom, 10)
            }
            .scrollIndicators(.never)
            if found > 0 { actionBar.padding(.top, 8).padding(.bottom, 4) }
        }
    }

    private var isBusyNow: Bool { vm.isBusy || isRunning }

    private var actionBar: some View {
        let totals = PrivacyBrowser.allCases.map { vm.selectedTotals($0) }
        let count = totals.reduce(0) { $0 + $1.count }
        let bytes = totals.reduce(UInt64(0)) { $0 + $1.bytes }
        return CleanupActionBar(
            countText: count == 0 ? "Seçili veri yok" : "\(count) dosya seçili", bytes: bytes, mode: $vm.deleteMode,
            isEnabled: count > 0 && !isBusyNow, isBusy: vm.phase == .deleting || isRunning, accent: accent
        ) {
            requestConfirmation()
        } leading: {
            Button { vm.scan() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).disabled(isBusyNow).help("Yeniden tara")
        }
    }

    private func skippedCard(_ skipped: [CleanupResult]) -> some View {
        CleanupResultCard(
            symbol: "exclamationmark.circle.fill", title: "\(skipped.count) dosya atlandı",
            subtitle: "Son temizlikte silinmeyen dosyalar.", accent: .privacyWarning,
            isExpanded: $showSkipped
        ) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(skipped, id: \.candidate.id) { r in
                    HStack {
                        Text(r.candidate.displayName).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(r.reasonText ?? "").foregroundStyle(.secondary).lineLimit(1)
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: Silme zinciri

    /// Seçili her tarayıcı için bekleyen silme kurulur (açık tarayıcıyı model reddeder ve kartı "açık" yapar); tek onay hepsini kapsar.
    private func requestConfirmation() {
        let pendings = PrivacyBrowser.allCases.compactMap { browser -> PendingPrivacyDeletion? in
            vm.selectedTotals(browser).count > 0 ? vm.requestDeletion(of: browser) : nil
        }
        guard !pendings.isEmpty else { return }
        confirm = PrivacyConfirmRequest(pendings: pendings)
    }

    private func start(_ request: PrivacyConfirmRequest, mode: DeleteMode) {
        guard !isRunning else { return }
        isRunning = true
        runTask = Task { @MainActor in
            let results = await PrivacyDeletionRun.run(request.pendings, mode: mode, on: vm)
            isRunning = false
            runTask = nil
            guard !Task.isCancelled else { return }
            let summary = PrivacyFreed(results: results, mode: mode)
            freed = summary
            if summary.count > 0 { showDone = true }
        }
    }

    // MARK: 4. Bitti

    private var done: some View {
        let summary = freed ?? PrivacyFreed(count: 0, bytes: 0, skipped: [], mode: .trash)
        let trashed = summary.mode == .trash
        var detail = "\(summary.count) dosya \(trashed ? "taşındı" : "kalıcı olarak silindi")"
        detail += summary.skipped.isEmpty ? "." : ", \(summary.skipped.count) atlandı."
        detail += " Yer imleri ve kayıtlı parolalara dokunulmadı."
        if trashed { detail += " Disk alanı, Çöp Sepeti'ni boşaltınca açılır." }
        return CleanupDoneView(
            accent: accent, bytes: summary.bytes, headline: trashed ? "Çöp Sepeti'ne taşındı" : "boşaltıldı", detail: detail,
            secondaryTitle: "Sonuçlara dön", onSecondary: { showDone = false }
        ) {
            showDone = false
            vm.scan()
        }
    }
}
