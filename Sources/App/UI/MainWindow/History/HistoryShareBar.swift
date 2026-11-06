import SwiftUI

/// Mobil ve Wi-Fi payını tek yatay çubukta gösterir (renge ek olarak çevresindeki metinler de ayırt eder).
struct HistoryShareBar: View {
    let mobileFraction: Double

    var body: some View {
        Capsule()
            .fill(MediumStyle.wifiColor)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(MediumStyle.mobileColor)
                        .frame(width: mobileFraction > 0 ? max(6, geo.size.width * min(1, mobileFraction)) : 0)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }
}
