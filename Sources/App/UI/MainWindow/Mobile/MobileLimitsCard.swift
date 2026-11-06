import SwiftUI

/// Günlük limit, ani kullanım uyarısı eşiği ve "bu ağı her zaman mobil say" ayarı.
struct MobileLimitsCard: View {
    @Bindable var prefs: Preferences

    var body: some View {
        MobileCard("Günlük limit ve uyarılar", systemImage: "gauge.with.dots.needle.33percent") {
            VStack(alignment: .leading, spacing: 14) {
                sliderRow("Günlük limit", value: $prefs.dailyCapGB, range: 0.5...20, step: 0.5,
                          text: "\(prefs.dailyCapGB.formatted(.number.precision(.fractionLength(1)))) GB")
                sliderRow("Ani kullanım uyarısı", value: $prefs.burstThresholdMB, range: 10...500, step: 10,
                          text: "\(Int(prefs.burstThresholdMB)) MB/dk")
                Toggle("Bu ağı her zaman mobil veri say", isOn: $prefs.forceMobile)
                Text("iPhone hotspot (Wi-Fi ve USB) otomatik algılanır. Algılanmayan bir modem için bunu aç.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            HStack {
                Slider(value: value, in: range, step: step)
                    .accessibilityLabel(title)
                Text(text)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 72, alignment: .trailing)
            }
        }
    }
}
