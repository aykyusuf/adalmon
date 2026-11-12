import SwiftUI

/// Onay: önce kaybedilecekler tarayıcı başına açıkça yazılır, ardından ortak DeleteConfirmation akışı
/// (Çöp tek adım, kalıcı iki onay). Tek onay tüm tarayıcıları kapsar.
struct PrivacyConfirmRequest: Identifiable {
    let id = UUID()
    let pendings: [PendingPrivacyDeletion]

    var count: Int { pendings.reduce(0) { $0 + $1.candidates.count } }
    var bytes: UInt64 { pendings.reduce(UInt64(0)) { $0 + $1.bytes } }
}

struct PrivacyConfirmSheet: View {
    let request: PrivacyConfirmRequest
    let mode: DeleteMode
    let home: String
    let onConfirm: (DeleteMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(request.pendings) { pending in
                    VStack(alignment: .leading, spacing: 4) {
                        Label("\(pending.browser.title): bunlar kaybolacak", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline).foregroundStyle(.orange)
                        ForEach(BrowserPrivacyRules.lossLines(browser: pending.browser, kinds: pending.kinds), id: \.self) { line in
                            Text("• " + line).font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text("Yer imleri ve kayıtlı parolalar etkilenmez.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.10), in: .rect(cornerRadius: 10))
            .padding([.horizontal, .top], 20)
            DeleteConfirmation(
                summary: DeleteSummary(count: request.count, bytes: request.bytes, mode: mode,
                                       sample: request.pendings.flatMap(\.candidates).prefix(5)
                                           .map { FolderWatchList.displayPath($0.path, home: home) }),
                onConfirm: onConfirm, onCancel: onCancel
            )
        }
    }
}
