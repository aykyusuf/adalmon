import AppKit
import SwiftUI

/// Kaldırıcı: uygulamalar + artıkları, ayrı sekmede yetim dosyalar. Tarama yalnızca "Tara"ya basınca olur.
struct UninstallerSection: View {
    @State private var model = UninstallerModel()
    @State private var confirm: ConfirmState?
    @State private var helpReason: AccessReason?
    @State private var showDetails = false

    init(model: UninstallerModel = UninstallerModel()) {
        _model = State(initialValue: model)
    }

    private struct ConfirmState: Identifiable {
        let id = UUID()
        var summary: DeleteSummary
        var pending: PendingRemoval
    }

    var body: some View {
        VStack(spacing: 0) {
            topRow.padding(.bottom, 10)
            VStack(spacing: 10) {
                if let issue = model.accessIssue { accessBanner(issue) }
                if let report = model.report { resultBanner(report) }
            }
            .padding(.bottom, model.accessIssue != nil || model.report != nil ? 10 : 0)
            content
            Divider()
            bottomBar.padding(.vertical, 10)
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

    // MARK: Üst satır

    private var topRow: some View {
        HStack(spacing: 10) {
            Picker("Bölüm", selection: $model.tab) {
                ForEach(UninstallerModel.Tab.allCases) { tab in
                    Text(tab == .orphans && !model.orphans.isEmpty ? "\(tab.title) (\(model.orphans.count))" : tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if case .scanning(let done, let total) = model.phase {
                ProgressView().controlSize(.small)
                Text(total > 0 ? "Taranıyor: \(done)/\(total)" : "Taranıyor…").foregroundStyle(.secondary).monospacedDigit()
                Button("Durdur") { model.cancel() }
            } else {
                Button(model.hasScanned ? "Yeniden tara" : "Tara", systemImage: "magnifyingglass") { model.scan() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
            }
            Spacer(minLength: 8)
            if model.hasScanned {
                if model.tab == .apps {
                    Picker("Sırala", selection: $model.sort) {
                        ForEach(UninstallerModel.Sort.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .help("Sıralama")
                }
                TextField("Ara", text: $model.search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }
        }
    }

    // MARK: İçerik

    @ViewBuilder
    private var content: some View {
        if !model.hasScanned {
            VStack {
                ContentUnavailableView {
                    Label("Uygulama kaldırıcı", systemImage: "app.badge.checkmark")
                } description: {
                    Text(model.isBusy ? "Taranıyor…" : "Uygulamaları ve artıklarını görmek için Tara'ya basın. Tarama yalnızca siz isteyince yapılır.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
        } else if model.tab == .apps {
            HStack(spacing: 0) {
                AppListView(model: model).frame(minWidth: 260, idealWidth: 330, maxWidth: 380)
                Divider()
                AppLeftoverList(model: model).frame(maxWidth: .infinity)
            }
            .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 12))
            .clipShape(.rect(cornerRadius: 12))
        } else {
            OrphanListView(model: model)
                .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 12))
        }
    }

    // MARK: Bantlar

    private func accessBanner(_ reason: AccessReason) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
        }
        .padding(12)
        .background(Color.orange.opacity(0.10), in: .rect(cornerRadius: 12))
    }

    private func resultBanner(_ report: AppRemovalReport) -> some View {
        let done = report.results.filter(\.isRemoved)
        let others = report.results.filter { !$0.isRemoved }
        let bytes = done.reduce(UInt64(0)) { $0 + $1.candidate.bytes }
        let verb = model.lastMode == .trash ? "taşındı" : "kalıcı olarak silindi"
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("\(done.count) öğe \(verb) (\(Format.bytes(bytes))). \(others.count) atlandı.", systemImage: "checkmark.circle")
                Spacer()
                if !others.isEmpty {
                    Button(showDetails ? "Gizle" : "Ayrıntılar") { showDetails.toggle() }.buttonStyle(.borderless)
                }
                Button { model.dismissReport() } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless).help("Kapat")
            }
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
        .background((others.isEmpty ? Color.green : Color.yellow).opacity(0.10), in: .rect(cornerRadius: 12))
    }

    // MARK: Alt çubuk

    private var bottomBar: some View {
        let pending = model.pending
        let count = pending?.candidates.count ?? 0
        let bytes = pending?.bytes ?? 0
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Seçili: \(count) öğe · \(Format.bytes(bytes))").monospacedDigit().foregroundStyle(.secondary)
                if model.deleteMode == .permanent {
                    Text("Başlangıç ajanı (LaunchAgent) dosyaları kalıcı modda bile Çöp'e taşınır.").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.phase == .deleting { ProgressView().controlSize(.small) }
            Picker("Silme yöntemi", selection: $model.deleteMode) {
                Text("Çöp'e taşı").tag(DeleteMode.trash)
                Text("Kalıcı sil").tag(DeleteMode.permanent)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(model.isBusy)
            .help("Kalıcı silme yalnızca bu işlem içindir; sonra Çöp'e taşımaya döner.")
            Button(model.deleteMode == .trash ? "Kaldır…" : "Kalıcı olarak kaldır…",
                   systemImage: model.deleteMode == .trash ? "trash" : "xmark.bin") {
                guard let pending else { return }
                confirm = ConfirmState(summary: DeleteSummary(
                    count: count, bytes: bytes, mode: model.deleteMode,
                    sample: pending.candidates.prefix(5).map { FolderWatchList.displayPath($0.path, home: model.home) }
                ), pending: pending)
            }
            .tint(model.deleteMode == .trash ? nil : .red)
            .disabled(pending == nil || model.isBusy || model.selectedAppRunning)
            .help(model.selectedAppRunning ? "Uygulama açık: önce kapatın" : "")
        }
    }
}
