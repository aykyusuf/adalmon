import Foundation

/// Aracın kendi temizlik komutunu çalıştıran araçlar. Bunlar `CleanupDeleter`dan GEÇMEZ: komutu aracın kendisi uygular ve sonuç kalıcıdır.
/// Adalmon yönetici (sudo) komutu çalıştırmaz; komut kullanıcı olarak, kabuk olmadan, süre sınırıyla çalışır.
enum CleanupTool: String, CaseIterable, Identifiable, Sendable {
    case brew, docker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brew: "Homebrew"
        case .docker: "Docker"
        }
    }

    var systemImage: String {
        switch self {
        case .brew: "mug"
        case .docker: "shippingbox.fill"
        }
    }

    /// Aracın aranacağı yerler (PATH'e güvenilmez: uygulama kabuk ortamıyla açılmaz).
    func candidatePaths(home: String) -> [String] {
        switch self {
        case .brew: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        case .docker: [
            "/usr/local/bin/docker", "/opt/homebrew/bin/docker", home + "/.docker/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
        ]
        }
    }

    /// Önizleme komutu (hiçbir şey silmez).
    var previewArguments: [String] {
        switch self {
        case .brew: ["cleanup", "-n"]
        case .docker: ["system", "df"]
        }
    }

    /// Asıl temizlik komutu. Docker için yalnızca yapı önbelleği; imaj, kapsayıcı ve birim silinmez.
    var runArguments: [String] {
        switch self {
        case .brew: ["cleanup"]
        case .docker: ["builder", "prune", "-f"]
        }
    }

    /// Kullanıcıya gösterilen, çalıştırılacak komut.
    func commandText(executableName: String? = nil) -> String {
        "\(executableName ?? rawValue) \(runArguments.joined(separator: " "))"
    }

    var previewTimeout: TimeInterval { 60 }
    var runTimeout: TimeInterval { 300 }

    var explanation: String {
        switch self {
        case .brew: "Eski sürümleri ve indirme önbelleğini temizler (brew cleanup)."
        case .docker: "Yalnızca yapı (build) önbelleğini temizler (docker builder prune); imajlara, kapsayıcılara ve birimlere dokunmaz."
        }
    }
}

/// Komut çalıştırıcı: testlerde sahtesi verilir (gerçek brew/docker asla çalışmaz). Canlı hâli `CommandRunner`ı kullanır.
struct CleanupToolRunner: Sendable {
    var run: @Sendable (_ executable: String, _ arguments: [String], _ timeout: TimeInterval) async -> CommandResult
    var isExecutable: @Sendable (_ path: String) -> Bool

    static let live = CleanupToolRunner(
        run: { executable, arguments, timeout in await CommandRunner.run(executable, arguments, timeout: timeout) },
        isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
    )
}

/// Önizleme sonucu.
struct ToolPreview: Sendable, Equatable {
    /// Aracın çıktısından kısaltılmış satırlar.
    var lines: [String]
    /// Çıktıdan okunan tahmini kazanç (varsa).
    var estimate: String?
    /// Temizlenecek bir şey yok.
    var nothingToClean: Bool
}

enum ToolOutcome: Sendable, Equatable {
    /// Araç bulunamadı.
    case unavailable
    /// Araç çalıştı ama komut başarısız oldu (örn. Docker kapalı).
    case failed(String)
    case preview(ToolPreview)
    case done(String)
}

enum ToolCommands {
    static let maxLines = 14

    /// Aracın yolu; yoksa nil (düğme devre dışı).
    static func locate(_ tool: CleanupTool, home: String, runner: CleanupToolRunner = .live) -> String? {
        tool.candidatePaths(home: home).first { runner.isExecutable($0) }
    }

    /// Önizleme: `brew cleanup -n` / `docker system df`. Hiçbir şeyi silmez.
    static func preview(_ tool: CleanupTool, home: String, runner: CleanupToolRunner = .live) async -> ToolOutcome {
        guard let exe = locate(tool, home: home, runner: runner) else { return .unavailable }
        let result = await runner.run(exe, tool.previewArguments, tool.previewTimeout)
        guard result.succeeded else { return .failed(failureText(tool, result)) }
        return .preview(parsePreview(tool, output: result.output))
    }

    /// Asıl komut. Yalnızca kullanıcı onayından sonra çağrılır.
    static func execute(_ tool: CleanupTool, home: String, runner: CleanupToolRunner = .live) async -> ToolOutcome {
        guard let exe = locate(tool, home: home, runner: runner) else { return .unavailable }
        let result = await runner.run(exe, tool.runArguments, tool.runTimeout)
        guard result.succeeded else { return .failed(failureText(tool, result)) }
        return .done(summarize(result.output))
    }

    static func parsePreview(_ tool: CleanupTool, output: String) -> ToolPreview {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
        let shown = Array(lines.suffix(maxLines))
        switch tool {
        case .brew:
            // "==> This operation would free approximately 1.2GB of disk space."
            var estimate: String?
            if let line = lines.last(where: { $0.contains("free approximately") }),
               let range = line.range(of: "approximately ") {
                let rest = line[range.upperBound...]
                estimate = rest.split(separator: " ").first.map(String.init)
            }
            return ToolPreview(lines: shown, estimate: estimate, nothingToClean: lines.isEmpty)
        case .docker:
            // "Build Cache  12  0  1.4GB  1.4GB": son sütun geri kazanılabilir boyut ("(100%)" eki varsa atlanır).
            var estimate: String?
            if let row = lines.first(where: { $0.hasPrefix("Build Cache") }) {
                var cols = row.split(separator: " ").map(String.init)
                if cols.last?.hasPrefix("(") == true { cols.removeLast() }
                if cols.count >= 5 { estimate = cols.last }
            }
            return ToolPreview(lines: shown, estimate: estimate, nothingToClean: false)
        }
    }

    static func summarize(_ output: String) -> String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return lines.suffix(4).joined(separator: "\n")
    }

    private static func failureText(_ tool: CleanupTool, _ result: CommandResult) -> String {
        let text = summarize(result.output)
        if result.status == -1 { return "\(tool.title) başlatılamadı. \(text)" }
        if tool == .docker, text.lowercased().contains("daemon") { return "Docker çalışmıyor. Önce Docker Desktop'ı açın." }
        return text.isEmpty ? "\(tool.title) komutu başarısız oldu (çıkış kodu \(result.status))." : text
    }
}

/// Araç kartının durumu (tek onay: önizleme → onay → çalıştırma). Önizleme yalnızca kullanıcı isteyince çalışır.
@MainActor @Observable
final class ToolCommandModel {
    enum Phase: Equatable { case idle, working, preview(ToolPreview), done(String), failed(String) }

    let tool: CleanupTool
    let home: String
    /// `locate()` ile bulunur (görünüm oluşturulurken dosya sistemine bakılmaz).
    private(set) var executablePath: String?
    private(set) var phase: Phase = .idle
    @ObservationIgnored private let runner: CleanupToolRunner

    init(tool: CleanupTool, home: String = NSHomeDirectory(), runner: CleanupToolRunner = .live) {
        self.tool = tool
        self.home = home
        self.runner = runner
    }

    func locate() { executablePath = ToolCommands.locate(tool, home: home, runner: runner) }

    var isAvailable: Bool { executablePath != nil }
    var isBusy: Bool { phase == .working }

    var canRun: Bool {
        if case .preview(let p) = phase { return !p.nothingToClean }
        return false
    }

    func loadPreview() async {
        locate()
        guard isAvailable, !isBusy else { return }
        phase = .working
        apply(await ToolCommands.preview(tool, home: home, runner: runner))
    }

    /// Yalnızca önizleme gösterildikten sonra ve onaydan sonra çağrılır.
    func run() async {
        guard canRun, !isBusy else { return }
        phase = .working
        apply(await ToolCommands.execute(tool, home: home, runner: runner))
    }

    private func apply(_ outcome: ToolOutcome) {
        switch outcome {
        case .unavailable: phase = .failed("\(tool.title) bulunamadı.")
        case .failed(let text): phase = .failed(text)
        case .preview(let p): phase = .preview(p)
        case .done(let text): phase = .done(text)
        }
    }
}
