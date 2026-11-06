import Foundation

/// Veri Tasarrufu modu ayarı. Faz A'da yalnızca saklanır; uygulama (default-deny) Faz B'de filtre tarafında yapılacak.
struct DataSaverConfig: Codable, Equatable, Sendable {
    var enabled = false
    /// Her zaman izinli uygulama anahtarları (bundle .app yolu / çalıştırılabilir yol).
    var allowlist: [String] = []

    init() {}

    private enum CodingKeys: String, CodingKey { case enabled, allowlist }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        allowlist = try c.decodeIfPresent([String].self, forKey: .allowlist) ?? []
    }
}
