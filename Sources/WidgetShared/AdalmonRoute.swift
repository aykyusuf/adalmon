import Foundation

/// `adalmon://battery` gibi bağlantılar ve "Adalmon'u aç (sayfa)" kestirmesi için sayfa kimlikleri.
enum AdalmonRoute: String, CaseIterable, Sendable, Equatable {
    case overview, network, history, mobile, rules, processes, battery, system, widgets, shortcuts

    static let scheme = "adalmon"

    var url: URL { URL(string: "\(Self.scheme)://\(rawValue)")! }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        let name = (url.host() ?? url.path.split(separator: "/").first.map(String.init) ?? "").lowercased()
        self.init(rawValue: name)
    }
}
