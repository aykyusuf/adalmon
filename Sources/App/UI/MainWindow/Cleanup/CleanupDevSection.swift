import SwiftUI

/// Geliştirici bölümü: global önbellekler (Xcode, npm, Gradle, Cargo, CocoaPods…), proje artıkları ve araç kartları (brew, Docker).
struct CleanupDevSection: View {
    var body: some View { CleanupView(group: .dev) }
}

/// Araç kartları: Adalmon aracın kendi komutunu önizlemeyle çalıştırır. Sonuç kalıcıdır (Çöp'e gitmez); tek onay istenir.
struct ToolCommandCards: View {
    var body: some View {
        ForEach(CleanupTool.allCases) { tool in
            ToolCommandCard(tool: tool)
        }
    }
}

private struct ToolCommandCard: View {
    @State private var model: ToolCommandModel
    @State private var confirming = false

    init(tool: CleanupTool) {
        _model = State(initialValue: ToolCommandModel(tool: tool))
    }

    var body: some View {
        ResourceCard(title: model.tool.title, systemImage: model.tool.systemImage) {
            Text(model.tool.explanation).font(.callout).foregroundStyle(.secondary)
            Label("Kalıcı; aracın kendi komutu. Çöp Sepeti'ne gitmez, geri alınamaz.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
            if !model.isAvailable {
                ResourceEmptyNote(text: "\(model.tool.title) bu Mac'te bulunamadı; kart devre dışı.")
            }
            HStack(spacing: 8) {
                Button("Önizle", systemImage: "eye") { Task { await model.loadPreview() } }
                    .disabled(!model.isAvailable || model.isBusy)
                Button("Çalıştır…", systemImage: "play") { confirming = true }
                    .disabled(!model.canRun || model.isBusy)
                if model.isBusy { ProgressView().controlSize(.small) }
            }
            result
        }
        .onAppear { model.locate() }
        .confirmationDialog(
            "\(model.tool.commandText()) çalıştırılsın mı?", isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Çalıştır (kalıcı)", role: .destructive) { Task { await model.run() } }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Komut aracın kendisi tarafından uygulanır. Sonuç kalıcıdır ve geri alınamaz.")
        }
    }

    @ViewBuilder
    private var result: some View {
        switch model.phase {
        case .idle, .working:
            EmptyView()
        case .preview(let preview):
            if preview.nothingToClean {
                ResourceEmptyNote(text: "Temizlenecek bir şey yok.")
            } else {
                if let estimate = preview.estimate {
                    Text("Tahmini kazanç: \(estimate)").font(.callout.bold()).monospacedDigit()
                }
                outputBox(preview.lines.joined(separator: "\n"))
            }
        case .done(let text):
            Label("Tamamlandı.", systemImage: "checkmark.circle").foregroundStyle(.green)
            if !text.isEmpty { outputBox(text) }
        case .failed(let text):
            Label(text, systemImage: "xmark.octagon").font(.callout).foregroundStyle(.red)
        }
    }

    private func outputBox(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
    }
}
