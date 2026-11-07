import Foundation

/// Menü çubuğu ayarından hangi `NSStatusItem`'ların oluşacağı. Saf mantık (testli).
/// Sabitlenmiş cihaz pilleri her zaman KENDİ öğesinde çizilir (tek öğe modunda da); diğer bileşenler `displayMode`'a göre
/// ya tek "compact" öğesinde birleşir ya da her biri ayrı öğe olur.
enum StatusItemPlan {
    struct Group: Equatable {
        var key: String
        var items: [MenuBarComponent]
    }

    /// Tek öğe modu eski kompakt kapsülün adını kullanır; kullanıcının yerleştirdiği konum korunur.
    static let combinedKey = "compact"

    static func groups(for config: MenuBarConfig) -> [Group] {
        let enabled = config.enabledComponents
        guard !enabled.isEmpty else { return [Group(key: combinedKey, items: [])] }
        var groups: [Group] = []
        var usedKeys = Set<String>()
        for component in enabled {
            if let id = component.deviceID {
                var key = deviceKey(id)
                if !usedKeys.insert(key).inserted {
                    key = "device.\(component.id.uuidString)"
                    usedKeys.insert(key)
                }
                groups.append(Group(key: key, items: [component]))
            } else if config.displayMode == .combined {
                if let index = groups.firstIndex(where: { $0.key == combinedKey }) {
                    groups[index].items.append(component)
                } else {
                    groups.append(Group(key: combinedKey, items: [component]))
                    usedKeys.insert(combinedKey)
                }
            } else {
                let key = "item.\(component.id.uuidString)"
                usedKeys.insert(key)
                groups.append(Group(key: key, items: [component]))
            }
        }
        return groups
    }

    /// Cihaz öğesinin kalıcı anahtarı (`autosaveName` için güvenli karakterler): konumu cihaz kimliğiyle korunur.
    static func deviceKey(_ deviceID: String) -> String {
        let safe = deviceID.lowercased().unicodeScalars.map { scalar -> Character in
            (scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar))) ? Character(scalar) : "-"
        }
        return "device." + String(safe)
    }
}
