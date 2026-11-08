import Foundation

/// Dış komut çalıştırıcı (enjekte edilir: testlerde sahte; gerçek `claude` testte ASLA çalışmaz).
protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async -> CommandResult
}

/// Gerçek çalıştırıcı: kabuk yok, argüman dizisi, ana iş parçacığı dışında, zaman aşımıyla. `claude` bir `node` betiği olabilir;
/// bu yüzden PATH yaygın konumlarla genişletilir.
struct LiveCommandRunner: CommandRunning {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.runBlocking(executable, arguments, timeout: timeout))
            }
        }
    }

    private static func runBlocking(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", environment["PATH"] ?? ""]
            .filter { !$0.isEmpty }.joined(separator: ":")
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return CommandResult(status: -1, output: error.localizedDescription) }
        nonisolated(unsafe) let running = process
        let timedOut = TimedOutFlag()
        let killer = DispatchWorkItem { if running.isRunning { timedOut.set(); running.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        let text = String(decoding: data, as: UTF8.self)
        return CommandResult(status: timedOut.value ? -2 : process.terminationStatus, output: text)
    }

    private final class TimedOutFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        func set() { lock.lock(); flag = true; lock.unlock() }
        var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    }
}

/// Plugin'in `claude` CLI ile kurulması / kaldırılması / durum kontrolü. Kullanıcının `~/.claude/settings.json` dosyasına
/// Adalmon doğrudan yazmaz; kayıtları yalnızca `claude plugin ...` komutları yapar (kullanıcının düğme tıklamasıyla).
struct AgentPluginInstaller: Sendable {
    enum InstallError: LocalizedError, Equatable {
        case cliNotFound
        case writeFailed(String)
        case commandFailed(step: String, output: String)
        case timedOut(step: String)

        var errorDescription: String? {
            switch self {
            case .cliNotFound:
                "`claude` komutu bulunamadı. Claude Code'u kurun ya da aşağıdaki komutları Terminal'de elle çalıştırın."
            case .writeFailed(let reason): "Plugin dosyaları yazılamadı: \(reason)"
            case .commandFailed(let step, let output): "\(step) başarısız: \(Self.trimmed(output))"
            case .timedOut(let step): "\(step) zaman aşımına uğradı."
            }
        }

        private static func trimmed(_ text: String) -> String { String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)) }
    }

    enum PluginStatus: Equatable, Sendable {
        case installed, notInstalled, unknown
    }

    static let commandTimeout: TimeInterval = 60
    static let listTimeout: TimeInterval = 20

    var generator: AgentPluginGenerator
    var runner: any CommandRunning
    /// `claude` çalıştırılabilirinin yolu; nil = bulunamadı.
    var cliPath: @Sendable () -> String?

    init(generator: AgentPluginGenerator = AgentPluginGenerator(), runner: any CommandRunning = LiveCommandRunner(),
         cliPath: @escaping @Sendable () -> String? = { AgentPluginInstaller.findCLI() }) {
        self.generator = generator
        self.runner = runner
        self.cliPath = cliPath
    }

    static func findCLI(fileManager: FileManager = .default, pathVariable: String? = ProcessInfo.processInfo.environment["PATH"]) -> String? {
        let home = fileManager.homeDirectoryForCurrentUser.path
        var candidates = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        candidates += (pathVariable ?? "").split(separator: ":").map { "\($0)/claude" }
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    // MARK: Elle çalıştırılacak komutlar (CLI bulunamazsa gösterilir)

    var manualInstallCommands: [String] {
        ["claude plugin marketplace add \"\(generator.root.path)\"", "claude plugin install \(AgentPluginGenerator.pluginID)"]
    }

    var manualUninstallCommands: [String] {
        ["claude plugin uninstall \(AgentPluginGenerator.pluginID)", "claude plugin marketplace remove \(AgentPluginGenerator.marketplaceName)"]
    }

    // MARK: Eylemler

    /// Dosyaları yazar, marketplace'i ekler, plugin'i kurar. Yazma CLI bulunamasa da yapılır (elle komutlar çalışsın).
    func install(port: UInt16, token: String) async throws {
        do { try generator.write(port: port, token: token) } catch { throw InstallError.writeFailed(error.localizedDescription) }
        guard let cli = cliPath() else { throw InstallError.cliNotFound }
        // Marketplace zaten ekliyse `add` hata verebilir; kurulum denemesi yine de yapılır.
        let add = await runner.run(cli, ["plugin", "marketplace", "add", generator.root.path], timeout: Self.commandTimeout)
        if add.status == -2 { throw InstallError.timedOut(step: "Marketplace ekleme") }
        let install = await runner.run(cli, ["plugin", "install", AgentPluginGenerator.pluginID], timeout: Self.commandTimeout)
        if install.status == -2 { throw InstallError.timedOut(step: "Plugin kurulumu") }
        guard install.succeeded else {
            throw InstallError.commandFailed(step: "Plugin kurulumu", output: add.succeeded ? install.output : add.output + "\n" + install.output)
        }
    }

    /// Plugin'i ve marketplace kaydını kaldırır, sonra yerel dosyaları siler.
    func uninstall() async throws {
        guard let cli = cliPath() else { throw InstallError.cliNotFound }
        let plugin = await runner.run(cli, ["plugin", "uninstall", AgentPluginGenerator.pluginID], timeout: Self.commandTimeout)
        if plugin.status == -2 { throw InstallError.timedOut(step: "Plugin kaldırma") }
        let market = await runner.run(cli, ["plugin", "marketplace", "remove", AgentPluginGenerator.marketplaceName], timeout: Self.commandTimeout)
        if market.status == -2 { throw InstallError.timedOut(step: "Marketplace kaldırma") }
        // Zaten kurulu değilse CLI hata verir; kalıntı kalmadığını doğrula.
        if await status() == .installed {
            throw InstallError.commandFailed(step: "Plugin kaldırma", output: plugin.output)
        }
        generator.removeFiles()
    }

    /// `claude plugin list` çıktısında plugin kimliği var mı.
    func status() async -> PluginStatus {
        guard let cli = cliPath() else { return .unknown }
        let result = await runner.run(cli, ["plugin", "list"], timeout: Self.listTimeout)
        guard result.succeeded else { return .unknown }
        return Self.isInstalled(listOutput: result.output) ? .installed : .notInstalled
    }

    static func isInstalled(listOutput: String) -> Bool { listOutput.contains(AgentPluginGenerator.pluginID) }
}
