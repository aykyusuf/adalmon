import Darwin
import Foundation

/// Konuşma dosyasının (`~/.claude/projects/*/<session_id>.jsonl`) son bölümü. `isTruncated`: dosyanın başı okunmadı,
/// ilk satır yarım olabilir.
struct TranscriptTail: Equatable, Sendable {
    var data: Data
    var isTruncated: Bool
}

/// Dosya okuyucu soyutlaması (testlerde sahte/geçici dizin enjekte edilir).
protocol TranscriptTailReading: Sendable {
    func readTail(sessionID: String, maxBytes: Int) -> TranscriptTail?
}

/// Oturumun modelini bulan şey (AgentMonitorModel'e enjekte edilir; testte sahte).
protocol SessionModelResolving: Sendable {
    /// Bulunamazsa nil. Eşzamanlı ve hızlıdır; çağıran arka plan kuyruğunda çalıştırır.
    func latestModel(sessionID: String) -> String?
}

/// Saf ayrıştırıcı: konuşma dosyası kuyruğundan YALNIZCA son asistan mesajının `message.model` değerini çıkarır.
/// Başka hiçbir alan okunmaz/saklanmaz/loglanmaz.
enum TranscriptModelParser {
    /// Dosyanın sonundan okunan en çok bayt.
    static let tailBytes = 128 * 1024
    static let maxSessionIDLength = 64

    /// Yalnızca `[A-Za-z0-9-]`, 1...64 karakter: yol ayracı/nokta yok, yol gezintisi imkansız.
    static func isValidSessionID(_ id: String) -> Bool {
        guard (1...maxSessionIDLength).contains(id.utf8.count) else { return false }
        return id.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x2D }
    }

    /// `^[A-Za-z0-9._:\-\[\]]{1,64}$` ve "claude" ile başlar.
    static func isValidModel(_ model: String) -> Bool {
        guard (1...64).contains(model.utf8.count), model.hasPrefix("claude") else { return false }
        return model.utf8.allSatisfy { b in
            (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
                || b == 0x2E || b == 0x5F || b == 0x3A || b == 0x2D || b == 0x5B || b == 0x5D
        }
    }

    private static let modelKey = Data("\"model\"".utf8)
    private static let assistantMark = Data("\"assistant\"".utf8)

    /// Satırları sondan başa tarar; geçerli bir asistan modeli bulunca döner. Bozuk/model alanı olmayan/geçersiz değerli satırlar atlanır.
    static func latestModel(in tail: TranscriptTail) -> String? {
        var data = tail.data
        if tail.isTruncated {
            // Kuyruk satırın ortasında başlıyor: yarım ilk satırı at.
            guard let nl = data.firstIndex(of: 0x0A) else { return nil }
            data = data[data.index(after: nl)...]
        }
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true).reversed() {
            // Ucuz ön süzgeç: model alanı ve asistan işareti olmayan satır ayrıştırılmaz.
            guard line.range(of: modelKey) != nil, line.range(of: assistantMark) != nil else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any],
                  let model = message["model"] as? String, isValidModel(model) else { continue }
            return model
        }
        return nil
    }
}

/// Gerçek okuyucu: `<root>/<tek seviye dizin>/<id>.jsonl`. Sembolik bağ izlenmez (dizin ve dosya), yalnızca normal dosya açılır,
/// yalnızca dosyanın sonu okunur. Yazma yok.
struct ClaudeProjectsTailReader: TranscriptTailReading {
    var root: URL

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)) {
        self.root = root
    }

    func readTail(sessionID: String, maxBytes: Int = TranscriptModelParser.tailBytes) -> TranscriptTail? {
        guard TranscriptModelParser.isValidSessionID(sessionID), maxBytes > 0 else { return nil }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return nil }
        for dir in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let values = try? dir.resourceValues(forKeys: Set(keys)), values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let file = dir.appendingPathComponent("\(sessionID).jsonl", isDirectory: false)
            if let tail = Self.readRegularFileTail(file, maxBytes: maxBytes) { return tail }
        }
        return nil
    }

    private static func readRegularFileTail(_ url: URL, maxBytes: Int) -> TranscriptTail? {
        // O_NOFOLLOW: son bileşen sembolik bağsa açılmaz; fstat ile normal dosya doğrulanır (yarış yok).
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { close(fd); return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let size = UInt64(max(0, info.st_size))
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        do {
            try handle.seek(toOffset: offset)
            let data = try handle.read(upToCount: maxBytes) ?? Data()
            return TranscriptTail(data: data, isTruncated: offset > 0)
        } catch {
            return nil
        }
    }
}

/// Oturum kimliğini doğrular, dosya kuyruğunu okur ve modeli ayrıştırır.
struct TranscriptModelResolver: SessionModelResolving {
    var reader: any TranscriptTailReading

    init(reader: any TranscriptTailReading = ClaudeProjectsTailReader()) { self.reader = reader }

    func latestModel(sessionID: String) -> String? {
        guard TranscriptModelParser.isValidSessionID(sessionID),
              let tail = reader.readTail(sessionID: sessionID, maxBytes: TranscriptModelParser.tailBytes) else { return nil }
        return TranscriptModelParser.latestModel(in: tail)
    }
}

/// Bilinmeyen model aramalarının hız sınırı (saf): oturum başına en çok `maxAttempts` olağan deneme, ilki hemen; başarısız
/// denemeden sonra `baseDelay * 2^n` (n: önceki yavaş bekleme sayısı) beklenir. PostToolUse ile gelen (`fast`) denemelerde ilk
/// `fastAttempts` deneme için bekleme `fastDelay`dir. Ek olarak `force` ile verilen her olay türü (Stop, SubagentStop, SessionEnd,
/// kapanış sonrası son deneme) oturum başına bir kez geri çekilmeyi ve üst sınırı atlar. Başarıda durur. Zamanlayıcı yok: yalnızca
/// olay gelince `shouldAttempt` sorulur.
struct ModelLookupTracker: Equatable, Sendable {
    static let maxAttempts = 8
    static let baseDelay: TimeInterval = 30
    static let fastDelay: TimeInterval = 5
    static let fastAttempts = 3

    private struct Entry: Equatable, Sendable {
        var attempts = 0
        var slowWaits = 0
        var nextAt = Date.distantPast
        var inFlight = false
        var inFlightFast = false
        var inFlightForced = false
        var resolved = false
        var forced: Set<String> = []
    }

    private var entries: [String: Entry] = [:]

    /// Deneme hakkı varsa true döner ve denemeyi başlamış sayar (`finish` ile bitirilmeli).
    /// `fast`: olay PostToolUse. `force`: olay türü anahtarı; oturum başına bir kez geri çekilmeyi ve üst sınırı atlar.
    mutating func shouldAttempt(_ id: String, now: Date, fast: Bool = false, force: String? = nil) -> Bool {
        var e = entries[id] ?? Entry()
        guard !e.resolved, !e.inFlight else { return false }
        if let force {
            guard !e.forced.contains(force) else { return false }
            e.forced.insert(force)
            e.inFlightForced = true
        } else {
            guard e.attempts < Self.maxAttempts, now >= e.nextAt else { return false }
            e.attempts += 1
            e.inFlightForced = false
            e.inFlightFast = fast
        }
        e.inFlight = true
        entries[id] = e
        return true
    }

    mutating func finish(_ id: String, found: Bool, now: Date) {
        guard var e = entries[id] else { return }
        e.inFlight = false
        if found {
            e.resolved = true
        } else if !e.inFlightForced {
            if e.inFlightFast, e.attempts <= Self.fastAttempts {
                e.nextAt = now.addingTimeInterval(Self.fastDelay)
            } else {
                e.nextAt = now.addingTimeInterval(Self.baseDelay * pow(2, Double(e.slowWaits)))
                e.slowWaits += 1
            }
        }
        e.inFlightForced = false
        entries[id] = e
    }

    /// Listede olmayan oturumların kayıtlarını atar.
    mutating func retain(_ ids: Set<String>) { entries = entries.filter { ids.contains($0.key) } }

    mutating func removeAll() { entries = [:] }

    func attempts(for id: String) -> Int { entries[id]?.attempts ?? 0 }
}
