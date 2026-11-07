import SwiftUI

/// 60 sn'lik alan grafiği; imleç gelince dikey çizgi, nokta ve "12 sn önce · %34" okuması çıkar (Canvas, Charts yok).
struct PanelHoverSparkline: View {
    let series: PanelSeries
    let tint: Color
    var height: CGFloat = 64
    var showsGrid = true
    /// Yalnızca test/önizleme: imleç yokken bu oranda (0...1) gelinmiş gibi okuma gösterir.
    var previewHover: Double?

    @State private var hover: Double?

    var body: some View {
        let hoverX = hover ?? previewHover
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            if showsGrid {
                for f in [0.0, 0.5, 1.0] {
                    var line = Path()
                    let y = 1 + (size.height - 2) * f
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(line, with: .color(.primary.opacity(0.07)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                }
            }
            guard !series.isEmpty, let last = series.times.last else { return }
            let range = series.resolvedScale.range(for: series.values)
            let span = max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
            let start = last.addingTimeInterval(-series.window)
            func point(_ i: Int) -> CGPoint {
                let x = series.times[i].timeIntervalSince(start) / series.window * size.width
                let t = (series.values[i] - range.lowerBound) / span
                return CGPoint(x: min(size.width, max(0, x)), y: 1 + (size.height - 2) * (1 - min(1, max(0, t))))
            }
            var line = Path()
            line.move(to: point(0))
            for i in 1..<series.values.count { line.addLine(to: point(i)) }
            var area = line
            area.addLine(to: CGPoint(x: point(series.values.count - 1).x, y: size.height))
            area.addLine(to: CGPoint(x: point(0).x, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(Gradient(colors: [tint.opacity(0.34), tint.opacity(0.02)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            if let hoverX, let r = series.readout(atFraction: hoverX) {
                let p = point(r.index)
                var rule = Path()
                rule.move(to: CGPoint(x: p.x, y: 0))
                rule.addLine(to: CGPoint(x: p.x, y: size.height))
                context.stroke(rule, with: .color(.primary.opacity(0.35)), lineWidth: 0.75)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(tint))
                context.stroke(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(.white.opacity(0.9)), lineWidth: 1)
            }
        }
        .frame(height: height)
        .overlay(alignment: .top) {
            GeometryReader { geo in
                if let hoverX, let r = series.readout(atFraction: hoverX) {
                    Text(r.text)
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.regularMaterial, in: .capsule)
                        .fixedSize()
                        .position(x: min(max(geo.size.width * hoverX, 60), geo.size.width - 60), y: 9)
                }
            }
            .allowsHitTesting(false)
        }
        .overlay {
            GeometryReader { geo in
                Color.clear
                    .contentShape(.rect)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p): hover = min(1, max(0, p.x / max(geo.size.width, 1)))
                        case .ended: hover = nil
                        }
                    }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Son 60 saniye grafiği")
        .accessibilityValue(series.values.last.map(series.text) ?? "veri yok")
    }
}
