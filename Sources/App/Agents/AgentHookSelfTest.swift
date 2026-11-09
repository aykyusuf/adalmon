import Foundation

/// "Hattı test et": hook betiği → yerel dinleyici → izleyici zincirini ve çalışan Claude oturumlarının olay gönderip göndermediğini
/// denetler. Saf değerlendirme (`evaluate`) ile sistem erişimi (`fire`, `liveClaudePIDs`) ayrıdır; ilki birim testlidir.
enum AgentHookSelfTest {
    enum Verdict: Equatable, Sendable {
        case healthy
        /// Hat çalışıyor ama bazı oturumlar olay göndermiyor (eski plugin ile başlamış ya da plugin yüklenmemiş olabilir).
        case someSessionsSilent
        case listenerOff
        case pluginMissing
        /// Betik çalıştı ama olay izleyiciye ulaşmadı (port/token uyuşmazlığı, güvenlik duvarı, betik hatası).
        case eventLost
    }

    struct Result: Equatable, Sendable {
        var verdict: Verdict
        var latencyMs: Double?
        var liveClaudeProcesses: Int
        var reportingProcesses: Int
        var at: Date

        var silentProcesses: Int { max(0, liveClaudeProcesses - reportingProcesses) }

        var message: String {
            switch verdict {
            case .healthy:
                return "Hat sağlıklı" + (latencyMs.map { " (\(Int($0.rounded())) ms)" } ?? "") + ". \(reportingProcesses)/\(liveClaudeProcesses) Claude oturumu olay gönderiyor."
            case .someSessionsSilent:
                return "Hat sağlıklı, ama \(silentProcesses) Claude oturumu henüz olay göndermedi (yalnızca \(reportingProcesses)/\(liveClaudeProcesses)). Bu oturumlar plugin'den önce açılmış olabilir: o oturumda /reload-plugins çalıştırın ya da yeni oturum açın. Oturumda yeni bir iş yapılınca da görünür."
            case .listenerOff:
                return "Dinleyici kapalı: Ayarlar › Claude ajanları'ndan özelliği açın."
            case .pluginMissing:
                return "Hook betiği bulunamadı: Ayarlar › Claude ajanları'ndan plugin'i kurun."
            case .eventLost:
                return "Betik çalıştı ama olay Adalmon'a ulaşmadı (port/token uyuşmazlığı olabilir). Uygulamayı yeniden başlatmayı deneyin."
            }
        }

        var isHealthy: Bool { verdict == .healthy || verdict == .someSessionsSilent }
    }

    static func evaluate(listenerRunning: Bool, pluginInstalled: Bool, eventArrived: Bool, latencyMs: Double?, liveClaudeProcesses: Int,
                         reportingProcesses: Int, at: Date) -> Result {
        let verdict: Verdict
        if !listenerRunning { verdict = .listenerOff }
        else if !pluginInstalled { verdict = .pluginMissing }
        else if !eventArrived { verdict = .eventLost }
        else if liveClaudeProcesses > reportingProcesses { verdict = .someSessionsSilent }
        else { verdict = .healthy }
        return Result(verdict: verdict, latencyMs: latencyMs, liveClaudeProcesses: liveClaudeProcesses, reportingProcesses: reportingProcesses, at: at)
    }

    /// Gerçek hook betiğini yapay "AdalmonSelfTest" olayıyla çalıştırır (izleyici bu adı yok sayar; oturum oluşturmaz).
    static func fire(script: URL, config: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: script.path) else { return false }
        let process = Process()
        let isPython = script.pathExtension == "py"
        process.executableURL = URL(fileURLWithPath: isPython ? "/usr/bin/python3" : "/bin/sh")
        process.arguments = (isPython ? ["-I"] : []) + [script.path]
        process.environment = ProcessInfo.processInfo.environment.merging(["ADALMON_AGENTS_CONFIG": config.path]) { $1 }
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        input.fileHandleForWriting.write(Data(#"{"hook_event_name":"AdalmonSelfTest","session_id":"adalmon-selftest"}"#.utf8))
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
