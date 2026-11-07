import SwiftUI

/// Büyük değer + sağda ikincil bilgiler (metrik panellerinin üst kartı).
struct BigValueHeader<Trailing: View>: View {
    let value: String
    var unit: String?
    var caption: String?
    var tint: Color = .primary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let unit { Text(unit).font(.callout.weight(.medium)).foregroundStyle(.secondary) }
                }
                if let caption { Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

/// İki renkli yığılmış çubuk (kullanıcı + sistem).
struct SplitBar: View {
    let first: Double
    let second: Double
    let firstTint: Color
    let secondTint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let a = geo.size.width * min(1, max(0, first))
            let b = geo.size.width * min(1 - min(1, max(0, first)), max(0, second))
            Capsule().fill(.primary.opacity(0.1))
                .overlay(alignment: .leading) {
                    HStack(spacing: 1) {
                        Capsule().fill(firstTint).frame(width: max(first > 0 ? height : 0, a))
                        Capsule().fill(secondTint).frame(width: max(second > 0 ? height : 0, b))
                    }
                }
                .clipShape(.capsule)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
