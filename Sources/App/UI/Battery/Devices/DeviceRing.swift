import SwiftUI

/// Cihaz simgesi + etrafında pil halkası.
struct DeviceRing: View {
    let device: DeviceBattery
    var size: CGFloat = 36
    var lineWidth: CGFloat = 3.5

    var body: some View {
        let tint = DevicePalette.tint(device)
        ZStack {
            Circle().stroke(.primary.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(device.summaryLevel ?? 0) / 100)
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: device.kind.symbol)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(device.isStale && !device.isConnected ? Color.secondary : Color.primary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
