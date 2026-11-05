import Foundation
import Observation

/// Panel ayarlarını UserDefaults'ta ("panelConfig") tutar.
@MainActor @Observable
final class PanelConfigStore {
    static let defaultsKey = "panelConfig"

    var config: PanelConfig { didSet { if config != oldValue { save() } } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(PanelConfig.self, from: data) {
            config = decoded
        } else {
            config = PanelConfig()
        }
    }

    func reset() { config = PanelConfig() }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
