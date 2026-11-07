import SwiftUI

/// Sol listedeki küçük grafik: değerler 0...1; en yeni nokta sağda.
struct PerformanceSparkline: View {
    /// Kutucukta gösterilen örnek sayısı (en yeni sağda).
    static let capacity = 60

    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let step = w / CGFloat(max(1, Self.capacity - 1))
            let startX = w - CGFloat(max(0, values.count - 1)) * step
            let point: (Int, Double) -> CGPoint = { i, v in CGPoint(x: startX + CGFloat(i) * step, y: h - CGFloat(min(1, max(0, v))) * (h - 2) - 1) }
            ZStack {
                Path { p in
                    guard let first = values.first else { return }
                    p.move(to: CGPoint(x: startX, y: h))
                    p.addLine(to: point(0, first))
                    for (i, v) in values.enumerated().dropFirst() { p.addLine(to: point(i, v)) }
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.closeSubpath()
                }
                .fill(color.opacity(0.22))
                Path { p in
                    guard let first = values.first else { return }
                    p.move(to: point(0, first))
                    for (i, v) in values.enumerated().dropFirst() { p.addLine(to: point(i, v)) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}
