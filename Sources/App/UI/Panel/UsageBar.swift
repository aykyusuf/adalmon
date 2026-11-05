import SwiftUI

/// İnce doluluk çubuğu. `ProgressView` yerine kendi çizimimiz: daha ince ve ImageRenderer ile de çizilir.
struct UsageBar: View {
    let fraction: Double
    var tint: Color = .accentColor
    var height: CGFloat = 4

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.1))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(tint)
                        .frame(width: max(fraction > 0 ? height : 0, geo.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: height)
            .accessibilityHidden(true)
    }
}
