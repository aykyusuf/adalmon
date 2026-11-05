import AppKit
import Observation

/// Menü çubuğu öğeleri. `MenuBarConfig` tek öğe modundaysa tüm etkin widget'lar tek NSStatusItem'da,
/// ayrı öğeler modundaysa her widget kendi NSStatusItem'ında çizilir.
@MainActor
final class StatusBarController: NSObject {
    /// Tek öğe modu eski kompakt kapsülün adını kullanır; kullanıcının yerleştirdiği konum korunur.
    private static let combinedKey = "compact"

    private let model: AppModel
    private let onClick: (NSStatusBarButton) -> Void
    private var items: [String: NSStatusItem] = [:]
    /// Her öğenin son çizilen içeriği; değişmeyen öğe yeniden çizilmez (pil/CPU).
    private var lastKeys: [String: MenuBarRenderKey] = [:]

    init(model: AppModel, onClick: @escaping (NSStatusBarButton) -> Void) {
        self.model = model
        self.onClick = onClick
        super.init()
        // Değerler her ölçüm adımında bir kez çizilir (her model alanı değişiminde değil).
        model.onStep = { [weak self] in self?.render() }
        observeConfig()
        render()
    }

    /// Yalnızca menü çubuğu ayarlarını izle; ayar değişince hemen yeniden çiz.
    private func observeConfig() {
        withObservationTracking {
            _ = model.prefs.menuBar.config
        } onChange: { @Sendable [weak self] in
            Task { @MainActor in
                self?.lastKeys = [:]
                self?.render()
                self?.observeConfig()
            }
        }
    }

    private var appearanceObservers: [String: NSKeyValueObservation] = [:]
    private var appearanceNames: [String: NSAppearance.Name] = [:]

    private var tick = 0

    private func render() {
        tick &+= 1
        let config = model.prefs.menuBar.config
        let values = WidgetValues(model: model)
        let enabled = config.enabledComponents

        let groups: [(key: String, items: [MenuBarComponent])] =
            if config.displayMode == .combined || enabled.isEmpty {
                [(Self.combinedKey, enabled)]
            } else {
                enabled.map { ("item.\($0.id.uuidString)", [$0]) }
            }
        syncItems(keys: groups.map(\.key))

        for group in groups {
            guard let button = items[group.key]?.button else { continue }
            let key = MenuBarRenderKey(components: group.items, config: config, values: values)
            guard lastKeys[group.key] != key else { continue }
            lastKeys[group.key] = key
            let image = group.items.isEmpty
                ? MenuBarComposer.placeholderImage()
                : MenuBarComposer.bitmap(MenuBarComposer.image(for: group.items, config: config, values: values),
                                         appearance: button.effectiveAppearance,
                                         scale: button.window?.backingScaleFactor ?? 2)
            // Sabit genişlik: menü çubuğu yalnızca genişlik değişince yeniden yerleşim yapar (pil).
            let width = ceil(image.size.width) + 8
            if let item = items[group.key], abs(item.length - width) > 0.5 { item.length = width }
            button.image = image
            // Tooltip/erişilebilirlik metni saniyelik değişmesin; yalnızca farklıysa ve seyrek güncelle.
            if tick % 5 == 0 || button.toolTip == nil {
                let summary = MenuBarComposer.accessibilitySummary(for: group.items, values: values)
                if button.toolTip != summary {
                    button.toolTip = summary
                    button.setAccessibilityLabel(summary)
                }
            }
        }
    }

    /// Yalnızca kaybolan öğeleri kaldırır, yenileri ekler; mevcut öğeler (ve Cmd-sürükle konumları) yerinde kalır.
    private func syncItems(keys: [String]) {
        for (key, item) in items where !keys.contains(key) {
            NSStatusBar.system.removeStatusItem(item)
            items[key] = nil
            appearanceObservers[key] = nil
            appearanceNames[key] = nil
            lastKeys[key] = nil
        }
        // NSStatusBar yeni öğeyi solun en sonuna ekler; sırayı korumak için sağdan sola oluştur.
        for key in keys.reversed() where items[key] == nil {
            items[key] = makeItem(key: key)
        }
    }

    private func makeItem(key: String) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "adalmon.\(key)"
        item.button?.target = self
        item.button?.action = #selector(clicked(_:))
        item.button?.imagePosition = .imageOnly
        // Menü çubuğu açık/koyu (duvar kağıdına göre) değişince bitmap'i yeniden üret.
        // Yalnızca görünüm adı gerçekten değişirse (görüntü ataması da bu KVO'yu tetikler → döngü olmasın).
        appearanceObservers[key] = item.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] button, _ in
            Task { @MainActor in
                guard let self else { return }
                let name = button.effectiveAppearance.name
                guard self.appearanceNames[key] != name else { return }
                self.appearanceNames[key] = name
                self.lastKeys[key] = nil
                self.render()
            }
        }
        appearanceNames[key] = item.button?.effectiveAppearance.name
        return item
    }

    @objc private func clicked(_ sender: NSStatusBarButton) { onClick(sender) }
}
