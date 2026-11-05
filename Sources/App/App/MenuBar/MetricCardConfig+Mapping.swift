import Foundation

extension MetricCardConfig {
    /// Values in menu bar order with the network source applied.
    var renderFields: [DataField] {
        kind.renderOrder.filter(fields.contains).map(networkSource.resolve)
    }

    /// Stable identity per card slot, so status items and selection survive edits.
    static func componentID(_ kind: MetricCardKind, slot: Int) -> UUID {
        let index = MetricCardKind.allCases.firstIndex(of: kind) ?? 0
        return UUID(uuidString: String(format: "ADA10000-0000-4000-8000-0000000000%X%X", index, slot)) ?? UUID()
    }

    func components() -> [MenuBarComponent] {
        if kind == .connection {
            var c = MenuBarComponent(.connection, visual: .dot, colorMode: thresholdColor ? .threshold : .monochrome,
                                     showLabel: showLabel, showValue: false, layout: .inline)
            c.id = Self.componentID(kind, slot: 0)
            c.enabled = shown
            return [c]
        }
        var out: [MenuBarComponent] = []
        let f = renderFields
        if let first = f.first {
            var c = MenuBarComponent(first, f.count > 1 ? f[1] : nil, tertiary: f.count > 2 ? f[2] : nil,
                                     visual: layout.visual, colorMode: thresholdColor ? .threshold : .monochrome,
                                     colorTarget: .value, showLabel: showLabel, layout: layout)
            c.id = Self.componentID(kind, slot: 0)
            c.enabled = shown
            out.append(c)
        }
        if showGraph, let graph = kind.graphField {
            var c = MenuBarComponent(graph, visual: .sparkline, colorMode: thresholdColor ? .threshold : .monochrome,
                                     showLabel: f.isEmpty && showLabel, showValue: false, layout: layout)
            c.id = Self.componentID(kind, slot: 1)
            c.enabled = shown
            out.append(c)
        }
        return out
    }

    static func components(for cards: [MetricCardConfig]) -> [MenuBarComponent] {
        cards.flatMap { $0.components() }
    }

    /// Reads the simple cards back from a component list. Returns nil when the list was customized in the
    /// advanced editor and can't be represented by cards ("Gelişmiş düzende özelleştirildi").
    /// Card kinds missing from the list are appended hidden, with their default values.
    static func cards(from components: [MenuBarComponent]) -> [MetricCardConfig]? {
        var cards: [MetricCardConfig] = []
        var i = 0
        while i < components.count {
            let c = components[i]
            guard let layout = c.layout, let kind = MetricCardKind(field: c.primary),
                  !cards.contains(where: { $0.kind == kind }) else { return nil }
            var card = MetricCardConfig(kind, shown: c.enabled, fields: [], layout: layout,
                                  thresholdColor: c.colorMode == .threshold, showLabel: c.showLabel)
            var consumed = 1
            if c.visual == .sparkline {
                card.showGraph = true
            } else if kind != .connection {
                var canonical = Set<DataField>()
                for field in c.fields {
                    guard MetricCardKind(field: field) == kind else { return nil }
                    if let split = NetworkCardSource.split(field) {
                        card.networkSource = split.source
                        canonical.insert(split.canonical)
                    } else {
                        canonical.insert(field)
                    }
                }
                card.fields = kind.options.filter(canonical.contains)
                if i + 1 < components.count, components[i + 1].visual == .sparkline, components[i + 1].layout != nil,
                   MetricCardKind(field: components[i + 1].primary) == kind {
                    card.showGraph = true
                    consumed = 2
                }
            }
            let expected = card.components()
            let actual = Array(components[i..<(i + consumed)])
            guard expected.count == actual.count,
                  zip(expected, actual).allSatisfy({ $0.isEquivalent(to: $1) }) else { return nil }
            cards.append(card)
            i += consumed
        }
        for kind in MetricCardKind.allCases where !cards.contains(where: { $0.kind == kind }) {
            var card = defaultCard(kind)
            card.shown = false
            cards.append(card)
        }
        return cards
    }
}
