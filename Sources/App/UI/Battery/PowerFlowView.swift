import AppKit
import SwiftUI

extension FlowTint {
    var color: Color {
        switch self {
        case .green: .green
        case .blue: .blue
        case .orange: .orange
        case .red: .red
        case .teal: .teal
        case .gray: .gray
        }
    }
}

// MARK: Geometri (saf)

/// Kübik Bézier; kenar yolu ve ok yönü için.
struct FlowCurve: Equatable {
    var p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint

    func point(_ t: Double) -> CGPoint {
        let u = 1 - t
        let x = u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p3.x
        let y = u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p3.y
        return CGPoint(x: x, y: y)
    }

    /// Birim olmayan teğet (kaynaktan hedefe).
    func tangent(_ t: Double) -> CGVector {
        let u = 1 - t
        let dx = 3 * u * u * (c1.x - p0.x) + 6 * u * t * (c2.x - c1.x) + 3 * t * t * (p3.x - c2.x)
        let dy = 3 * u * u * (c1.y - p0.y) + 6 * u * t * (c2.y - c1.y) + 3 * t * t * (p3.y - c2.y)
        return CGVector(dx: dx, dy: dy)
    }

    var path: Path {
        Path { $0.move(to: p0); $0.addCurve(to: p3, control1: c1, control2: c2) }
    }
}

/// Deterministik ızgara: sütunlar -1/0/1 (Adaptör · Mac · aygıtlar), satırlar 0/1 (Mac satırı · Pil satırı).
/// Aygıt yoksa Adaptör–Mac–Pil grubu yatayda ortalanır. Kenarlar daire çevreleri arasında düz çizgilerdir.
enum PowerFlowGeometry {
    static let nodeRadius: CGFloat = 26
    static let gap: CGFloat = 4
    static let labelHeight: CGFloat = 30
    static let singleLineLabelHeight: CGFloat = 18
    static let labelSpacing: CGFloat = 3
    static let rowGap: CGFloat = 100
    static let edgeInset: CGFloat = 40
    static let maxColumnSpacing: CGFloat = 150

    static func rowY(_ row: Int) -> CGFloat { labelHeight + labelSpacing + nodeRadius + CGFloat(row) * rowGap }

    static func height(for model: PowerFlowModel) -> CGFloat {
        let bottomLabel = model.nodes.contains { $0.row == 1 && $0.id != .battery } ? labelHeight : singleLineLabelHeight
        return rowY(1) + nodeRadius + labelSpacing + bottomLabel + 2
    }

    static func columnSpacing(width: CGFloat) -> CGFloat { min(maxColumnSpacing, max(60, (width - 2 * edgeInset) / 2)) }

    static func center(_ n: FlowNode, in model: PowerFlowModel, width: CGFloat) -> CGPoint {
        let shift: CGFloat = model.hasDeviceNodes ? 0 : 0.5 // aygıt yok: Adaptör–Mac grubu ortalanır
        return CGPoint(x: width / 2 + (CGFloat(n.column) + shift) * columnSpacing(width: width), y: rowY(n.row))
    }

    static func curve(for edge: FlowEdge, in model: PowerFlowModel, width: CGFloat) -> FlowCurve? {
        guard let a = model.node(edge.from), let b = model.node(edge.to) else { return nil }
        let pa = center(a, in: model, width: width), pb = center(b, in: model, width: width)
        let dx = pb.x - pa.x, dy = pb.y - pa.y
        let len = max(0.001, (dx * dx + dy * dy).squareRoot())
        let r = nodeRadius + gap
        let p0 = CGPoint(x: pa.x + dx / len * r, y: pa.y + dy / len * r)
        let p3 = CGPoint(x: pb.x - dx / len * r, y: pb.y - dy / len * r)
        let c1 = CGPoint(x: p0.x + (p3.x - p0.x) / 3, y: p0.y + (p3.y - p0.y) / 3)
        let c2 = CGPoint(x: p0.x + (p3.x - p0.x) * 2 / 3, y: p0.y + (p3.y - p0.y) * 2 / 3)
        return FlowCurve(p0: p0, c1: c1, c2: c2, p3: p3)
    }

    /// Etiket kenarın ortasında durur; dikey kenarda noktaların görünmesi için yanına (sola) kayar.
    static func labelCenter(for curve: FlowCurve) -> CGPoint {
        let mid = curve.point(0.5)
        return abs(curve.p0.x - curve.p3.x) < 2 ? CGPoint(x: mid.x - 38, y: mid.y) : mid
    }
}

final class FlowClock: @unchecked Sendable {
    private var last: Date?
    private(set) var phases: [String: Double] = [:]

    func advance(to date: Date, edges: [FlowEdge]) {
        defer { last = date }
        guard let last else { return }
        let dt = min(0.1, max(0, date.timeIntervalSince(last))) // uzun duraklamadan sonra sıçrama yok
        for e in edges where e.isActive {
            let spacing = e.dotSpacing
            var p = (phases[e.id] ?? 0) + e.speed * dt
            if p > spacing { p -= spacing * (p / spacing).rounded(.down) }
            phases[e.id] = p
        }
    }

    /// Duraklayınca: bir sonraki kare büyük dt görmesin.
    func pause() { last = nil }
}

// MARK: Çizim

/// Kenar çizgileri + akan noktalar. Tek stroke / kenar (kesikli çizgi, yuvarlak uç), düğümler bunun dışında statik.
struct PowerFlowCanvas {
    enum Motion { case dots, arrows }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, model: PowerFlowModel, phases: [String: Double], motion: Motion, hovered: String?) {
        // Fişte ama pil boşta (dolu / şarj sınırı): adaptör → pil bağlantısı silik kesikli çizgi (akış yok).
        if model.mode == .pluggedIdle,
           let ghost = PowerFlowGeometry.curve(for: FlowEdge(id: "ghost", kind: .adapterToBattery, from: .adapter, to: .battery, watts: 0, isActive: false,
                                                             label: "", tint: .gray, tooltip: ""), in: model, width: size.width) {
            ctx.stroke(ghost.path, with: .color(Color.primary.opacity(0.10)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 5]))
        }
        for e in model.edges {
            guard let curve = PowerFlowGeometry.curve(for: e, in: model, width: size.width) else { continue }
            let path = curve.path
            let color = e.tint.color
            let hot = hovered == e.id
            if e.isActive {
                ctx.stroke(path, with: .color(color.opacity(hot ? 0.34 : 0.20)), style: StrokeStyle(lineWidth: max(2, e.thickness * 0.8), lineCap: .round))
                switch motion {
                case .dots:
                    let phase = phases[e.id] ?? 0
                    ctx.stroke(path, with: .color(color), style: StrokeStyle(
                        lineWidth: e.thickness + 1, lineCap: .round, dash: [0.01, e.dotSpacing], dashPhase: -phase))
                case .arrows:
                    for t in [0.32, 0.56, 0.8] { chevron(&ctx, curve, t, color, e.thickness) }
                }
            } else {
                ctx.stroke(path, with: .color(Color.primary.opacity(hot ? 0.22 : 0.12)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 5]))
            }
        }
    }

    private static func chevron(_ ctx: inout GraphicsContext, _ c: FlowCurve, _ t: Double, _ color: Color, _ thickness: Double) {
        let p = c.point(t), v = c.tangent(t)
        let len = max(0.001, (v.dx * v.dx + v.dy * v.dy).squareRoot())
        let ux = v.dx / len, uy = v.dy / len
        let s = 3.5 + thickness * 0.5
        let back = CGPoint(x: p.x - ux * s, y: p.y - uy * s)
        var path = Path()
        path.move(to: CGPoint(x: back.x - uy * s, y: back.y + ux * s))
        path.addLine(to: p)
        path.addLine(to: CGPoint(x: back.x + uy * s, y: back.y - ux * s))
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }
}

// MARK: Pencere görünürlüğü

/// Pencere ekranda görünür mü (örtülü/küçültülmüş/kapalı değil)? Animasyon yalnız görünürken çalışır.
private struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var visible: Bool

    func makeNSView(context: Context) -> Tracker {
        let t = Tracker()
        t.onChange = { v in if v != visible { visible = v } }
        return t
    }

    func updateNSView(_ nsView: Tracker, context: Context) {
        nsView.onChange = { v in if v != visible { visible = v } }
    }

    final class Tracker: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { report(false); return }
            let names: [Notification.Name] = [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                                              NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        guard let window else { self?.report(false); return }
                        self?.report(name != NSWindow.willCloseNotification && Self.isVisible(window))
                    }
                }
            }
            report(Self.isVisible(window))
        }

        private static func isVisible(_ w: NSWindow) -> Bool {
            w.isVisible && !w.isMiniaturized && w.occlusionState.contains(.visible)
        }

        private func report(_ v: Bool) { onChange?(v) }
    }
}

// MARK: Görünüm

/// Animasyonlu güç akışı: Adaptör, Mac, Pil (+ dış aksesuarlar) ve aralarındaki yönlü, watt orantılı akış.
/// Animasyon yalnızca görünürken (ekranda, pencere görünür, kaydırmada görünür, Hareketi azalt kapalı, en az bir aktif kenar) ve
/// ≤ 30 fps çalışır; aksi halde TimelineView durur (CPU sıfır). Hareketi azalt açıkken durağan oklar çizilir.
struct PowerFlowView: View {
    let model: PowerFlowModel
    var forceAnimating: Bool?
    var fixedPhase: Double?
    var showsHoverCaption = true
    var forceReduceMotion = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var scrollVisible = true
    @State private var windowVisible = false
    @State private var hover: String?
    @State private var clock = FlowClock()

    init(model: PowerFlowModel, forceAnimating: Bool? = nil, fixedPhase: Double? = nil, showsHoverCaption: Bool = true, forceReduceMotion: Bool = false) {
        self.model = model
        self.forceAnimating = forceAnimating
        self.fixedPhase = fixedPhase
        self.showsHoverCaption = showsHoverCaption
        self.forceReduceMotion = forceReduceMotion
    }

    private var animating: Bool {
        if let forceAnimating { return forceAnimating }
        return appeared && scrollVisible && windowVisible && !reduceMotion && !forceReduceMotion && model.hasMotion
    }

    private var motion: PowerFlowCanvas.Motion { reduceMotion || forceReduceMotion ? .arrows : .dots }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .topLeading) {
                    edgeLayer
                    ForEach(model.edges) { edge in edgeLabel(edge, width: width) }
                    ForEach(model.nodes) { node in nodeView(node, width: width) }
                }
            }
            .frame(height: PowerFlowGeometry.height(for: model))
            if !model.chips.isEmpty { chipRow }
            if showsHoverCaption {
                Text(hoverText ?? "Ayrıntı için bir düğümün ya da değerin üzerine gel")
                    .font(.caption2).foregroundStyle(hoverText == nil ? .tertiary : .secondary)
                    .multilineTextAlignment(.center).lineLimit(3).frame(maxWidth: .infinity, minHeight: 30, alignment: .top)
                    .animation(nil, value: hover)
            }
        }
        .background(WindowVisibilityReader(visible: $windowVisible).frame(width: 0, height: 0))
        .onAppear { appeared = true }
        .onDisappear { appeared = false; clock.pause() }
        .onScrollVisibilityChange(threshold: 0.05) { scrollVisible = $0 }
        .onChange(of: animating) { _, now in if !now { clock.pause() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Güç akışı")
        .accessibilityValue(model.summary)
    }

    private var hoverText: String? {
        guard let hover else { return nil }
        if let n = model.nodes.first(where: { "n." + String(describing: $0.id) == hover }) { return n.tooltip.replacingOccurrences(of: "\n", with: " · ") }
        if let e = model.edges.first(where: { "e." + $0.id == hover }) { return e.tooltip.replacingOccurrences(of: "\n", with: " · ") }
        if let c = model.chips.first(where: { "c." + $0.id == hover }) { return c.tooltip.replacingOccurrences(of: "\n", with: " · ") }
        return nil
    }

    @ViewBuilder
    private var edgeLayer: some View {
        if animating {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { tl in
                Canvas { ctx, size in
                    clock.advance(to: tl.date, edges: model.edges)
                    PowerFlowCanvas.draw(&ctx, size: size, model: model, phases: clock.phases, motion: .dots, hovered: edgeHover)
                }
            }
        } else {
            Canvas { ctx, size in
                let phases = fixedPhase.map { p in Dictionary(uniqueKeysWithValues: model.edges.map { ($0.id, p) }) } ?? clock.phases
                PowerFlowCanvas.draw(&ctx, size: size, model: model, phases: phases, motion: fixedPhase != nil ? .dots : motion, hovered: edgeHover)
            }
        }
    }

    private var edgeHover: String? { hover.flatMap { $0.hasPrefix("e.") ? String($0.dropFirst(2)) : nil } }

    private func edgeLabel(_ edge: FlowEdge, width: CGFloat) -> some View {
        let mid = PowerFlowGeometry.curve(for: edge, in: model, width: width).map(PowerFlowGeometry.labelCenter) ?? .zero
        return Text(edge.label)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded)).monospacedDigit()
            .foregroundStyle(edge.isActive ? edge.tint.color : .secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.regularMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(edge.tint.color.opacity(edge.isActive ? 0.45 : 0.18), lineWidth: 0.75))
            .position(mid)
            .onHover { hover = $0 ? "e." + edge.id : (hover == "e." + edge.id ? nil : hover) }
            .help(edge.tooltip)
    }

    private func nodeView(_ node: FlowNode, width: CGFloat) -> some View {
        let c = PowerFlowGeometry.center(node, in: model, width: width)
        let key = "n." + String(describing: node.id)
        let singleLine = node.id == .battery
        let labelH = singleLine ? PowerFlowGeometry.singleLineLabelHeight : PowerFlowGeometry.labelHeight
        let spacing = PowerFlowGeometry.labelSpacing
        let dy = (labelH + spacing) / 2 * (node.labelSide == .below ? 1 : -1)
        let label = Group {
            if singleLine {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(node.value).font(.system(.callout, design: .rounded, weight: .semibold)).monospacedDigit()
                    Text("· " + node.caption).font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 0) {
                    Text(node.value).font(.system(.callout, design: .rounded, weight: .semibold)).monospacedDigit().minimumScaleFactor(0.8)
                    Text(node.caption).font(.caption2).foregroundStyle(.secondary).truncationMode(.middle)
                }
            }
        }
        .lineLimit(1)
        .frame(width: singleLine ? 150 : 100, height: labelH, alignment: node.labelSide == .above ? .bottom : .top)
        return VStack(spacing: spacing) {
            if node.labelSide == .above { label }
            nodeDisc(node, highlighted: hover == key)
            if node.labelSide == .below { label }
        }
        .opacity(node.isActive || node.id == .battery || node.id == .mac ? 1 : 0.5)
        .position(x: c.x, y: c.y + dy)
        .contentShape(Rectangle())
        .onHover { hover = $0 ? key : (hover == key ? nil : hover) }
        .help(node.tooltip)
    }

    private func nodeDisc(_ node: FlowNode, highlighted: Bool) -> some View {
        let tint = node.tint.color
        let size = PowerFlowGeometry.nodeRadius * 2
        return ZStack {
            Circle().fill(tint.opacity(highlighted ? 0.26 : 0.15))
            if let level = node.level {
                FlowBatteryGlyph(level: level, tint: tint, charging: node.isCharging)
            } else {
                Image(systemName: node.symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(tint.opacity(highlighted ? 0.8 : 0), lineWidth: 1.5))
    }

    private var chipRow: some View {
        FlowChipWrap(spacing: 5) {
            Text("Bağlı:").font(.caption2).foregroundStyle(.tertiary)
            ForEach(model.chips) { chip in
                let key = "c." + chip.id
                Label(chip.title, systemImage: chip.symbol)
                    .font(.caption2).foregroundStyle(hover == key ? .primary : .secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.primary.opacity(hover == key ? 0.12 : 0.07), in: .capsule)
                    .onHover { hover = $0 ? key : (hover == key ? nil : hover) }
                    .help(chip.tooltip)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Yatay kapsül pil simgesi (uçta çıkıntı); seviyeye kadar dolu, şarjda şimşek bindirmeli.
struct FlowBatteryGlyph: View {
    let level: Int
    let tint: Color
    let charging: Bool

    private let bodyW: CGFloat = 30, bodyH: CGFloat = 15

    var body: some View {
        let fraction = CGFloat(min(100, max(0, level))) / 100
        let inset: CGFloat = 2
        let fillW = level <= 0 ? 0 : max(3, (bodyW - 2 * inset) * fraction)
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous).strokeBorder(tint.opacity(0.85), lineWidth: 1.5)
                RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(tint)
                    .frame(width: fillW, height: bodyH - 2 * inset - 1).padding(.leading, inset + 0.5)
                if charging {
                    Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 0.8)
                        .frame(width: bodyW)
                }
            }
            .frame(width: bodyW, height: bodyH)
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 1.5, topTrailingRadius: 1.5)
                .fill(tint.opacity(0.85)).frame(width: 2.5, height: 6)
        }
        .accessibilityHidden(true)
    }
}

/// Çipleri satır satır dizer, her satırı ortalar.
private struct FlowChipWrap: Layout {
    var spacing: CGFloat = 5

    private func rows(_ width: CGFloat, _ subviews: Subviews) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var x: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let w = v.sizeThatFits(.unspecified).width
            if x > 0, x + w > width { rows.append([]); x = 0 }
            rows[rows.count - 1].append(i)
            x += w + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rs = rows(width, subviews)
        var height: CGFloat = 0, maxW: CGFloat = 0
        for r in rs {
            let sizes = r.map { subviews[$0].sizeThatFits(.unspecified) }
            height += (sizes.map(\.height).max() ?? 0) + (height > 0 ? spacing : 0)
            maxW = max(maxW, sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1)))
        }
        return CGSize(width: width.isFinite ? width : maxW, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for r in rows(bounds.width, subviews) {
            let sizes = r.map { subviews[$0].sizeThatFits(.unspecified) }
            let rowH = sizes.map(\.height).max() ?? 0
            var x = bounds.midX - (sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1))) / 2
            for (k, i) in r.enumerated() {
                subviews[i].place(at: CGPoint(x: x, y: y + (rowH - sizes[k].height) / 2), proposal: .unspecified)
                x += sizes[k].width + spacing
            }
            y += rowH + spacing
        }
    }
}
