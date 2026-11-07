import Foundation

/// Menü çubuğu öğesi → panel türü. Saf mantık (testlenir).
enum PanelRouter {
    /// - Parameter components: tıklanan öğedeki (hit-test sonrası tek) bileşenler; ilki birincildir.
    static func kind(for components: [MenuBarComponent], clickMode: PanelClickMode) -> PanelKind {
        if clickMode == .combined { return .combined }
        guard let primary = components.first else { return .combined }
        return kind(for: primary)
    }

    /// Bileşenin kendi paneli: elle seçim > pil bileşeni > birincil alanın kategorisi.
    static func kind(for component: MenuBarComponent) -> PanelKind {
        if let override = component.panelKind { return override }
        return automaticKind(for: component)
    }

    static func automaticKind(for component: MenuBarComponent) -> PanelKind {
        if component.deviceID != nil || component.visual == .batteryCapsule { return .battery }
        return kind(for: component.primary.category)
    }

    static func kind(for category: FieldCategory) -> PanelKind {
        switch category {
        case .cpu: .cpu
        case .gpu: .gpu
        case .memory: .memory
        case .disk: .disk
        case .network, .mobile, .connection: .network
        case .temperature: .temperature
        case .battery: .battery
        }
    }

    /// Birleşik görünümde (tek öğe) tıklanan x konumuna düşen bileşen; bulunamazsa ilki.
    static func component(at x: CGFloat, in components: [MenuBarComponent], frames: [ClosedRange<CGFloat>]) -> MenuBarComponent? {
        guard !components.isEmpty else { return nil }
        if let i = frames.firstIndex(where: { $0.contains(x) }), components.indices.contains(i) { return components[i] }
        // Boşluğa denk geldiyse en yakın bileşen.
        let nearest = frames.enumerated().min { abs($0.element.lowerBound - x) < abs($1.element.lowerBound - x) }
        return nearest.flatMap { components.indices.contains($0.offset) ? components[$0.offset] : nil } ?? components.first
    }
}

/// Açık panel durumu ile yeni tıklama arasında ne yapılacağı.
struct PanelRoute: Equatable, Sendable {
    /// Durum öğesinin kimliği (StatusBarController grup anahtarı).
    var itemKey: String
    var kind: PanelKind
}

enum PanelToggle {
    enum Action: Equatable { case open, close, switchTo }

    /// Panel kapalıysa aç; aynı öğede aynı içerik açıksa kapat; aksi halde (başka öğe ya da aynı öğede başka bileşen) içeriği değiştir.
    static func next(current: PanelRoute?, click: PanelRoute) -> Action {
        guard let current else { return .open }
        return current == click ? .close : .switchTo
    }
}
