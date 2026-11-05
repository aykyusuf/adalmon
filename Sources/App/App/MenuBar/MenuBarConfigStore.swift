import Foundation
import Observation

@MainActor @Observable
final class MenuBarConfigStore {
    static let defaultsKey = "menuBarConfig"

    var config: MenuBarConfig { didSet { save() } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(MenuBarConfig.self, from: data) {
            config = decoded
        } else {
            config = Self.migratedConfig(from: defaults)
        }
        save()
    }

    var currentPreset: MenuBarPreset? { MenuBarPreset.matching(config.components) }

    /// Simple metric cards, or nil when the advanced editor produced something cards can't represent.
    var cards: [MetricCardConfig]? { MetricCardConfig.cards(from: config.components) }

    func apply(cards: [MetricCardConfig]) {
        let components = MetricCardConfig.components(for: cards)
        guard components != config.components else { return }
        config.components = components
    }

    /// "Basit düzene dön": replaces an advanced component list with the default cards (layout options kept).
    func resetToSimpleLayout() {
        apply(cards: MetricCardConfig.defaults)
    }

    func apply(_ preset: MenuBarPreset) {
        config.components = preset.components
    }

    /// "Varsayılana dön": default components and layout options.
    func resetToDefault() {
        config = .default
    }

    @discardableResult
    func add(_ component: MenuBarComponent) -> MenuBarComponent.ID {
        let copy = component.duplicated()
        config.components.append(copy)
        return copy.id
    }

    func remove(id: MenuBarComponent.ID) {
        config.components.removeAll { $0.id == id }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        config.components.move(fromOffsets: source, toOffset: destination)
    }

    func move(id: MenuBarComponent.ID, by delta: Int) {
        guard let i = config.components.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard config.components.indices.contains(j) else { return }
        config.components.swapAt(i, j)
    }

    /// Moves `id` to the position currently held by `target` (drag and drop in the mock).
    func move(id: MenuBarComponent.ID, onto target: MenuBarComponent.ID) {
        guard id != target,
              let from = config.components.firstIndex(where: { $0.id == id }),
              let to = config.components.firstIndex(where: { $0.id == target }) else { return }
        config.components.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    static func migratedConfig(from defaults: UserDefaults) -> MenuBarConfig {
        func flag(_ key: String) -> Bool { (defaults.object(forKey: key) as? Bool) ?? false }
        var components: [MenuBarComponent] = []
        if flag("showCPUItem") { components.append(MenuBarComponent(.cpu, visual: .stacked2, showLabel: true)) }
        if flag("showRAMItem") { components.append(MenuBarComponent(.memoryPercent, visual: .stacked2, showLabel: true)) }
        if flag("showGPUItem") { components.append(MenuBarComponent(.gpu, visual: .stacked2, showLabel: true)) }
        if flag("showNetItem") { components.append(MenuBarComponent(.upload, .download, visual: .stacked2, showLabel: true)) }
        guard !components.isEmpty else { return .default }
        let compactOn = (defaults.object(forKey: "showCompactItem") as? Bool) ?? true
        if compactOn { return MenuBarConfig(components: MenuBarPreset.kompakt.components + components, displayMode: .combined) }
        return MenuBarConfig(components: components, displayMode: .separate)
    }
}
