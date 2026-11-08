import AppKit
import Observation

/// Menü çubuğu öğeleri (`StatusItemPlan`): tek öğe modunda etkin widget'lar tek NSStatusItem'da, ayrı modda her biri kendi
/// öğesinde; sabitlenmiş cihaz pilleri her iki modda da kendi öğesindedir.
@MainActor
final class StatusBarController: NSObject {
    private let model: AppModel
    private let onClick: (NSStatusBarButton, PanelRoute) -> Void
    private var items: [String: NSStatusItem] = [:]
    /// Her öğenin son çizilen içeriği; değişmeyen öğe yeniden çizilmez (pil/CPU).
    private var lastKeys: [String: MenuBarRenderKey] = [:]
    /// Her öğenin son çizilen bileşenleri ve görüntü genişliği (tıklama → panel eşlemesi için).
    private var groupComponents: [String: [MenuBarComponent]] = [:]
    private var imageWidths: [String: CGFloat] = [:]
    /// Mac pilinin canlı sıvı animasyonu (yalnızca pil öğesi menü çubuğundayken çalışır).
    private let batteryAnimator = BatteryLiquidAnimator()

    init(model: AppModel, onClick: @escaping (NSStatusBarButton, PanelRoute) -> Void) {
        self.model = model
        self.onClick = onClick
        super.init()
        // Değerler her ölçüm adımında bir kez çizilir (her model alanı değişiminde değil).
        model.onStep = { [weak self] in self?.render() }
        batteryAnimator.onMotionPolicyChange = { [weak self] in
            self?.lastKeys = [:]
            self?.render()
        }
        observeConfig()
        observeAgents()
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

    /// "Ajanlar" öğesi (Claude Code oturumları): bileşen düzeninden bağımsız, kendi anahtarı. Yalnızca özet değişince çizilir.
    static let agentsKey = "agents"
    private var lastAgents: AgentSummary?

    private func observeAgents() {
        withObservationTracking {
            _ = model.agents.monitor.summary
            _ = model.prefs.agentsEnabled
            _ = model.prefs.agentsInMenuBar
        } onChange: { @Sendable [weak self] in
            Task { @MainActor in
                self?.render()
                self?.observeAgents()
            }
        }
    }

    private var agentsVisible: Bool { model.prefs.agentsEnabled && model.prefs.agentsInMenuBar }

    private func renderAgentsItem() {
        guard agentsVisible, let button = items[Self.agentsKey]?.button else { lastAgents = nil; return }
        let summary = model.agents.monitor.summary
        guard lastAgents != summary || button.image == nil else { return }
        lastAgents = summary
        let image = NSImage(systemSymbolName: "person.3.fill", accessibilityDescription: "Claude ajanları")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = summary.working > 0 ? .imageLeading : .imageOnly
        button.title = summary.working > 0 ? "\(summary.working)" : ""
        let text = summary.working > 0 ? "Claude ajanları: \(summary.working) çalışıyor" : "Claude ajanları: çalışan yok"
        button.toolTip = text
        button.setAccessibilityLabel(text)
    }

    private var appearanceObservers: [String: NSKeyValueObservation] = [:]
    private var appearanceNames: [String: NSAppearance.Name] = [:]

    private var tick = 0

    private func render() {
        tick &+= 1
        let config = model.prefs.menuBar.config
        let values = WidgetValues(model: model)

        let groups = StatusItemPlan.groups(for: config)
        syncItems(keys: groups.map(\.key) + (agentsVisible ? [Self.agentsKey] : []))
        renderAgentsItem()
        let animatedKey = animatedGroupKey(groups, values: values)
        if animatedKey == nil, batteryAnimator.target != nil { batteryAnimator.clear() }

        for group in groups {
            groupComponents[group.key] = group.items
            guard let button = items[group.key]?.button else { continue }
            let key = MenuBarRenderKey(components: group.items, config: config, values: values)
            guard lastKeys[group.key] != key else { continue }
            lastKeys[group.key] = key
            let appearance = button.effectiveAppearance
            let scale = button.window?.backingScaleFactor ?? 2
            let image: NSImage
            if group.key == animatedKey, let battery = values.battery,
               let index = MenuBarComposer.animatedBatteryIndex(in: group.items),
               let rect = MenuBarComposer.animatedBatteryRect(in: group.items, config: config, values: values) {
                // Taban (gövdesiz) bir kez çizilir; kareler animatörde önceden hazırlanır.
                let base = MenuBarComposer.bitmap(MenuBarComposer.image(for: group.items, config: config, values: values, battery: .layered),
                                                  appearance: appearance, scale: scale)
                let frameKey = BatteryFrameKey(state: battery, options: group.items[index].battery,
                                               appearance: appearance.name, scale: scale)
                image = batteryAnimator.show(.init(itemKey: group.key, button: button, base: base, rect: rect,
                                                    frameKey: frameKey, appearance: appearance, bolt: battery))
            } else if group.items.isEmpty {
                image = MenuBarComposer.placeholderImage()
            } else {
                image = MenuBarComposer.bitmap(MenuBarComposer.image(for: group.items, config: config, values: values),
                                               appearance: appearance, scale: scale)
            }
            // Sabit genişlik: menü çubuğu yalnızca genişlik değişince yeniden yerleşim yapar (pil).
            let width = ceil(image.size.width) + 8
            if let item = items[group.key], abs(item.length - width) > 0.5 { item.length = width }
            button.image = image
            imageWidths[group.key] = image.size.width
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

    /// Canlı sıvıyla çizilecek öğe: Mac pili kapsülünü içeren ilk öğe (pil okunuyorsa ve hareket izinliyse).
    private func animatedGroupKey(_ groups: [StatusItemPlan.Group], values: WidgetValues) -> String? {
        guard values.battery != nil else { return nil }
        for group in groups {
            guard let index = MenuBarComposer.animatedBatteryIndex(in: group.items) else { continue }
            return batteryAnimator.motionAllowed(group.items[index].battery.motion) ? group.key : nil
        }
        return nil
    }

    /// Yalnızca kaybolan öğeleri kaldırır, yenileri ekler; mevcut öğeler (ve Cmd-sürükle konumları) yerinde kalır.
    private func syncItems(keys: [String]) {
        for (key, item) in items where !keys.contains(key) {
            if batteryAnimator.target?.itemKey == key { batteryAnimator.clear() }
            NSStatusBar.system.removeStatusItem(item)
            items[key] = nil
            appearanceObservers[key] = nil
            appearanceNames[key] = nil
            lastKeys[key] = nil
            groupComponents[key] = nil
            imageWidths[key] = nil
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

    /// Tüm öğelerin ekran dikdörtgenleri (panel dış-tıklama izlemesi bunları hariç tutar).
    func buttonFrames() -> [NSRect] {
        items.values.compactMap { item in
            guard let button = item.button, let window = button.window else { return nil }
            return window.convertToScreen(button.convert(button.bounds, to: nil))
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let key = items.first(where: { $0.value.button === sender })?.key else { return }
        if key == Self.agentsKey {
            onClick(sender, PanelRoute(itemKey: key, kind: .agents))
            return
        }
        let config = model.prefs.menuBar.config
        let components = groupComponents[key] ?? []
        var target = components
        // Birleşik (tek öğe) modda tıklanan x konumundaki bileşenin paneli açılır.
        if components.count > 1, config.clickMode == .perMetric, let event = NSApp.currentEvent {
            let x = sender.convert(event.locationInWindow, from: nil).x - (sender.bounds.width - (imageWidths[key] ?? sender.bounds.width)) / 2
            let frames = MenuBarComposer.frames(of: components, config: config, values: WidgetValues(model: model))
            if let hit = PanelRouter.component(at: x, in: components, frames: frames) { target = [hit] }
        }
        let kind = PanelRouter.kind(for: target, clickMode: config.clickMode)
        onClick(sender, PanelRoute(itemKey: key, kind: kind, focusDeviceID: PanelRouter.focusDeviceID(for: target)))
    }
}
