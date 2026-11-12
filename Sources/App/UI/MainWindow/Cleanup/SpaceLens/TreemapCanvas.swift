import SwiftUI

/// Treemap çizimi (SwiftUI Canvas, animasyon döngüsü yok). Yerleşim `TreemapLayout`tan gelir; dokunuş kutuya eşlenir.
struct TreemapCanvas: View {
    static let otherID = "__other__"
    static let maxBoxes = 150

    let nodes: [SpaceNode]
    let selectedID: String?
    let onTap: (SpaceNode) -> Void

    static func items(for nodes: [SpaceNode]) -> [TreemapItem] {
        let measured = nodes.filter { $0.isMeasured && $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        var items = measured.prefix(maxBoxes).map { TreemapItem(id: $0.id, value: Double($0.bytes)) }
        let rest = measured.dropFirst(maxBoxes).reduce(UInt64(0)) { $0 + $1.bytes }
        if rest > 0 { items.append(TreemapItem(id: otherID, value: Double(rest))) }
        return items
    }

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let rects = TreemapLayout.layout(Self.items(for: nodes), in: bounds)
            let byID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            Canvas { context, _ in
                for (index, item) in rects.enumerated() {
                    let node = byID[item.id]
                    let box = item.rect.insetBy(dx: 1, dy: 1)
                    guard box.width > 0, box.height > 0 else { continue }
                    let shape = Path(roundedRect: box, cornerRadius: 3)
                    context.fill(shape, with: .color(color(for: node, index: index)))
                    if item.id == selectedID { context.stroke(shape, with: .color(.white), lineWidth: 2) }
                    if box.width > 64, box.height > 30 {
                        let title = node?.name ?? "Diğer"
                        let size = Format.bytes(node?.bytes ?? 0)
                        let text = Text("\(title)\n\(size)").font(.caption2).foregroundStyle(.white)
                        context.draw(context.resolve(text), in: box.insetBy(dx: 4, dy: 3))
                    }
                }
            }
            .contentShape(.rect)
            .onTapGesture { location in
                guard let hit = rects.first(where: { $0.rect.contains(location) }), let node = byID[hit.id] else { return }
                onTap(node)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Yer kaplayanlar haritası")
        .accessibilityHint("Ayrıntılar aşağıdaki listede")
    }

    private func color(for node: SpaceNode?, index: Int) -> Color {
        guard let node else { return Color.gray.opacity(0.55) }
        switch node.kind {
        case .file: return Color(hue: 0.58, saturation: 0.12, brightness: 0.55)
        default:
            let hue = Double((index * 37) % 100) / 100
            return Color(hue: hue, saturation: 0.55, brightness: 0.62)
        }
    }
}
