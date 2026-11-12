import AppKit
import SwiftUI

/// Gizlilik: Chrome, Edge ve Safari için geçmiş ve çerezleri ayrı ayrı temizler. Yalnızca Tara'ya basınca okur;
/// açık tarayıcı reddedilir. Silme Çöp Sepeti'ne gider (kalıcı silme işlem başına, iki onayla).
struct PrivacySection: View {
    @State private var vm = BrowserPrivacyViewModel()
    @State private var pending: PendingPrivacyDeletion?
    @State private var helpReason: AccessReason?
    @State private var showDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                topRow
                Text(vm.deleteMode == .trash
                     ? "Silinen dosyalar Çöp Sepeti'ne taşınır. Yer, Çöp Sepeti boşaltılınca açılır."
                     : "Kalıcı silme seçili: dosyalar Çöp Sepeti'ne gitmez, geri alınamaz. İşlemden sonra Çöp'e taşımaya döner.")
                    .font(.caption).foregroundStyle(vm.deleteMode == .trash ? Color.secondary : Color.red)
                if let result = vm.lastResult { banner(result) }
                if !vm.hasScanned {
                    ResourceEmptyNote(text: "Tarayıcı geçmişi ve çerezlerini görmek için Tara'ya basın. Tarama yalnızca siz isteyince yapılır. Yer imleri ve kayıtlı parolalar listelenmez, silinmez.")
                }
                ForEach(PrivacyBrowser.allCases) { browser in
                    if let scan = vm.scan(for: browser) {
                        BrowserPrivacyCard(vm: vm, browser: browser, scan: scan,
                                           onHelp: { helpReason = $0 },
                                           onDelete: { pending = vm.requestDeletion(of: browser) })
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .onAppear { vm.access.resume() }
        .onDisappear {
            vm.cancel()
            vm.access.stop()
            vm.resetMode()
        }
        .sheet(item: $pending) { request in
            PrivacyConfirmSheet(request: request, mode: vm.deleteMode, home: vm.home, onConfirm: { mode in
                pending = nil
                vm.perform(request, mode: mode)
            }, onCancel: {
                pending = nil
                vm.resetMode()
            })
        }
        .sheet(item: $helpReason) { reason in
            AccessHelpSheet(reason: reason, monitor: vm.access) { helpReason = nil }
        }
    }

    private var topRow: some View {
        HStack(spacing: 10) {
            if vm.phase == .scanning {
                ProgressView().controlSize(.small)
                Text("Taranıyor…").foregroundStyle(.secondary)
                Button("Durdur") { vm.cancel() }
            } else {
                Button("Tara", systemImage: "magnifyingglass") { vm.scan() }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isBusy)
            }
            Spacer(minLength: 8)
            if vm.phase == .deleting { ProgressView().controlSize(.small) }
            Picker("Silme yöntemi", selection: $vm.deleteMode) {
                Text("Çöp'e taşı").tag(DeleteMode.trash)
                Text("Kalıcı sil").tag(DeleteMode.permanent)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(vm.isBusy)
            .help("Kalıcı silme yalnızca bu işlem içindir; sonra Çöp'e taşımaya döner.")
        }
    }

    private func banner(_ results: [CleanupResult]) -> some View {
        let moved = results.filter(\.isRemoved)
        let skipped = results.filter { !$0.isRemoved }
        let bytes = moved.reduce(UInt64(0)) { $0 + $1.candidate.bytes }
        let verb = vm.lastMode == .trash ? "Çöp Sepeti'ne taşındı" : "kalıcı olarak silindi"
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("\(moved.count) dosya \(verb) (\(Format.bytes(bytes))). \(skipped.count) atlandı.", systemImage: "checkmark.circle")
                Spacer()
                if !skipped.isEmpty {
                    Button(showDetails ? "Gizle" : "Ayrıntılar") { showDetails.toggle() }.buttonStyle(.borderless)
                }
            }
            if showDetails {
                ForEach(skipped, id: \.candidate.id) { r in
                    HStack {
                        Text(r.candidate.displayName).lineLimit(1).truncationMode(.middle)
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

/// Tarayıcı başına kart: durum (açık / erişim yok / bulunamadı) ya da geçmiş ve çerezler için ayrı seçim.
private struct BrowserPrivacyCard: View {
    let vm: BrowserPrivacyViewModel
    let browser: PrivacyBrowser
    let scan: BrowserPrivacyScan
    let onHelp: (AccessReason) -> Void
    let onDelete: () -> Void

    var body: some View {
        ResourceCard(title: browser.title, systemImage: browser.symbol) {
            switch scan.state {
            case .running:
                HStack(spacing: 8) {
                    Label(BrowserPrivacyRules.closeFirstText(browser), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Spacer(minLength: 8)
                    Button("Tekrar tara") { vm.scan() }.disabled(vm.isBusy)
                }
                Text("\(browser.shortName) açıkken dosyaları kilitli olabilir; bu yüzden hiçbir şey listelenmez ve silinmez.")
                    .font(.caption).foregroundStyle(.secondary)
            case .noAccess:
                HStack(spacing: 8) {
                    Label(AccessReason.fullDiskAccess.title, systemImage: "lock").foregroundStyle(.orange)
                    if let button = AccessReason.fullDiskAccess.buttonTitle {
                        Button(button) { vm.access.openSettings(for: .fullDiskAccess) }
                    }
                    Button("Nasıl?") { onHelp(.fullDiskAccess) }.buttonStyle(.borderless)
                }
            case .notFound:
                ResourceEmptyNote(text: "Bulunamadı.")
            case .scanned:
                scannedContent
            }
        }
    }

    @ViewBuilder
    private var scannedContent: some View {
        if scan.files.isEmpty {
            ResourceEmptyNote(text: "Silinecek geçmiş ya da çerez yok.")
        } else {
            Text(profileText).font(.caption).foregroundStyle(.secondary)
            ForEach(PrivacyDataKind.allCases) { kind in
                kindRow(kind)
            }
            let totals = vm.selectedTotals(browser)
            HStack {
                Text(totals.count == 0 ? "Seçili veri yok" : "Seçili: \(totals.count) dosya · \(Format.bytes(totals.bytes))")
                    .monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button(vm.deleteMode == .trash ? "Çöp Sepeti'ne taşı…" : "Kalıcı olarak sil…",
                       systemImage: vm.deleteMode == .trash ? "trash" : "xmark.bin") { onDelete() }
                    .tint(vm.deleteMode == .trash ? nil : .red)
                    .disabled(totals.count == 0 || vm.isBusy)
            }
        }
    }

    private var profileText: String {
        browser == .safari ? "Safari" : "\(scan.profileCount) profil"
    }

    private func kindRow(_ kind: PrivacyDataKind) -> some View {
        let available = scan.has(kind)
        let isOn = vm.selected(browser).contains(kind)
        return HStack(spacing: 8) {
            Button { vm.toggle(kind, in: browser) } label: {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
            }
            .buttonStyle(.borderless)
            .disabled(!available)
            .accessibilityLabel("\(kind.title): \(browser.shortName)")
            VStack(alignment: .leading, spacing: 0) {
                Text(kind.title)
                Text(kind == .history ? "Ziyaret edilen sayfalar, en çok gidilen siteler" : "Tüm sitelerden çıkış yapılır")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(available ? Format.bytes(scan.bytes(of: kind)) : "Yok").monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.callout)
        .contentShape(.rect)
    }
}

/// Onay: önce kaybedilecekler açıkça yazılır, ardından ortak DeleteConfirmation akışı (Çöp tek adım, kalıcı iki onay).
private struct PrivacyConfirmSheet: View {
    let request: PendingPrivacyDeletion
    let mode: DeleteMode
    let home: String
    let onConfirm: (DeleteMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(request.browser.title): bunlar kaybolacak", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(.orange)
                ForEach(BrowserPrivacyRules.lossLines(browser: request.browser, kinds: request.kinds), id: \.self) { line in
                    Text("• " + line).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                Text("Yer imleri ve kayıtlı parolalar etkilenmez.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.10), in: .rect(cornerRadius: 10))
            .padding([.horizontal, .top], 20)
            DeleteConfirmation(
                summary: DeleteSummary(count: request.candidates.count, bytes: request.bytes, mode: mode,
                                       sample: request.candidates.prefix(5).map { FolderWatchList.displayPath($0.path, home: home) }),
                onConfirm: onConfirm, onCancel: onCancel
            )
        }
    }
}
