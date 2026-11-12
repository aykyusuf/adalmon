import Darwin
import Foundation

// Codex limitlerini CANLI okur: `codex app-server` (resmi, yerel JSON-RPC) → `account/rateLimits/read`. Rollout dosyası yalnızca
// oturum varken güncellenir; bu yol oturum olmasa da sunucudaki güncel değeri verir. Yalnızca OKUMA yapılır: istemci yalnızca
// `CodexRPC.allowedMethods` içindeki üç metodu gönderebilir; sıfırlama hakkı kullanan/harcayan hiçbir metot yoktur (testle zorlanır).
// Yanıttan yalnızca yüzde/yenilenme/pencere uzunluğu/plan adı/kredi bakiyesi/limit doldu bilgisi ve ücretsiz sıfırlama haklarının
// bilgi alanları (başlık, açıklama, tür, durum, verilme/son kullanma tarihi) alınır. `accountId` ve kimlikler (hak kimliği dahil)
// çözülmez, saklanmaz, loglanmaz.

// MARK: İzinli JSON-RPC metotları

enum CodexRPC {
    /// İstemcinin gönderebileceği TEK metotlar. Başka metot göndermeye çalışmak hatadır.
    static let allowedMethods: Set<String> = ["initialize", "initialized", "account/rateLimits/read"]

    struct DisallowedMethod: Error, Equatable { var method: String }

    /// Tek satır JSON-RPC mesajı. `id == nil` ise bildirimdir. `paramsJSON` hazır JSON metnidir (yoksa param alanı yazılmaz).
    static func line(method: String, id: Int?, paramsJSON: String?) throws -> String {
        guard allowedMethods.contains(method) else { throw DisallowedMethod(method: method) }
        var parts: [String] = []
        if let id { parts.append(#""id":\#(id)"#) }
        parts.append(#""method":"\#(method)""#)
        if let paramsJSON { parts.append(#""params":\#(paramsJSON)"#) }
        return "{" + parts.joined(separator: ",") + "}"
    }
}

// MARK: Yanıt ayrıştırma (saf)

enum CodexAppServerParser {
    /// Tek satır JSON-RPC mesajlarından `id == requestID` olan YANIT satırını bulur (sunucu bildirimleri/istekleri atlanır).
    static func responseLine(in buffer: Data, requestID: Int) -> Data? {
        for line in buffer.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(line)),
                  envelope.id == requestID, envelope.method == nil else { continue }
            return Data(line)
        }
        return nil
    }

    /// `account/rateLimits/read` yanıt satırından canlı limitler; hata yanıtı ya da hiç pencere yoksa nil.
    static func limits(fromResponse line: Data, now: Date) -> ProviderLimits? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: line),
              envelope.error == nil, let result = envelope.result else { return nil }
        // Çoklu kovada `codex` kovası; yoksa geriye dönük uyumlu tek kova görünümü.
        guard let snapshot = result.rateLimitsByLimitId?["codex"] ?? result.rateLimits else { return nil }
        var limits = ProviderLimits(source: .codex, observedAt: now)
        for (index, raw) in [snapshot.primary, snapshot.secondary].enumerated() {
            guard let raw, let used = raw.usedPercent, used.isFinite, (-1...1000).contains(used) else { continue }
            let window = LimitWindow(usedPercent: min(100, max(0, used)), resetsAt: ClaudeLimitsPayload.epoch(raw.resetsAt))
            let kind: LimitWindowKind = if let minutes = raw.windowDurationMins {
                minutes <= 12 * 60 ? .fiveHour : .weekly
            } else {
                index == 0 ? .fiveHour : .weekly
            }
            switch kind {
            case .fiveHour where limits.fiveHour == nil: limits.fiveHour = window
            case .weekly where limits.weekly == nil: limits.weekly = window
            default: break
            }
        }
        guard limits.fiveHour != nil || limits.weekly != nil else { return nil }
        limits.planType = snapshot.planType.flatMap { LimitPlanMapper.codex(planType: $0) != nil ? $0.lowercased() : nil }
        if let credits = snapshot.credits, credits.hasCredits == true, credits.unlimited != true,
           let balance = credits.balance, balance.isFinite, balance >= 0 {
            limits.creditsBalance = balance
        }
        limits.limitReached = snapshot.reached
        if let resets = result.rateLimitResetCredits {
            let rows = (resets.credits ?? []).map { row in
                LimitResetCredit(title: row.title, detail: row.description, resetType: row.resetType, status: row.status ?? "unknown",
                                 grantedAt: ClaudeLimitsPayload.epoch(row.grantedAt), expiresAt: ClaudeLimitsPayload.epoch(row.expiresAt))
            }
            limits.resetCredits = rows.isEmpty ? nil : rows
            let available = rows.filter { $0.status == "available" }.count
            limits.resetCreditCount = max(resets.availableCount ?? 0, available)
        }
        limits.isLive = true
        return limits
    }

    // Yalnızca ihtiyaç duyulan alanlar bildirilir; bildirilmeyen (accountId, kimlikler, başlıklar …) hiç çözülmez.
    private struct Envelope: Decodable {
        let id: Int?
        let method: String?
        let result: Result?
        let error: Failure?

        private enum CodingKeys: String, CodingKey { case id, method, result, error }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try? c.decodeIfPresent(Int.self, forKey: .id)
            method = try? c.decodeIfPresent(String.self, forKey: .method)
            result = try? c.decodeIfPresent(Result.self, forKey: .result)
            error = try? c.decodeIfPresent(Failure.self, forKey: .error)
        }
    }

    private struct Failure: Decodable {}

    private struct Result: Decodable {
        let rateLimits: Snapshot?
        let rateLimitsByLimitId: [String: Snapshot]?
        let rateLimitResetCredits: ResetCredits?

        private enum CodingKeys: String, CodingKey { case rateLimits, rateLimitsByLimitId, rateLimitResetCredits }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            rateLimits = try? c.decodeIfPresent(Snapshot.self, forKey: .rateLimits)
            rateLimitsByLimitId = try? c.decodeIfPresent([String: Snapshot].self, forKey: .rateLimitsByLimitId)
            rateLimitResetCredits = try? c.decodeIfPresent(ResetCredits.self, forKey: .rateLimitResetCredits)
        }
    }

    private struct Snapshot: Decodable {
        let primary: Window?
        let secondary: Window?
        let credits: Credits?
        let planType: String?
        let reached: Bool

        private enum CodingKeys: String, CodingKey { case primary, secondary, credits, planType, rateLimitReachedType }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            primary = try? c.decodeIfPresent(Window.self, forKey: .primary)
            secondary = try? c.decodeIfPresent(Window.self, forKey: .secondary)
            credits = try? c.decodeIfPresent(Credits.self, forKey: .credits)
            planType = try? c.decodeIfPresent(String.self, forKey: .planType)
            // Doluysa tür metni gelir (ör. "rate_limit_reached"); boş/null → dolmadı. Türün kendisi saklanmaz.
            reached = ((try? c.decodeIfPresent(String.self, forKey: .rateLimitReachedType)) ?? nil).map { !$0.isEmpty } ?? false
        }
    }

    private struct Window: Decodable {
        let usedPercent: Double?
        let resetsAt: Double?
        let windowDurationMins: Double?

        private enum CodingKeys: String, CodingKey { case usedPercent, resetsAt, windowDurationMins }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            usedPercent = try? c.decodeIfPresent(Double.self, forKey: .usedPercent)
            resetsAt = try? c.decodeIfPresent(Double.self, forKey: .resetsAt)
            windowDurationMins = try? c.decodeIfPresent(Double.self, forKey: .windowDurationMins)
        }
    }

    private struct Credits: Decodable {
        let hasCredits: Bool?
        let unlimited: Bool?
        let balance: Double?

        private enum CodingKeys: String, CodingKey { case hasCredits, unlimited, balance }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            hasCredits = try? c.decodeIfPresent(Bool.self, forKey: .hasCredits)
            unlimited = try? c.decodeIfPresent(Bool.self, forKey: .unlimited)
            if let number = (try? c.decodeIfPresent(Double.self, forKey: .balance)) ?? nil {
                balance = number
            } else if let text = (try? c.decodeIfPresent(String.self, forKey: .balance)) ?? nil {
                balance = Double(text.trimmingCharacters(in: .whitespaces))
            } else {
                balance = nil
            }
        }
    }

    /// Hak sayısı ve satırların bilgi alanları. Satırların `id` alanı çözülmez.
    private struct ResetCredits: Decodable {
        let availableCount: Int?
        let credits: [Row]?

        struct Row: Decodable {
            let title: String?
            let description: String?
            let resetType: String?
            let status: String?
            let grantedAt: Double?
            let expiresAt: Double?

            private enum CodingKeys: String, CodingKey { case title, description, resetType, status, grantedAt, expiresAt }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                func text(_ key: CodingKeys, _ limit: Int) -> String? {
                    guard let raw = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil else { return nil }
                    let cleaned = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(limit))
                        .trimmingCharacters(in: .whitespaces)
                    return cleaned.isEmpty ? nil : cleaned
                }
                title = text(.title, 80)
                description = text(.description, 240)
                resetType = text(.resetType, 40)
                status = text(.status, 20)
                grantedAt = (try? c.decodeIfPresent(Double.self, forKey: .grantedAt)) ?? nil
                expiresAt = (try? c.decodeIfPresent(Double.self, forKey: .expiresAt)) ?? nil
            }
        }

        private enum CodingKeys: String, CodingKey { case availableCount, credits }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            availableCount = (try? c.decodeIfPresent(Int.self, forKey: .availableCount)) ?? nil
            credits = (try? c.decodeIfPresent([Row].self, forKey: .credits)) ?? nil
        }
    }
}

// MARK: Codex ikilisini bulma

/// Kullanıcının PATH'i GUI uygulamada yoktur: önce bilinen dizinlere (nvm, Homebrew, ~/.local …) bakılır; bulunamazsa login shell'den
/// `command -v codex` BİR KEZ çözülür ve önbelleğe alınır. Bulunamazsa nil (çağıran rollout yoluna düşer); bulunamama kısa süre hatırlanır.
final class CodexBinaryLocator: @unchecked Sendable {
    static let shared = CodexBinaryLocator()
    static let missMemory: TimeInterval = 10 * 60

    private let directories: @Sendable () -> [URL]
    private let shellResolver: @Sendable () -> URL?
    private let lock = NSLock()
    private var cached: URL?
    private var missedAt: Date?

    init(directories: @escaping @Sendable () -> [URL] = { CodexBinaryLocator.defaultDirectories() },
         shellResolver: @escaping @Sendable () -> URL? = { CodexBinaryLocator.loginShellResolve() }) {
        self.directories = directories
        self.shellResolver = shellResolver
    }

    static func defaultDirectories(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        var result: [URL] = []
        // nvm: en yeni sürüm önce.
        let nvm = home.appending(path: ".nvm/versions/node", directoryHint: .isDirectory)
        let versions = ((try? FileManager.default.contentsOfDirectory(at: nvm, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
        result += versions.map { $0.appending(path: "bin", directoryHint: .isDirectory) }
        result += [URL(filePath: "/opt/homebrew/bin"), URL(filePath: "/usr/local/bin"),
                   home.appending(path: ".local/bin", directoryHint: .isDirectory),
                   home.appending(path: ".volta/bin", directoryHint: .isDirectory),
                   home.appending(path: ".bun/bin", directoryHint: .isDirectory),
                   home.appending(path: ".npm-global/bin", directoryHint: .isDirectory)]
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        result += path.split(separator: ":").map { URL(filePath: String($0), directoryHint: .isDirectory) }
        return result
    }

    private static func isExecutable(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: url.path)
    }

    /// Önbellekteki yol hâlâ çalıştırılabilirse onu, değilse yeniden arar.
    func locate(now: Date = .now) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        if let cached, Self.isExecutable(cached) { return cached }
        cached = nil
        if let missedAt, now.timeIntervalSince(missedAt) < Self.missMemory { return nil }
        for dir in directories() {
            let candidate = dir.appending(path: "codex")
            if Self.isExecutable(candidate) { cached = candidate; missedAt = nil; return candidate }
        }
        if let resolved = shellResolver(), Self.isExecutable(resolved) { cached = resolved; missedAt = nil; return resolved }
        missedAt = now
        return nil
    }

    /// `zsh -l -c 'command -v codex'`; en çok 5 sn. Çıktının son mutlak yol satırı alınır (rc dosyaları gürültü basabilir).
    static func loginShellResolve(timeout: TimeInterval = 5) -> URL? {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-l", "-c", "command -v codex"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        guard (try? process.run()) != nil else { return nil }
        var data = Data()
        let reader = DispatchGroup()
        reader.enter()
        DispatchQueue.global(qos: .utility).async {
            data = output.fileHandleForReading.readDataToEndOfFile()
            reader.leave()
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = exited.wait(timeout: .now() + 2)
        }
        _ = reader.wait(timeout: .now() + 1)
        let text = String(decoding: data, as: UTF8.self)
        guard let line = text.split(separator: "\n").last(where: { $0.hasPrefix("/") }) else { return nil }
        return URL(filePath: line.trimmingCharacters(in: .whitespaces))
    }
}

// MARK: Süreç istemcisi

/// `codex app-server` sürecini başlatır, üç mesajı yazar (initialize, initialized, account/rateLimits/read), yanıt gelince süreci sonlandırır.
/// Bloklar (en çok `timeout` + sonlandırma payı): çağıran `Task.detached(priority: .utility)` içinde çalıştırmalıdır.
struct CodexAppServerClient: Sendable {
    var executable: URL
    var arguments: [String] = ["app-server"]
    var timeout: TimeInterval = 10
    var clientVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    static let rateLimitsRequestID = 2

    /// Ham yanıt satırı (id == 2) ya da nil (başlatılamadı / zaman aşımı / süreç erken bitti).
    func readRateLimitsResponse() -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = Self.environment(for: executable)
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        let collector = LineCollector()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; collector.finish() } else { collector.append(chunk) }
        }
        guard (try? process.run()) != nil else {
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        // Kapanmış boruya yazmak SIGPIPE ile uygulamayı öldürmesin.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        guard let messages = try? [
            CodexRPC.line(method: "initialize", id: 1,
                          paramsJSON: #"{"clientInfo":{"name":"adalmon","version":"\#(Self.safe(clientVersion))"}}"#),
            CodexRPC.line(method: "initialized", id: nil, paramsJSON: nil),
            CodexRPC.line(method: "account/rateLimits/read", id: Self.rateLimitsRequestID, paramsJSON: "null"),
        ] else {
            output.fileHandleForReading.readabilityHandler = nil
            Self.shutdown(process, input: input, output: output, exited: exited)
            return nil
        }
        try? input.fileHandleForWriting.write(contentsOf: Data((messages.joined(separator: "\n") + "\n").utf8))

        let deadline = Date().addingTimeInterval(timeout)
        var response: Data?
        while response == nil {
            response = collector.responseLine(requestID: Self.rateLimitsRequestID)
            if response != nil || collector.isFinished { break }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            collector.wait(timeout: remaining)
        }
        if response == nil { response = collector.responseLine(requestID: Self.rateLimitsRequestID) }
        Self.shutdown(process, input: input, output: output, exited: exited)
        return response
    }

    /// stdin'i kapat (süreç EOF'ta çıkar), çıkmazsa SIGTERM, olmazsa SIGKILL; her durumda çıkışı bekle (zombi bırakma).
    private static func shutdown(_ process: Process, input: Pipe, output: Pipe, exited: DispatchSemaphore) {
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if exited.wait(timeout: .now() + 0.3) == .timedOut {
            if process.isRunning { process.terminate() }
            if exited.wait(timeout: .now() + 2) == .timedOut {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                _ = exited.wait(timeout: .now() + 2)
            }
        }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
    }

    /// GUI uygulamasında PATH kısadır; `codex` bir node betiği olabilir (`#!/usr/bin/env node`): ikilinin dizini ve standart dizinler eklenir.
    static func environment(for executable: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        var parts = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        for item in existing where !parts.contains(item) { parts.append(item) }
        env["PATH"] = parts.joined(separator: ":")
        return env
    }

    private static func safe(_ version: String) -> String {
        String(version.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }.prefix(32))
    }

    /// Okuma iş parçacığından gelen baytları kilitle toplar.
    private final class LineCollector: @unchecked Sendable {
        private let lock = NSLock()
        private let signal = DispatchSemaphore(value: 0)
        private var buffer = Data()
        private var finished = false
        private static let maxBytes = 1_000_000

        func append(_ data: Data) {
            lock.lock()
            if buffer.count < Self.maxBytes { buffer.append(data) }
            lock.unlock()
            signal.signal()
        }

        func finish() {
            lock.lock(); finished = true; lock.unlock()
            signal.signal()
        }

        var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return finished }

        func responseLine(requestID: Int) -> Data? {
            lock.lock(); let snapshot = buffer; lock.unlock()
            return CodexAppServerParser.responseLine(in: snapshot, requestID: requestID)
        }

        func wait(timeout: TimeInterval) { _ = signal.wait(timeout: .now() + timeout) }
    }
}

// MARK: Yüksek seviye

/// İkiliyi bulur, app-server'dan canlı limiti okur. Hiçbir adım başarısızsa nil: çağıran rollout dosyasına düşer.
struct CodexLiveLimits: Sendable {
    var locator: CodexBinaryLocator = .shared
    var timeout: TimeInterval = 10
    /// Testte sahte ikili için; nil ise `locator` kullanılır.
    var executableOverride: URL?

    /// Bloklar: `Task.detached(priority: .utility)` içinde çağrılır.
    func fetch(now: Date = .now) -> ProviderLimits? {
        guard let executable = executableOverride ?? locator.locate() else { return nil }
        let client = CodexAppServerClient(executable: executable, timeout: timeout)
        guard let line = client.readRateLimitsResponse() else { return nil }
        return CodexAppServerParser.limits(fromResponse: line, now: now)
    }
}
