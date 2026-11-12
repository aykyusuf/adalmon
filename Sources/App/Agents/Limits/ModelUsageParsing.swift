import Darwin
import Foundation

// Model bazında kullanım (USAGE-03): Claude Code transkriptleri (~/.claude/projects/**/*.jsonl) ve Codex rollout dosyaları
// (~/.codex/sessions/**/rollout-*.jsonl) satır satır, bayt düzeyinde taranır. Yalnızca model adı, token sayıları, zaman damgası ve
// yinelenen kayıtları ayıklamak için mesaj kimliğinin özeti okunur; istem/yanıt metni hiçbir yerde çözülmez, saklanmaz.
// Bu dosya saf mantıktır (dosya/ağ/zamanlayıcı yok) ve fixture satırlarıyla test edilir.

struct ModelTokens: Equatable, Hashable, Sendable {
    /// Önbelleğe girmeyen girdi.
    var input = 0
    var output = 0
    /// Önbelleğe yazılan girdi (Claude `cache_creation_input_tokens`).
    var cacheWrite = 0
    /// Önbellekten okunan girdi.
    var cacheRead = 0

    var total: Int { input + output + cacheWrite + cacheRead }
    var cached: Int { cacheWrite + cacheRead }

    static func + (a: Self, b: Self) -> Self {
        Self(input: a.input + b.input, output: a.output + b.output, cacheWrite: a.cacheWrite + b.cacheWrite, cacheRead: a.cacheRead + b.cacheRead)
    }

    static func += (a: inout Self, b: Self) { a = a + b }
}

/// Tek bir model isteğinin (Claude: bir asistan mesajı, Codex: bir `token_count` olayı) ham ölçümü.
struct UsageSample: Equatable, Sendable {
    var timestamp: TimeInterval
    var model: String
    var tokens: ModelTokens
    /// Yinelenen kayıtları ayıklamak için mesaj kimliğinin özeti (FNV-1a); 0 = kimlik yok, ayıklama yapılmaz.
    var key: UInt64
}

/// Bayt tamponu üzerinde küçük, ayırmasız arama/okuma yardımcıları. JSON ağacı kurulmaz: satırlar çoğu zaman megabaytlarca
/// araç çıktısı taşır; yalnızca ihtiyaç duyulan birkaç anahtara bakılır.
enum UsageBytes {
    /// `needle`ın `[from, limit)` aralığındaki ilk konumu.
    static func find(_ needle: StaticString, in hay: UnsafeRawBufferPointer, from: Int = 0, limit: Int? = nil) -> Int? {
        let stop = min(limit ?? hay.count, hay.count)
        guard from >= 0, from < stop, let base = hay.baseAddress else { return nil }
        return needle.withUTF8Buffer { pattern -> Int? in
            guard let found = memmem(base + from, stop - from, pattern.baseAddress, pattern.count) else { return nil }
            return base.distance(to: UnsafeRawPointer(found))
        }
    }

    /// `prefix` (ör. `"model":"`) hemen ardından gelen JSON metin değeri; kaçış dizisi içeriyorsa ya da çok uzunsa nil.
    static func string(after prefix: StaticString, in hay: UnsafeRawBufferPointer, from: Int = 0, limit: Int? = nil,
                       maxLength: Int = 160) -> String? {
        guard let at = find(prefix, in: hay, from: from, limit: limit) else { return nil }
        let start = at + prefix.utf8CodeUnitCount
        let stop = min(hay.count, start + maxLength + 1)
        var index = start
        while index < stop {
            let byte = hay[index]
            if byte == UInt8(ascii: "\"") { return String(decoding: UnsafeRawBufferPointer(rebasing: hay[start..<index]), as: UTF8.self) }
            if byte == UInt8(ascii: "\\") { return nil }
            index += 1
        }
        return nil
    }

    /// `{` konumundan başlayan nesnenin birinci düzey sayı alanları (yalnızca tamsayı kısmı). Anahtar yoksa ya da sayı değilse nil.
    /// Dönen `end`, nesnenin kapanış parantezinden sonraki konumdur.
    static func integers(ofObjectAt open: Int, in hay: UnsafeRawBufferPointer, keys: [StaticString]) -> (values: [Int?], end: Int)? {
        guard open < hay.count, hay[open] == UInt8(ascii: "{") else { return nil }
        var values = [Int?](repeating: nil, count: keys.count)
        var index = open + 1
        let count = hay.count
        func skipSpace() {
            while index < count, hay[index] == 0x20 || hay[index] == 0x0A || hay[index] == 0x0D || hay[index] == 0x09 { index += 1 }
        }
        /// `index` açılış tırnağındayken kapanış tırnağının ardına geçer.
        func skipString() -> Bool {
            index += 1
            while index < count {
                let byte = hay[index]
                if byte == UInt8(ascii: "\\") { index += 2; continue }
                index += 1
                if byte == UInt8(ascii: "\"") { return true }
            }
            return false
        }
        /// `index` açılış parantezindeyken ({ ya da [) dengeli kapanışın ardına geçer.
        func skipContainer() -> Bool {
            var depth = 0
            while index < count {
                let byte = hay[index]
                if byte == UInt8(ascii: "\"") { guard skipString() else { return false }; continue }
                index += 1
                if byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[") { depth += 1 }
                if byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]") {
                    depth -= 1
                    if depth == 0 { return true }
                }
            }
            return false
        }
        while true {
            skipSpace()
            guard index < count else { return nil }
            if hay[index] == UInt8(ascii: "}") { return (values, index + 1) }
            if hay[index] == UInt8(ascii: ",") { index += 1; continue }
            guard hay[index] == UInt8(ascii: "\"") else { return nil }
            let keyStart = index + 1
            guard skipString() else { return nil }
            let keyEnd = index - 1
            skipSpace()
            guard index < count, hay[index] == UInt8(ascii: ":") else { return nil }
            index += 1
            skipSpace()
            guard index < count else { return nil }
            let byte = hay[index]
            if byte == UInt8(ascii: "\"") {
                guard skipString() else { return nil }
            } else if byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[") {
                guard skipContainer() else { return nil }
            } else {
                let valueStart = index
                while index < count, hay[index] != UInt8(ascii: ","), hay[index] != UInt8(ascii: "}") { index += 1 }
                if let slot = keys.firstIndex(where: { matches($0, hay, keyStart, keyEnd) }), values[slot] == nil {
                    values[slot] = integer(hay, valueStart, index)
                }
            }
        }
    }

    private static func matches(_ key: StaticString, _ hay: UnsafeRawBufferPointer, _ start: Int, _ end: Int) -> Bool {
        guard key.utf8CodeUnitCount == end - start else { return false }
        return key.withUTF8Buffer { pattern in
            for offset in 0..<pattern.count where hay[start + offset] != pattern[offset] { return false }
            return true
        }
    }

    /// Boşluksuz ondalık tamsayı (kesir/üs kısmı atılır); sayı değilse nil.
    private static func integer(_ hay: UnsafeRawBufferPointer, _ start: Int, _ end: Int) -> Int? {
        var index = start, value = 0, digits = 0
        while index < end, hay[index] == 0x20 { index += 1 }
        while index < end {
            let byte = hay[index]
            guard byte >= 0x30, byte <= 0x39 else { break }
            value = value &* 10 &+ Int(byte - 0x30)
            digits += 1
            if digits > 15 { return nil }
            index += 1
        }
        return digits > 0 ? value : nil
    }

    /// ISO-8601 `2026-11-11T17:36:19.695Z` (UTC) → epoch saniyesi. Biçim uymazsa nil. Biçimleyici kullanılmaz (milyonlarca satır).
    static func timestamp(at start: Int, in hay: UnsafeRawBufferPointer) -> TimeInterval? {
        guard start >= 0, start + 20 <= hay.count else { return nil }
        func digit(_ offset: Int) -> Int? {
            let byte = hay[start + offset]
            return byte >= 0x30 && byte <= 0x39 ? Int(byte - 0x30) : nil
        }
        func number(_ offset: Int, _ length: Int) -> Int? {
            var value = 0
            for position in offset..<(offset + length) {
                guard let d = digit(position) else { return nil }
                value = value * 10 + d
            }
            return value
        }
        guard hay[start + 4] == UInt8(ascii: "-"), hay[start + 7] == UInt8(ascii: "-"), hay[start + 10] == UInt8(ascii: "T"),
              hay[start + 13] == UInt8(ascii: ":"), hay[start + 16] == UInt8(ascii: ":"),
              let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
              let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2),
              (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 62 else { return nil }
        var fraction = 0.0
        var cursor = start + 19
        if cursor < hay.count, hay[cursor] == UInt8(ascii: ".") {
            var scale = 0.1
            cursor += 1
            while cursor < hay.count, hay[cursor] >= 0x30, hay[cursor] <= 0x39, scale > 1e-6 {
                fraction += Double(hay[cursor] - 0x30) * scale
                scale /= 10
                cursor += 1
            }
        }
        // Gün sayısı (Howard Hinnant, days_from_civil).
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146_097 + doe - 719_468
        return Double(days) * 86_400 + Double(hour * 3600 + minute * 60 + second) + fraction
    }

    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return hash == 0 ? 1 : hash
    }
}

// MARK: Claude

/// Claude Code transkript satırı. Asistan satırı: `…"message":{"model":"…","id":"msg_…","role":"assistant",…,"usage":{…}},…,"timestamp":"…"`.
/// Aynı mesaj akış sırasında birden çok satır olarak yazılır (içerik bloğu başına bir); çağıran `key` ile yinelemeleri birleştirir.
enum ClaudeTranscriptUsageParser {
    /// `message` nesnesi satırın başında aranır (araç çıktısı taşıyan uzun satırlarda bile ucuz).
    static let messageSearchLimit = 8192
    static let headerSpan = 1024

    static func parse(line: UnsafeRawBufferPointer) -> UsageSample? {
        guard let message = UsageBytes.find(#""message":{"#, in: line, limit: messageSearchLimit) else { return nil }
        let header = min(line.count, message + headerSpan)
        guard UsageBytes.find(#""role":"assistant""#, in: line, from: message, limit: header) != nil,
              let model = UsageBytes.string(after: #""model":""#, in: line, from: message, limit: header),
              !model.isEmpty, !model.hasPrefix("<") else { return nil }
        guard let usageKey = UsageBytes.find(#""usage":{"#, in: line, from: message) else { return nil }
        let keys: [StaticString] = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
        guard let (values, end) = UsageBytes.integers(ofObjectAt: usageKey + 8, in: line, keys: keys) else { return nil }
        let tokens = ModelTokens(input: values[0] ?? 0, output: values[1] ?? 0, cacheWrite: values[2] ?? 0, cacheRead: values[3] ?? 0)
        guard tokens.total > 0 else { return nil }
        let stamp = UsageBytes.find(#""timestamp":""#, in: line, from: end) ?? UsageBytes.find(#""timestamp":""#, in: line, limit: message)
        guard let stamp, let time = UsageBytes.timestamp(at: stamp + 13, in: line) else { return nil }
        let id = UsageBytes.string(after: #""id":""#, in: line, from: message, limit: header)
        return UsageSample(timestamp: time, model: model, tokens: tokens, key: id.map(UsageBytes.fnv1a) ?? 0)
    }
}

// MARK: Codex

/// Codex rollout satırı. `turn_context` (model adı) ve `event_msg/token_count` (istek başına `last_token_usage`) okunur.
/// `token_count` satırı: `{"timestamp":"…","ordinal":N,"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{…},
/// "last_token_usage":{input_tokens,cached_input_tokens,cache_write_input_tokens,output_tokens,…},…},"rate_limits":{…}}}`.
enum CodexRolloutUsageParser {
    enum Event: Equatable, Sendable {
        case model(String)
        /// `total`: oturumun o ana kadarki toplam token sayısı (aynı olayı iki kez saymamak için).
        case usage(timestamp: TimeInterval, tokens: ModelTokens, total: Int)
    }

    static let headerSpan = 256
    static let modelSearchLimit = 64 * 1024

    static func parse(line: UnsafeRawBufferPointer) -> Event? {
        if UsageBytes.find(#""type":"turn_context""#, in: line, limit: headerSpan) != nil {
            guard let model = UsageBytes.string(after: #""model":""#, in: line, limit: modelSearchLimit), !model.isEmpty else { return nil }
            return .model(model)
        }
        guard UsageBytes.find(#""type":"token_count""#, in: line, limit: headerSpan) != nil,
              let last = UsageBytes.find(#""last_token_usage":{"#, in: line),
              let stamp = UsageBytes.find(#""timestamp":""#, in: line, limit: 48),
              let time = UsageBytes.timestamp(at: stamp + 13, in: line) else { return nil }
        let keys: [StaticString] = ["input_tokens", "cached_input_tokens", "cache_write_input_tokens", "output_tokens", "total_tokens"]
        guard let (values, _) = UsageBytes.integers(ofObjectAt: last + 19, in: line, keys: keys) else { return nil }
        let cacheRead = values[1] ?? 0, cacheWrite = values[2] ?? 0
        // OpenAI sayımında `input_tokens` önbellektekileri de içerir: önbelleğe girmeyen girdi farktır.
        let tokens = ModelTokens(input: max(0, (values[0] ?? 0) - cacheRead - cacheWrite), output: values[3] ?? 0,
                                 cacheWrite: cacheWrite, cacheRead: cacheRead)
        guard tokens.total > 0 else { return nil }
        var total = 0
        if let totalKey = UsageBytes.find(#""total_token_usage":{"#, in: line),
           let (totals, _) = UsageBytes.integers(ofObjectAt: totalKey + 20, in: line, keys: ["total_tokens"]) {
            total = totals[0] ?? 0
        }
        return .usage(timestamp: time, tokens: tokens, total: total)
    }
}
