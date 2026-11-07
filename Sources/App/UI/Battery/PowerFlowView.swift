import AppKit
import SwiftUI

extension FlowTint {
    var color: Color {
        switch self {
        case .green: .green
        case .blue: .blue
        case .orange: .orange
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

enum PowerFlowGeometry {
    static let nodeRadius: CGFloat = 19
    /// Düğüm halkasından kenarın başladığı boşluk.
    static let gap: CGFloat = 4

    static func center(_ n: FlowNode, width: CGFloat) -> CGPoint {
        let half: CGFloat = 50
        return CGPoint(x: min(max(n.x * width, half), max(half, width - half)), y: n.y)
    }

    /// Kenarın eğrisi: yatay komşular yatay teğetle, dikey komşular dikey teğetle bağlanır.
    static func curve(for edge: FlowEdge, in model: PowerFlowModel, width: CGFloat) -> FlowCurve? {
        guard let a = model.node(edge.from), let b = model.node(edge.to) else { return nil }
        let pa = center(a, width: width), pb = center(b, width: width)
        let r = nodeRadius + gap
        if abs(pa.x - pb.x) < 2 {
            let dir: CGFloat = pb.y > pa.y ? 1 : -1
            let p0 = CGPoint(x: pa.x, y: pa.y + dir * r), p3 = CGPoint(x: pb.x, y: pb.y - dir * r)
            let m = (p0.y + p3.y) / 2
            return FlowCurve(p0: p0, c1: CGPoint(x: p0.x, y: m), c2: CGPoint(x: p3.x, y: m), p3: p3)
        }
        let dir: CGFloat = pb.x > pa.x ? 1 : -1
        let p0 = CGPoint(x: pa.x + dir * r, y: pa.y), p3 = CGPoint(x: pb.x - dir * r, y: pb.y)
        let m = (p0.x + p3.x) / 2
        return FlowCurve(p0: p0, c1: CGPoint(x: m, y: p0.y), c2: CGPoint(x: m, y: p3.y), p3: p3)
    }
}

// MARK: Faz saati

/// Kenar başına nokta fazını (pt) hızla İNTEGRE eder: hız değişince noktalar sıçramaz. Gözlemlenmez; yalnız Canvas çizerken yazılır.
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
    /// Test/önizleme: nil = normal geçit; true/false = geçidi atla.
    var forceAnimating: Bool?
    /// Test/önizleme: tüm noktaları bu faza (pt) kilitler.
    var fixedPhase: Double?
    var showsHoverCaption = true
    /// Test/önizleme: Hareketi azalt görünümünü zorla (durağan oklar).
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
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .topLeading) {
                    edgeLayer
                    ForEach(model.edges) { edge in edgeLabel(edge, width: width) }
                    ForEach(model.nodes) { node in nodeView(node, width: width) }
                }
            }
            .frame(height: PowerFlowModel.height)
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
        return nil
    }

    // MARK: Kenarlar

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
        let mid = PowerFlowGeometry.curve(for: edge, in: model, width: width)?.point(0.5) ?? .zero
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

    // MARK: Düğümler

    private func nodeView(_ node: FlowNode, width: CGFloat) -> some View {
        let c = PowerFlowGeometry.center(node, width: width)
        let key = "n." + String(describing: node.id)
        let labelH: CGFloat = 30, circle = PowerFlowGeometry.nodeRadius * 2
        let block = circle + 2 + labelH
        let dy: CGFloat = node.labelSide == .below ? (block / 2 - circle / 2) : -(block / 2 - circle / 2)
        let label = VStack(spacing: 0) {
            Text(node.value).font(.system(.callout, design: .rounded, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Text(node.caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .frame(width: 96, height: labelH)
        return VStack(spacing: 2) {
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
        return ZStack {
            Circle().fill(tint.opacity(highlighted ? 0.26 : 0.15))
            if let level = node.level {
                Circle().stroke(Color.primary.opacity(0.10), lineWidth: 3.5)
                Circle().trim(from: 0, to: CGFloat(level) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round)).rotationEffect(.degrees(-90))
                Image(systemName: node.isActive && node.tint == .green ? "bolt.fill" : "battery.100percent")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            } else {
                Image(systemName: node.symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(tint)
            }
        }
        .frame(width: PowerFlowGeometry.nodeRadius * 2, height: PowerFlowGeometry.nodeRadius * 2)
        .overlay(Circle().strokeBorder(tint.opacity(highlighted ? 0.8 : 0), lineWidth: 1.5))
    }
}
