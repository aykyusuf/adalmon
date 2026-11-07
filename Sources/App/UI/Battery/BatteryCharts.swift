import Charts
import SwiftUI

enum BatteryLevelRange: Int, CaseIterable, Identifiable {
    case h6 = 21_600, h12 = 43_200, h24 = 86_400, d7 = 604_800, d14 = 1_209_600

    var id: Int { rawValue }
    var seconds: Int { rawValue }

    var title: String {
        switch self {
        case .h6: "6 sa"
        case .h12: "12 sa"
        case .h24: "24 sa"
        case .d7: "7 gün"
        case .d14: "14 gün"
        }
    }

    var bucketSeconds: Int {
        switch self {
        case .h6, .h12: 60
        case .h24: 120
        case .d7: 900
        case .d14: 1_800
        }
    }

    var isLong: Bool { self == .d7 || self == .d14 }
}

enum BatteryDayRange: Int, CaseIterable, Identifiable {
    case d7 = 7, d30 = 30, d90 = 90
    var id: Int { rawValue }
    var title: String { "\(rawValue) gün" }
}

struct BatteryBarItem: Identifiable, Equatable {
    var date: Date
    var value: Double
    var id: Date { date }
}

private enum ChartText {
    static let locale = Locale(identifier: "tr_TR")
    static func time(_ d: Date, long: Bool) -> String {
        long ? d.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
             : d.formatted(.dateTime.hour().minute().locale(locale))
    }
}

struct BatteryEmptyChart: View {
    var text = "Geçmiş birikiyor; pil dakikada bir kaydedilir."
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
    }
}

/// Pil seviyesi: şarj aralıkları yeşil, pil kullanımı mavi; uyku/kapalı boşluklarda çizgi kopar.
struct BatteryLevelChart: View {
    let samples: [BatterySample]
    let range: BatteryLevelRange
    var now = Date.now
    @State private var hover: Date?

    private struct Segment: Identifiable {
        var id: Int
        var charging: Bool
        var points: [BatterySample]
    }

    private var segments: [Segment] {
        var out: [Segment] = []
        let gap = max(range.bucketSeconds * 4, 300)
        for s in samples {
            if var last = out.last, let prev = last.points.last, s.ts - prev.ts <= gap {
                if last.charging == s.charging {
                    last.points.append(s)
                    out[out.count - 1] = last
                } else {
                    out.append(Segment(id: out.count, charging: s.charging, points: [prev, s]))
                }
            } else {
                out.append(Segment(id: out.count, charging: s.charging, points: [s]))
            }
        }
        return out
    }

    var body: some View {
        let from = now.addingTimeInterval(-Double(range.seconds))
        let selected = hover.flatMap { nearest(to: $0) }
        Chart {
            ForEach(segments.filter { $0.points.count >= 2 }) { seg in
                ForEach(seg.points) { p in
                    let d = Date(timeIntervalSince1970: TimeInterval(p.ts))
                    AreaMark(x: .value("Zaman", d), y: .value("Pil", p.pct), series: .value("Dilim", seg.id), stacking: .unstacked)
                        .foregroundStyle(.linearGradient(colors: [(seg.charging ? Color.green : .blue).opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.linear)
                    LineMark(x: .value("Zaman", d), y: .value("Pil", p.pct), series: .value("Dilim", seg.id))
                        .foregroundStyle(seg.charging ? Color.green : Color.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)
                }
            }
            RuleMark(y: .value("Düşük", 20)).foregroundStyle(.orange.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
            if let s = selected {
                let d = Date(timeIntervalSince1970: TimeInterval(s.ts))
                RuleMark(x: .value("Seçili", d))
                    .foregroundStyle(.secondary.opacity(0.55))
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTooltip(title: ChartText.time(d, long: range.isLong), rows: rows(s))
                    }
                PointMark(x: .value("Seçili", d), y: .value("Pil", s.pct)).foregroundStyle(s.charging ? Color.green : Color.blue).symbolSize(60)
            }
        }
        .chartXScale(domain: from...now)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { v in
                AxisGridLine()
                AxisValueLabel { if let n = v.as(Int.self) { Text("%\(n)") } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: range.isLong ? 7 : 6)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                AxisValueLabel(format: range.isLong ? .dateTime.day().month(.abbreviated) : .dateTime.hour().minute(), centered: false)
            }
        }
        .chartPointer(as: Date.self) { hover = $0 }
        .accessibilityLabel("Pil seviyesi grafiği")
        .accessibilityValue(samples.last.map { "son değer yüzde \($0.pct)" } ?? "veri yok")
    }

    private func nearest(to date: Date) -> BatterySample? {
        let t = Int(date.timeIntervalSince1970)
        guard let best = samples.min(by: { abs($0.ts - t) < abs($1.ts - t) }), abs(best.ts - t) <= range.bucketSeconds * 6 else { return nil }
        return best
    }

    private func rows(_ s: BatterySample) -> [ChartTooltipRow] {
        var r = [ChartTooltipRow(name: "Pil", color: s.charging ? .green : .blue, text: "%\(s.pct)")]
        r.append(ChartTooltipRow(name: "Durum", color: .gray, text: s.charging ? "Şarj oluyor" : (s.plugged ? "Fişte" : "Pilde")))
        if let t = s.tempC { r.append(ChartTooltipRow(name: "Sıcaklık", color: .orange, text: BatteryFormat.temp(t))) }
        return r
    }
}

/// Günlük çubuklar + fareyle değer kutusu.
struct BatteryBarChart: View {
    let items: [BatteryBarItem]
    let tint: Color
    let format: (Double) -> String
    var axisFormat: (Double) -> String = { "\(Int($0))" }
    var title = "Değer"
    @State private var hover: Date?

    var body: some View {
        let selected = hover.flatMap { h in items.first { Calendar.current.isDate($0.date, inSameDayAs: h) } }
        Chart {
            ForEach(items) { item in
                BarMark(x: .value("Gün", item.date, unit: .day), y: .value(title, item.value))
                    .foregroundStyle((selected?.id == item.id ? tint : tint.opacity(0.75)).gradient)
                    .cornerRadius(items.count > 40 ? 1 : 3)
            }
            if let selected {
                ChartBarSelectionMarks(x: selected.date, title: selected.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "tr_TR"))),
                                       rows: [ChartTooltipRow(name: title, color: tint, text: format(selected.value))])
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine()
                AxisValueLabel { if let d = v.as(Double.self) { Text(axisFormat(d)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: items.count > 14 ? 6 : 7)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
            }
        }
        .chartPointer(as: Date.self) { hover = $0 }
        .accessibilityLabel(title)
    }
}

/// Tek seri çizgi grafiği (kapasite, döngü, sıcaklık) — InteractiveLineChart üzerinden (hover'lı).
struct BatteryTrendLine: View {
    let points: [ChartPoint]
    let color: Color
    let name: String
    let format: (Double) -> String
    var axisFormat: ((Double) -> String)?
    var timeLabel: (Date) -> String = { $0.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "tr_TR"))) }
    var xLabel: (Date) -> String = { $0.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "tr_TR"))) }
    var minSpan = 2.0

    var body: some View {
        if points.count < 2 {
            BatteryEmptyChart(text: points.isEmpty ? "Henüz veri yok" : "Çizgi için en az iki kayıt gerekir; günler geçtikçe dolacak.")
        } else {
            let values = points.map(\.value)
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            let pad = max((hi - lo) * 0.15, minSpan / 2)
            InteractiveLineChart(
                lines: [ChartLine(name: name, color: color, points: points)],
                xDomain: points[0].date...points[points.count - 1].date,
                yDomain: (lo - pad)...(hi + pad),
                yLabel: format,
                timeLabel: timeLabel,
                yAxisLabel: axisFormat,
                xAxisValues: .automatic(desiredCount: 4),
                xLabel: xLabel,
                lineWidth: 2)
        }
    }
}
