import SwiftUI

enum BatteryPalette {
    static func tint(_ r: BatteryReading) -> Color {
        if r.isCharging { return .green }
        if r.lowPowerMode && !r.isPluggedIn { return .yellow }
        if r.isPluggedIn { return .green }
        if r.level <= 10 { return .red }
        if r.level <= 20 { return .orange }
        return .green
    }

    static func tempTint(_ c: Double?) -> Color {
        switch BatteryFormat.temperatureStatus(c) {
        case .hot: .red
        case .warm: .orange
        case .cool: .cyan
        default: .green
        }
    }

    static func healthTint(_ p: Int?) -> Color {
        guard let p else { return .secondary }
        return p >= 80 ? .green : (p >= 70 ? .orange : .red)
    }
}

/// Bölümlü kapasite çubuğu (Juicy'deki gibi dilimli).
struct SegmentedCapacityBar: View {
    let level: Int
    let tint: Color
    var charging = false
    var segments = 20
    var height: CGFloat = 10

    var body: some View {
        let filled = Double(level) / 100 * Double(segments)
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { i in
                let amount = max(0, min(1, filled - Double(i)))
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(.primary.opacity(0.10))
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(tint.gradient)
                                .frame(width: geo.size.width * amount)
                                .opacity(charging && amount > 0 && amount < 1 ? 0.75 : 1)
                        }
                    }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Pil seviyesi")
        .accessibilityValue("yüzde \(level)")
    }
}

/// Güç akışı özeti: adaptör → kablo → Mac (→ pil).
struct PowerFlowSummary {
    var adapterTitle: String
    var adapterWatts: String
    var cableTitle: String
    var macTitle: String
    var macWatts: String
    var batteryTitle: String
    var batteryWatts: String
    var isPlugged: Bool

    init(_ r: BatteryReading) {
        isPlugged = r.isPluggedIn
        adapterTitle = r.adapterDisplayName ?? "Şarj aleti"
        adapterWatts = r.adapterLabelWatts.map { "\($0) W" } ?? "—"
        cableTitle = r.cable.title
        macTitle = r.isPluggedIn ? "Mac" : "Mac çekiyor"
        macWatts = BatteryFormat.watts(r.systemPowerW)
        let rate = r.chargeRateW
        if let rate, rate > 0.05 {
            batteryTitle = "Pili şarj ediyor"
        } else if let rate, rate < -0.05 {
            batteryTitle = "Pilden harcıyor"
        } else {
            batteryTitle = "Pil dinlenmede"
        }
        batteryWatts = BatteryFormat.watts(rate)
    }
}

struct PowerFlowNode: View {
    let symbol: String
    let title: String
    let value: String
    var tint: Color = .secondary
    var dim = false

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: .circle)
            Text(value).font(.system(.callout, design: .rounded, weight: .semibold)).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .frame(minWidth: 92)
        .opacity(dim ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }
}

struct PowerFlowConnector: View {
    var tint: Color = .green
    var active = true

    var body: some View {
        ZStack {
            Capsule().fill(.primary.opacity(0.10)).frame(height: 4)
            if active {
                Capsule().fill(LinearGradient(colors: [tint.opacity(0.15), tint, tint.opacity(0.15)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 30)
        .accessibilityHidden(true)
    }
}

/// Kart zemini (sayfa ve panelle ortak).
struct BatteryCardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.06), lineWidth: 0.5))
    }
}

extension View {
    func batteryCard(padding: CGFloat = 16) -> some View { modifier(BatteryCardStyle(padding: padding)) }
}
