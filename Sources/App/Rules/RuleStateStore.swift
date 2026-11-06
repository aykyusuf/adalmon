import Foundation

/// Diske yazılan kural motoru durumu.
struct PersistedRuleState: Codable, Equatable, Sendable {
    var version = 1
    var runtimes: [String: RuleRuntime] = [:]
    /// Merdiven bildirimlerinin gönderildiği gün ve ulaşılan en yüksek kademe (yeniden başlatmada tekrar bildirme).
    var ladderDay: String?
    var ladderMaxLevel: TierLevel = .none
}

/// Küçük JSON dosyası (Application Support). Testler kendi URL'sini verir.
enum RuleStateStore {
    static var defaultURL: URL { AppEnvironment.supportDirectory.appending(path: "rule-state.json") }

    static func load(from url: URL) -> PersistedRuleState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(PersistedRuleState.self, from: data) else { return PersistedRuleState() }
        return state
    }

    static func encode(_ state: PersistedRuleState) -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return try? enc.encode(state)
    }

    static func write(_ data: Data, to url: URL) {
        try? data.write(to: url, options: .atomic)
    }
}
