import SwiftUI

/// Yer kaplayanlar haritası: 3D hissi veren karolar (üstten ışık gradyanı, kenar parlaması, derinlik gölgesi). Yerleşim `TreemapLayout`tan gelir.
/// Animasyon yalnızca geçişte (tıklanan karodan içeri zoom, geri dönüşte tersi), ilk görünüşte (sıralı yerleşme) ve imleç üstündeyken
/// (karo hafif yükselip eğilir) çalışır; sürekli döngü / zamanlayıcı yoktur.
struct TreemapCanvas: View {
    static let otherID = "__other__"
    static let maxBoxes = 150

    /// Bir seviyenin görüntüsü (geçiş sırasında eski ve yeni aynı anda tutulur).
    struct Level: Identifiable, Equatable {
        let id = UUID()
        var path: String
        var nodes: [SpaceNode]
        var otherBytes: UInt64
        var anchor: UnitPoint = .center
        var forward = true
        var stagger = false
    }

    struct Hover: Equatable {
        var id: String
        /// -1...1 (karo içinde imlecin konumu, 0,5'lik adımlara yuvarlanır: her piksel için yeniden çizim olmasın).
        var tx: Double
        var ty: Double
    }

    private struct Key: Equatable {
        var path: String
        var nodes: [SpaceNode]
        var otherBytes: UInt64
    }

    let nodes: [SpaceNode]
    /// Küçük olduğu için tek tek tutulmayan öğelerin toplamı ("Diğer" kutusuna katılır).
    var otherBytes: UInt64 = 0
    let selectedID: String?
    /// Geçerli klasör yolu: değişince zoom geçişi çalışır (yalnızca bu yol değişince).
    var contextPath: String = ""
    /// Önizleme testleri için başlangıçta üstüne gelinmiş karo.
    var previewHoverID: String?
    let onTap: (SpaceNode) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: Level
    @State private var outgoing: Level?
    @State private var inShown = true
    @State private var outShown = true
    @State private var size = CGSize.zero
    @State private var hover: Hover?

    init(nodes: [SpaceNode], otherBytes: UInt64 = 0, selectedID: String?, contextPath: String = "", previewHoverID: String? = nil,
         onTap: @escaping (SpaceNode) -> Void) {
        self.nodes = nodes
        self.otherBytes = otherBytes
        self.selectedID = selectedID
        self.contextPath = contextPath
        self.previewHoverID = previewHoverID
        self.onTap = onTap
        _displayed = State(initialValue: Level(path: contextPath, nodes: nodes, otherBytes: otherBytes, stagger: true))
        _hover = State(initialValue: previewHoverID.map { Hover(id: $0, tx: -0.5, ty: -0.5) })
    }

    static func items(for nodes: [SpaceNode], otherBytes: UInt64 = 0) -> [TreemapItem] {
        let measured = nodes.filter { $0.isMeasured && $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        var items = measured.prefix(maxBoxes).map { TreemapItem(id: $0.id, value: Double($0.bytes)) }
        let rest = measured.dropFirst(maxBoxes).reduce(otherBytes) { $0 + $1.bytes }
        if rest > 0 { items.append(TreemapItem(id: otherID, value: Double(rest))) }
        return items
    }

    static func rects(for level: Level, in size: CGSize) -> [TreemapRect] {
        TreemapLayout.layout(items(for: level.nodes, otherBytes: level.otherBytes), in: CGRect(origin: .zero, size: size))
    }

    /// `id` kutusunun merkezi (0...1); kutu yoksa nil.
    static func anchor(of id: String, in level: Level, size: CGSize) -> UnitPoint? {
        guard size.width > 0, size.height > 0, let hit = rects(for: level, in: size).first(where: { $0.id == id }) else { return nil }
        return UnitPoint(x: hit.rect.midX / size.width, y: hit.rect.midY / size.height)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let outgoing {
                    TreemapLevelView(level: outgoing, size: proxy.size, selectedID: nil, hover: nil, reduceMotion: reduceMotion)
                        .id(outgoing.id)
                        .scaleEffect(outShown ? 1 : (outgoing.forward ? 1.7 : 0.45), anchor: outgoing.anchor)
                        .opacity(outShown ? 1 : 0)
                        .allowsHitTesting(false)
                }
                TreemapLevelView(level: displayed, size: proxy.size, selectedID: selectedID, hover: hover, reduceMotion: reduceMotion)
                    .id(displayed.id)
                    .scaleEffect(inShown ? 1 : (displayed.forward ? 0.55 : 1.5), anchor: displayed.anchor)
                    .opacity(inShown ? 1 : 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(.rect)
            .onContinuousHover { phase in updateHover(phase, size: proxy.size) }
            .onTapGesture { location in
                guard let hit = Self.rects(for: displayed, in: proxy.size).first(where: { $0.rect.contains(location) }),
                      let node = displayed.nodes.first(where: { $0.id == hit.id }) else { return }
                onTap(node)
            }
            .onAppear { size = proxy.size }
            .onChange(of: proxy.size) { _, new in size = new }
        }
        .onChange(of: Key(path: contextPath, nodes: nodes, otherBytes: otherBytes)) { _, new in apply(new) }
        .accessibilityElement()
        .accessibilityLabel("Yer kaplayanlar haritası")
        .accessibilityHint("Ayrıntılar aşağıdaki listede")
    }

    // MARK: Geçiş

    private func apply(_ key: Key) {
        hover = nil
        var next = Level(path: key.path, nodes: key.nodes, otherBytes: key.otherBytes)
        guard key.path != displayed.path, !reduceMotion, size.width > 0 else {
            displayed = next
            return
        }
        let old = displayed
        let forward = key.path.hasPrefix(old.path.hasSuffix("/") ? old.path : old.path + "/")
        if forward {
            // Tıklanan karodan içeri: eski seviyedeki karonun merkezinden büyür.
            next.anchor = Self.anchor(of: key.path, in: old, size: size) ?? .center
        } else {
            // Geri: çıkılan klasörün yeni seviyedeki karosuna doğru küçülür.
            next.anchor = Self.ancestorChild(of: key.path, toward: old.path).flatMap { Self.anchor(of: $0, in: next, size: size) } ?? .center
        }
        next.forward = forward
        var out = old
        out.anchor = next.anchor
        out.forward = forward
        outgoing = out
        displayed = next
        outShown = true
        inShown = false
        let outID = out.id
        Task { @MainActor in
            await Task.yield()
            withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
                inShown = true
                outShown = false
            }
            try? await Task.sleep(for: .milliseconds(450))
            if outgoing?.id == outID { outgoing = nil }
        }
    }

    /// `parent`ın, `descendant` yoluna giden doğrudan çocuğu.
    static func ancestorChild(of parent: String, toward descendant: String) -> String? {
        let base = parent.hasSuffix("/") ? parent : parent + "/"
        guard descendant.hasPrefix(base) else { return nil }
        let rest = descendant.dropFirst(base.count)
        let first = rest.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        return first.isEmpty ? nil : base + first
    }

    // MARK: Hover

    private func updateHover(_ phase: HoverPhase, size: CGSize) {
        guard !reduceMotion else { return }
        switch phase {
        case .active(let point):
            guard let hit = Self.rects(for: displayed, in: size).first(where: { $0.rect.contains(point) }),
                  hit.id != Self.otherID, displayed.nodes.first(where: { $0.id == hit.id })?.isMeasured == true else {
                if hover != nil { withAnimation(.spring(duration: 0.25)) { hover = nil } }
                return
            }
            func step(_ v: Double) -> Double { (v * 2).rounded() / 2 }
            let tx = step((point.x - hit.rect.midX) / max(1, hit.rect.width / 2))
            let ty = step((point.y - hit.rect.midY) / max(1, hit.rect.height / 2))
            let next = Hover(id: hit.id, tx: tx, ty: ty)
            if next != hover { withAnimation(.spring(duration: 0.25)) { hover = next } }
        case .ended:
            if hover != nil { withAnimation(.spring(duration: 0.25)) { hover = nil } }
        }
    }
}

/// Tek seviyenin karoları. İlk görünüşte (`stagger`) karolar sırayla yerleşir.
private struct TreemapLevelView: View {
    let level: TreemapCanvas.Level
    let size: CGSize
    let selectedID: String?
    let hover: TreemapCanvas.Hover?
    let reduceMotion: Bool
    @State private var shown: Bool

    init(level: TreemapCanvas.Level, size: CGSize, selectedID: String?, hover: TreemapCanvas.Hover?, reduceMotion: Bool) {
        self.level = level
        self.size = size
        self.selectedID = selectedID
        self.hover = hover
        self.reduceMotion = reduceMotion
        _shown = State(initialValue: !level.stagger || reduceMotion)
    }

    var body: some View {
        let rects = TreemapCanvas.rects(for: level, in: size)
        let byID = Dictionary(level.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let otherTotal = TreemapCanvas.items(for: level.nodes, otherBytes: level.otherBytes)
            .first { $0.id == TreemapCanvas.otherID }.map { UInt64($0.value) } ?? 0
        ZStack(alignment: .topLeading) {
            ForEach(Array(rects.enumerated()), id: \.element.id) { index, item in
                let node = byID[item.id]
                let isHovered = hover?.id == item.id
                TreemapTile(node: node, otherBytes: otherTotal, index: index, size: item.rect.insetBy(dx: 1.5, dy: 1.5).size,
                            selected: item.id == selectedID, hover: isHovered ? hover : nil)
                    .frame(width: max(0, item.rect.width - 3), height: max(0, item.rect.height - 3))
                    .scaleEffect(shown ? 1 : 0.8)
                    .opacity(shown ? 1 : 0)
                    .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.2).delay(min(0.45, Double(index) * 0.02)), value: shown)
                    .offset(x: item.rect.minX + 1.5, y: item.rect.minY + 1.5)
                    .zIndex(isHovered ? 2 : 0)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onAppear { if !shown { shown = true } }
    }
}

/// Tek karo: gradyan dolgu, üst ışık parlaması, kenar parlaması, derinlik gölgesi; hover'da yükselir ve imlece doğru eğilir.
private struct TreemapTile: View {
    let node: SpaceNode?
    let otherBytes: UInt64
    let index: Int
    let size: CGSize
    let selected: Bool
    let hover: TreemapCanvas.Hover?

    private var category: SpaceCategory { node.map(SpaceCategory.of) ?? .other }
    private var base: (h: Double, s: Double, b: Double) {
        let hsb = category.hsb
        // Bitişik karoları ayırmak için çok hafif parlaklık değişimi.
        return (hsb.h, hsb.s, hsb.b + Double(index % 3) * 0.035 - 0.035)
    }

    private func color(_ lift: Double) -> Color {
        Color(hue: base.h, saturation: max(0, base.s - lift * 0.25), brightness: min(1, max(0, base.b + lift)))
    }

    private var title: String { node?.name ?? "Diğer" }
    private var bytes: UInt64 { node?.bytes ?? otherBytes }

    var body: some View {
        let radius = max(2, min(10, min(size.width, size.height) / 4))
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let hovered = hover != nil
        ZStack(alignment: .topLeading) {
            shape.fill(LinearGradient(colors: [color(0.14), color(0), color(-0.18)], startPoint: .top, endPoint: .bottom))
            // Üstten gelen ışık.
            shape.fill(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.5)))
            // Kenar parlaması: üstte parlak, altta koyu çizgi.
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.08), .black.opacity(0.25)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
            if selected { shape.strokeBorder(.white, lineWidth: 2) }
            label
        }
        .clipShape(shape)
        .shadow(color: .black.opacity(hovered ? 0.5 : 0.32), radius: hovered ? 9 : 3, x: 0, y: hovered ? 7 : 2)
        .scaleEffect(hovered ? 1 + min(0.035, 10 / max(size.width, size.height, 1)) : 1)
        .rotation3DEffect(.degrees((hover?.tx ?? 0) * 4), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(-(hover?.ty ?? 0) * 4), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
    }

    /// Büyük karoda ad + boyut, orta karoda ad + boyut (küçük yazı), küçükte gizli.
    @ViewBuilder
    private var label: some View {
        if size.width >= 92, size.height >= 48 {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Text(Format.bytes(bytes)).font(.caption2).opacity(0.9).monospacedDigit()
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
            .padding(7)
        } else if size.width >= 60, size.height >= 32 {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).lineLimit(1).truncationMode(.middle)
                Text(Format.bytes(bytes)).opacity(0.9).monospacedDigit()
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
            .padding(4)
        }
    }
}

/// Haritadaki kategorilerin renk açıklaması (yalnızca görünen kategoriler).
struct TreemapLegend: View {
    let nodes: [SpaceNode]

    private var categories: [SpaceCategory] {
        let present = Set(nodes.filter(\.isMeasured).map(SpaceCategory.of))
        return SpaceCategory.allCases.filter { present.contains($0) }
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(categories, id: \.self) { category in
                HStack(spacing: 5) {
                    let hsb = category.hsb
                    Circle().fill(Color(hue: hsb.h, saturation: hsb.s, brightness: hsb.b)).frame(width: 9, height: 9)
                    Text(category.title).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .accessibilityHidden(true)
    }
}
