import CoreGraphics
import Foundation

extension MenuBarConfig {
    /// Ekrandaki sol→sağ sıraya (kimlik listesi) göre bileşenleri yeniden dizer (MENUBAR-01).
    /// Yalnızca etkin bileşenlerin yuvaları yeniden doldurulur; devre dışı bileşenler olduğu yerde kalır.
    /// Ekranda görünmeyen (listede olmayan / bilinmeyen kimlikli) etkin bileşenler kendi göreli sıralarıyla sona gider.
    static func reordered(_ components: [MenuBarComponent], screenOrder: [UUID]) -> [MenuBarComponent] {
        let enabled = components.filter(\.enabled)
        var byID: [UUID: MenuBarComponent] = [:]
        for component in enabled { byID[component.id] = component }
        var seen = Set<UUID>()
        var ordered: [MenuBarComponent] = []
        for id in screenOrder where seen.insert(id).inserted {
            if let component = byID[id] { ordered.append(component) }
        }
        ordered += enabled.filter { !seen.contains($0.id) }
        var next = ordered.makeIterator()
        return components.map { $0.enabled ? (next.next() ?? $0) : $0 }
    }

    /// Bileşen kimliği → ekran x konumu; eşit x'te kayıtlı sıra korunur.
    func syncedFromScreen(positions: [UUID: CGFloat]) -> MenuBarConfig {
        let index = Dictionary(components.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let order = positions
            .filter { index[$0.key] != nil && $0.value.isFinite }
            .sorted { ($0.value, index[$0.key] ?? 0) < ($1.value, index[$1.key] ?? 0) }
            .map(\.key)
        var copy = self
        copy.components = Self.reordered(components, screenOrder: order)
        return copy
    }
}

enum MenuBarOrderSyncResult: Equatable {
    case applied, unchanged, noItems
}

extension MenuBarConfigStore {
    /// Menü çubuğundan okunan konumları kaydedilmiş sıraya uygular (toptan değişiklik: yedek + "Geri al").
    @discardableResult
    func syncOrder(positions: [UUID: CGFloat]) -> MenuBarOrderSyncResult {
        guard !positions.isEmpty else { return .noItems }
        let new = config.syncedFromScreen(positions: positions)
        if new.isSameLayout(as: config) { return .unchanged }
        replaceConfig(new, reason: "Sırayı menü çubuğundan alma")
        return .applied
    }
}
