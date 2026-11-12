import SwiftUI

/// Geliştirici bölümü: global önbellekler (Xcode, npm, Gradle, Cargo, CocoaPods…), proje artıkları ve araç komutları (brew, Docker).
/// Karşılama → tarama → sonuç → bitti sihirbazı `CleanupView`dadır; araç komutları sonuç ekranında ayrı bir blok olarak durur.
struct CleanupDevSection: View {
    var body: some View { CleanupView(group: .dev) }
}

/// "Araç komutları" bloğu: Adalmon aracın kendi komutunu önizlemeyle çalıştırır (önizle → onayla).
/// Sonuç kalıcıdır (Çöp'e gitmez, yukarıdaki seçimden ve silme yönteminden bağımsızdır); tek onay istenir.
struct ToolCommandCards: View {
    let accent: CleanupAccent
    @State private var models: [ToolCommandModel]

    init(accent: CleanupAccent = .dev, models: [ToolCommandModel]? = nil) {
        self.accent = accent
        _models = State(initialValue: models ?? CleanupTool.allCases.map { ToolCommandModel(tool: $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Araç komutları").font(.headline)
                Text("Aracın kendi temizlik komutunu çalıştırır: önce önizleyin, sonra onaylayın. Sonuç kalıcıdır, Çöp Sepeti'ne gitmez, geri alınamaz ve yukarıdaki seçimden bağımsızdır.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8).padding(.horizontal, 4)
            ForEach(models, id: \.tool) { model in
                ToolCommandCard(model: model, accent: accent)
            }
        }
    }
}

private struct ToolCommandCard: View {
    let model: ToolCommandModel
    let accent: CleanupAccent
    @State private var confirming = false
    @State private var expanded = false

    var body: some View {
        CleanupResultCard(
            symbol: model.tool.systemImage, title: model.tool.title, subtitle: subtitle, sizeText: estimate, accent: accent,
            isExpanded: $expanded, accessory: { actions }, detail: { detail }
        )
        .onAppear { model.locate() }
        .onChange(of: model.phase) { _, new in
            switch new {
            case .preview, .done, .failed: expanded = true
            case .idle, .working: break
            }
        }
        .confirmationDialog(
            "\(model.tool.commandText()) çalıştırılsın mı?", isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Çalıştır (kalıcı)", role: .destructive) { Task { await model.run() } }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Komut aracın kendisi tarafından uygulanır. Sonuç kalıcıdır ve geri alınamaz.")
        }
    }

    private var subtitle: String {
        if !model.isAvailable, model.phase == .idle || isFailedUnavailable { return "\(model.tool.title) bu Mac'te bulunamadı; kart devre dışı." }
        switch model.phase {
        case .idle: return model.tool.explanation
        case .working: return "Çalışıyor…"
        case .preview(let preview):
            if preview.nothingToClean { return "Temizlenecek bir şey yok." }
            return "Önizleme hazır; çıktıyı inceleyin, sonra çalıştırın."
        case .done: return "Tamamlandı."
        case .failed(let text): return text.split(separator: "\n").first.map(String.init) ?? text
        }
    }

    private var isFailedUnavailable: Bool { false }

    private var estimate: String? {
        if case .preview(let preview) = model.phase, !preview.nothingToClean { return preview.estimate.map { "≈ \($0)" } }
        return nil
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            if model.isBusy { ProgressView().controlSize(.small) }
            Button("Önizle", systemImage: "eye") { Task { await model.loadPreview() } }
                .controlSize(.small)
                .disabled(!model.isAvailable || model.isBusy)
            if model.canRun {
                Button { confirming = true } label: { Label("Çalıştır…", systemImage: "play.fill") }
                    .buttonStyle(CleanupPrimaryButtonStyle(accent: .destructive, prominent: false))
                    .disabled(model.isBusy)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.tool.explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Label("Kalıcı; aracın kendi komutu. Çöp Sepeti'ne gitmez, geri alınamaz.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
            switch model.phase {
            case .idle, .working:
                EmptyView()
            case .preview(let preview):
                if let estimate = preview.estimate {
                    Text("Tahmini kazanç: \(estimate)").font(.callout.bold()).monospacedDigit()
                }
                if !preview.nothingToClean { outputBox(preview.lines.joined(separator: "\n")) }
            case .done(let text):
                Label("Tamamlandı.", systemImage: "checkmark.circle").foregroundStyle(.green)
                if !text.isEmpty { outputBox(text) }
            case .failed(let text):
                Label(text, systemImage: "xmark.octagon").font(.callout).foregroundStyle(.red)
            }
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
