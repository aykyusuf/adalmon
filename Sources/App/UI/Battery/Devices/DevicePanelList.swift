import SwiftUI

/// Panel Pil bölümündeki "Cihazlar" alt listesi (en düşük pil üstte).
struct DevicePanelList: View {
    let devices: [DeviceBattery]
    var limit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Cihazlar").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if devices.count > limit { Text("+\(devices.count - limit) cihaz daha").font(.caption2).foregroundStyle(.tertiary) }
            }
            ForEach(devices.prefix(limit)) { DevicePanelRow(device: $0) }
        }
    }
}
