import SwiftUI

/// Onay penceresinde gösterilen özet.
struct DeleteSummary: Equatable {
    var count: Int
    var bytes: UInt64
    var mode: DeleteMode
    /// İlk birkaç öğenin görünen yolu.
    var sample: [String] = []

    var headline: String {
        let what = "\(count) öğe (\(Format.bytes(bytes)))"
        return mode == .trash ? "\(what) Çöp Sepeti'ne taşınsın mı?" : "\(what) kalıcı olarak silinsin mi?"
    }

    var undoNote: String { mode == .trash ? "Çöp Sepeti'nden geri alınabilir." : "GERİ ALINAMAZ. Öğeler Çöp Sepeti'ne gitmez." }
}

/// Onay adımları: Çöp'e taşımada tek adım; kalıcı silmede ikinci, kırmızı bir adım ve "anlıyorum" kutusu.
struct DeleteConfirmationFlow: Equatable {
    enum Step: Equatable { case summary, permanentConfirm }

    let mode: DeleteMode
    var step: Step = .summary
    var acknowledged = false

    /// Bu adımdaki ana düğme işlemi başlatabilir mi.
    var canConfirm: Bool {
        switch (mode, step) {
        case (.trash, .summary): true
        case (.permanent, .summary): false
        case (_, .permanentConfirm): mode == .permanent && acknowledged
        }
    }

    /// Ana düğmeye basıldı: işlem başlamalıysa true; kalıcı silmede ilk basış ikinci adıma geçirir.
    mutating func primaryPressed() -> Bool {
        switch (mode, step) {
        case (.trash, .summary): return true
        case (.permanent, .summary):
            step = .permanentConfirm
            acknowledged = false
            return false
        case (_, .permanentConfirm): return canConfirm
        }
    }
}

/// Silme onayı (sayfa olarak sunulur). Kalıcı silmede Return hiçbir adımda onaylamaz; Esc her adımda vazgeçer.
struct DeleteConfirmation: View {
    let summary: DeleteSummary
    let onConfirm: (DeleteMode) -> Void
    let onCancel: () -> Void
    @State private var flow: DeleteConfirmationFlow

    init(summary: DeleteSummary, onConfirm: @escaping (DeleteMode) -> Void, onCancel: @escaping () -> Void) {
        self.summary = summary
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _flow = State(initialValue: DeleteConfirmationFlow(mode: summary.mode))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if flow.step == .summary { summaryStep } else { permanentStep }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var summaryStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(summary.headline, systemImage: summary.mode == .trash ? "trash" : "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(summary.mode == .trash ? Color.primary : Color.red)
            if !summary.sample.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(summary.sample, id: \.self) { Text($0).lineLimit(1).truncationMode(.middle) }
                    if summary.count > summary.sample.count {
                        Text("…ve \(summary.count - summary.sample.count) öğe daha").foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }
            Text(summary.undoNote)
                .font(summary.mode == .trash ? .callout : .callout.bold())
                .foregroundStyle(summary.mode == .trash ? Color.secondary : Color.red)
            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                if summary.mode == .trash {
                    Button("Çöp Sepeti'ne taşı") { press() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Devam…", role: .destructive) { press() }
                }
            }
        }
    }

    private var permanentStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Son onay: kalıcı silme", systemImage: "exclamationmark.octagon.fill")
                .font(.headline).foregroundStyle(.red)
            Text("\(summary.count) öğe · \(Format.bytes(summary.bytes)) kalıcı olarak silinecek.")
                .font(.title3.bold()).monospacedDigit()
            Text("Bu işlem geri alınamaz. Öğeler Çöp Sepeti'ne gitmez, oradan da geri getirilemez.")
                .foregroundStyle(.red)
            Toggle("Kalıcı olarak silineceğini anlıyorum", isOn: $flow.acknowledged)
                .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Kalıcı olarak sil", role: .destructive) { press() }
                    .tint(.red)
                    .buttonStyle(.borderedProminent)
                    .disabled(!flow.canConfirm)
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.08), in: .rect(cornerRadius: 10))
    }

    private func press() {
        if flow.primaryPressed() { onConfirm(summary.mode) }
    }
}
