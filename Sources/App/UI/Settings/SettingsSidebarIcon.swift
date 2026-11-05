import SwiftUI

/// Sistem Ayarları tarzı renkli yuvarlak kare simge.
struct SettingsSidebarIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(tint.gradient, in: .rect(cornerRadius: 6))
            .accessibilityHidden(true)
    }
}
