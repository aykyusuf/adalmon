import SwiftUI

/// Kart içi mini alan grafiği. `Canvas` ile çizilir (Charts yok): ölçüm başına tek `Path`, animasyon yok.
/// Geçmiş sağa yaslıdır; az örnek varsa grafik sağdan büyür.
struct PanelSparkline: View {
    let values: [Double]
    let tint: Color
    var scale: PanelSparklineScale = .fixed(0...1)
    var capacity = AppModel.historyLength

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, size.width > 0, size.height > 0 else { return }
            let range = scale.range(for: values)
            let span = max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
            let step = size.width / CGFloat(max(capacity - 1, 1))
            let inset: CGFloat = 1
            let usable = size.height - inset * 2
            let lastX = size.width
            func point(_ index: Int) -> CGPoint {
                let x = lastX - CGFloat(values.count - 1 - index) * step
                let t = (values[index] - range.lowerBound) / span
                return CGPoint(x: x, y: inset + usable * (1 - CGFloat(min(1, max(0, t)))))
            }
            var line = Path()
            line.move(to: point(0))
            for i in 1..<values.count { line.addLine(to: point(i)) }

            var area = line
            area.addLine(to: CGPoint(x: lastX, y: size.height))
            area.addLine(to: CGPoint(x: point(0).x, y: size.height))
            area.closeSubpath()

            context.fill(area, with: .linearGradient(
                Gradient(colors: [tint.opacity(0.32), tint.opacity(0.02)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(tint),
                           style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
