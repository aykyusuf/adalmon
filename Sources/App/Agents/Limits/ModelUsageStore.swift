import Darwin
import Foundation

/// Bir modelin bir zaman aralığındaki toplamı (ham, fiyat ağırlığı henüz uygulanmadı).
struct ModelAggregate: Equatable, Sendable {
    var model: String
    var tokens: ModelTokens
    var messages: Int
}

struct ModelUsageScanStats: Equatable, Sendable {
    var filesConsidered = 0
    var filesRead = 0
    var bytesRead: UInt64 = 0
    var newRecords = 0
}

/// Transkript/rollout dosyalarını artımlı okur ve model başına kayıtları bellekte tutar.
/// - Dosya başına son okunan konum + değişiklik zamanı saklanır; değişmeyen dosyaya dokunulmaz, büyüyen dosyada yalnızca yeni baytlar okunur.
/// - Yalnızca `since` tarihinden sonra değişmiş dosyalar okunur; satırlar 1 MiB'lık parçalarla akıtılır (dosya belleğe alınmaz).
/// - Kayıtlar yalnızca sayılardan oluşur (model adı tablosuna indeks, token sayıları, zaman); metin saklanmaz.
/// Zamanlayıcısı yoktur: çağıran (SubscriptionLimitsModel) yalnızca sayfa görünürken ve en çok dakikada bir çağırır.
final class ModelUsageStore: @unchecked Sendable {
    static let chunkBytes = 1 << 20
    /// Bu boyutu aşan tek satır atlanır (devasa araç çıktıları); asistan satırları buna yaklaşmaz.
    static let maxLineBytes = 64 << 20
    /// Bellekte tutulan en eski kayıt (pencereler en çok 7 gün + pay).
    static let retention: TimeInterval = 8 * 86_400

    private struct FileState {
        var id: UInt32
        var offset: UInt64
        var modified: Date
        /// Codex: dosyadaki geçerli model (en son `turn_context`) ve son toplam token (tekrarlayan olayı saymamak için).
        var codexModel: String?
        var codexTotal: Int
    }

    private struct Record {
        var timestamp: TimeInterval
        var model: UInt16
        var file: UInt32
        var input: UInt32
        var output: UInt32
        var cacheWrite: UInt32
        var cacheRead: UInt32
        var key: UInt64
    }

    let claudeRoot: URL
    let codexRoot: URL
    private let lock = NSLock()
    private var files: [String: FileState] = [:]
    private var nextFileID: UInt32 = 1
    private var models: [String] = []
    private var modelIndex: [String: UInt16] = [:]
    private var records: [LimitSource: [Record]] = [:]
    private var keyIndex: [LimitSource: [UInt64: Int]] = [:]

    init(claudeRoot: URL = ModelUsageStore.defaultClaudeRoot, codexRoot: URL = CodexRolloutReader.defaultRoot) {
        self.claudeRoot = claudeRoot
        self.codexRoot = codexRoot
    }

    static var defaultClaudeRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects", directoryHint: .isDirectory)
    }

    func root(for source: LimitSource) -> URL { source == .claude ? claudeRoot : codexRoot }

    // MARK: Tarama

    /// `since`'ten sonra değişmiş dosyaları artımlı okur. `isCancelled` parça aralarında denetlenir; iptalde okunan kısım korunur,
    /// kalanı sonraki çağrıda okunur.
    @discardableResult
    func refresh(_ source: LimitSource, since: Date, now: Date = .now, isCancelled: () -> Bool = { false }) -> ModelUsageScanStats {
        lock.lock()
        defer { lock.unlock() }
        var stats = ModelUsageScanStats()
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let walker = manager.enumerator(at: root(for: source), includingPropertiesForKeys: keys,
                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return stats }
        let cutoff = now.timeIntervalSince1970 - Self.retention
        var seen = Set<String>()
        var pending: [(url: URL, size: UInt64, modified: Date)] = []
        for case let url as URL in walker {
            guard url.pathExtension == "jsonl", source == .claude || url.lastPathComponent.hasPrefix("rollout-"),
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate, let size = values.fileSize else { continue }
            seen.insert(Self.stateKey(source, url))
            guard modified >= since else { continue }
            pending.append((url, UInt64(size), modified))
        }
        // En yeni dosya önce: iptal edilirse en güncel veri hazır olur.
        pending.sort { $0.modified > $1.modified }
        stats.filesConsidered = pending.count
        for entry in pending {
            if isCancelled() { break }
            let stateKey = Self.stateKey(source, entry.url)
            var state = files[stateKey] ?? FileState(id: takeFileID(), offset: 0, modified: .distantPast, codexModel: nil, codexTotal: 0)
            if state.offset == entry.size, state.modified == entry.modified { continue }
            if entry.size < state.offset {
                // Dosya kısalmış/yeniden yazılmış: onun kayıtlarını at, baştan oku.
                dropRecords(of: state.id, source: source)
                state = FileState(id: state.id, offset: 0, modified: .distantPast, codexModel: nil, codexTotal: 0)
            }
            let before = records[source]?.count ?? 0
            let read = scan(path: entry.url.path(percentEncoded: false), source: source, state: &state, cutoff: cutoff, isCancelled: isCancelled)
            state.modified = entry.modified
            files[stateKey] = state
            stats.filesRead += 1
            stats.bytesRead += read
            stats.newRecords += (records[source]?.count ?? 0) - before
        }
        // Silinmiş dosyaların durumunu bırak.
        let prefix = source.rawValue + "|"
        for key in files.keys where key.hasPrefix(prefix) && !seen.contains(key) { files[key] = nil }
        prune(source, cutoff: cutoff)
        return stats
    }

    private static func stateKey(_ source: LimitSource, _ url: URL) -> String { source.rawValue + "|" + url.path(percentEncoded: false) }

    private func takeFileID() -> UInt32 {
        defer { nextFileID &+= 1 }
        return nextFileID
    }

    /// `state.offset`'ten dosya sonuna kadar akıtır; tam satırlar işlenir, sondaki yarım satır sonraki okumaya kalır. Okunan bayt sayısı döner.
    private func scan(path: String, source: LimitSource, state: inout FileState, cutoff: TimeInterval, isCancelled: () -> Bool) -> UInt64 {
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { return 0 }
        defer { close(descriptor) }
        var capacity = Self.chunkBytes
        var buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 16)
        defer { buffer.deallocate() }
        var have = 0
        var position = state.offset
        var consumed = state.offset
        var discarding = false
        var totalRead: UInt64 = 0
        while !isCancelled() {
            if have == capacity {
                if capacity >= Self.maxLineBytes {
                    // Tek satır sınırı aştı: satır sonuna kadar at.
                    discarding = true
                    consumed += UInt64(have)
                    have = 0
                } else {
                    let grown = UnsafeMutableRawPointer.allocate(byteCount: capacity * 2, alignment: 16)
                    grown.copyMemory(from: buffer, byteCount: have)
                    buffer.deallocate()
                    buffer = grown
                    capacity *= 2
                }
            }
            let count = pread(descriptor, buffer + have, capacity - have, off_t(position))
            if count <= 0 { break }
            position += UInt64(count)
            totalRead += UInt64(count)
            have += count
            var start = 0
            if discarding {
                guard let newline = memchr(buffer, 0x0A, have) else {
                    consumed += UInt64(have)
                    have = 0
                    continue
                }
                start = buffer.distance(to: newline) + 1
                discarding = false
            }
            while start < have, let newline = memchr(buffer + start, 0x0A, have - start) {
                let end = buffer.distance(to: newline)
                if end > start {
                    ingest(line: UnsafeRawBufferPointer(start: buffer + start, count: end - start), source: source, state: &state, cutoff: cutoff)
                }
                start = end + 1
            }
            if start > 0 {
                if start < have { memmove(buffer, buffer + start, have - start) }
                have -= start
                consumed += UInt64(start)
            }
        }
        state.offset = consumed
        return totalRead
    }

    private func ingest(line: UnsafeRawBufferPointer, source: LimitSource, state: inout FileState, cutoff: TimeInterval) {
        switch source {
        case .claude:
            guard let sample = ClaudeTranscriptUsageParser.parse(line: line), sample.timestamp >= cutoff else { return }
            add(sample, source: source, file: state.id)
        case .codex:
            switch CodexRolloutUsageParser.parse(line: line) {
            case .model(let model)?:
                state.codexModel = model
            case .usage(let timestamp, let tokens, let total)?:
                // Aynı toplam yeniden yazıldıysa (ör. bağlantı yenilemesi) ikinci kez sayma.
                if total > 0, total == state.codexTotal { return }
                state.codexTotal = total
                guard timestamp >= cutoff else { return }
                add(UsageSample(timestamp: timestamp, model: state.codexModel ?? "bilinmiyor", tokens: tokens, key: 0), source: source, file: state.id)
            case nil:
                return
            }
        }
    }

    private func add(_ sample: UsageSample, source: LimitSource, file: UInt32) {
        let model = intern(sample.model)
        func clamp(_ value: Int) -> UInt32 { UInt32(min(max(value, 0), Int(UInt32.max))) }
        if sample.key != 0, let existing = keyIndex[source]?[sample.key], existing < (records[source]?.count ?? 0) {
            // Aynı mesajın sonraki satırları: sayılar akışla büyür, en büyüğü tut.
            guard var record = records[source]?[existing] else { return }
            record.input = max(record.input, clamp(sample.tokens.input))
            record.output = max(record.output, clamp(sample.tokens.output))
            record.cacheWrite = max(record.cacheWrite, clamp(sample.tokens.cacheWrite))
            record.cacheRead = max(record.cacheRead, clamp(sample.tokens.cacheRead))
            records[source]?[existing] = record
            return
        }
        if sample.key != 0 { keyIndex[source, default: [:]][sample.key] = records[source]?.count ?? 0 }
        records[source, default: []].append(Record(
            timestamp: sample.timestamp, model: model, file: file, input: clamp(sample.tokens.input), output: clamp(sample.tokens.output),
            cacheWrite: clamp(sample.tokens.cacheWrite), cacheRead: clamp(sample.tokens.cacheRead), key: sample.key))
    }

    private func intern(_ model: String) -> UInt16 {
        if let index = modelIndex[model] { return index }
        guard models.count < Int(UInt16.max) else { return 0 }
        let index = UInt16(models.count)
        models.append(model)
        modelIndex[model] = index
        return index
    }

    private func dropRecords(of file: UInt32, source: LimitSource) {
        guard let list = records[source] else { return }
        records[source] = list.filter { $0.file != file }
        rebuildKeyIndex(source)
    }

    private func prune(_ source: LimitSource, cutoff: TimeInterval) {
        guard let list = records[source], list.contains(where: { $0.timestamp < cutoff }) else { return }
        records[source] = list.filter { $0.timestamp >= cutoff }
        rebuildKeyIndex(source)
    }

    private func rebuildKeyIndex(_ source: LimitSource) {
        var index: [UInt64: Int] = [:]
        for (position, record) in (records[source] ?? []).enumerated() where record.key != 0 { index[record.key] = position }
        keyIndex[source] = index
    }

    // MARK: Toplama

    /// `[start, end]` aralığındaki kayıtların model başına toplamı (belirlenimli sıra: toplam token azalan, sonra ad).
    func aggregate(_ source: LimitSource, from start: Date, to end: Date) -> [ModelAggregate] {
        lock.lock()
        defer { lock.unlock() }
        let low = start.timeIntervalSince1970, high = end.timeIntervalSince1970
        var totals: [UInt16: (tokens: ModelTokens, messages: Int)] = [:]
        for record in records[source] ?? [] where record.timestamp >= low && record.timestamp <= high {
            var entry = totals[record.model] ?? (ModelTokens(), 0)
            entry.tokens += ModelTokens(input: Int(record.input), output: Int(record.output), cacheWrite: Int(record.cacheWrite),
                                        cacheRead: Int(record.cacheRead))
            entry.messages += 1
            totals[record.model] = entry
        }
        return totals.map { ModelAggregate(model: models[Int($0.key)], tokens: $0.value.tokens, messages: $0.value.messages) }
            .sorted { ($0.tokens.total, $1.model) > ($1.tokens.total, $0.model) }
    }

    var recordCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return records.values.reduce(0) { $0 + $1.count }
    }
}
