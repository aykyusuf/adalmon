import SwiftUI

/// Izgaradaki tek kartın gösterilecek değerleri. `PanelData`'dan her çizimde hesaplanır; yalnız metin ve
/// dizi referansları taşır (diziler kopyalanmaz).
struct PanelCardModel: Identifiable {
    let kind: PanelCardKind
    let value: String
    var unit = ""
    let caption: String
    let tint: Color
    var valueTint: Color?
    var history: [Double] = []
    var scale: PanelSparklineScale = .fixed(0...1)
    /// Geçmişi olmayan kartlar için çubuk (0...1).
    var fraction: Double?
    let spokenValue: String
    var help = ""

    var id: PanelCardKind { kind }
    var title: String { kind.displayName }

    var accessibilityLabel: String {
        [title, spokenValue, caption].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

extension PanelCardModel {
    private static let locale = Locale(identifier: "tr_TR")
    private static let loadFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2)).locale(locale)

    /// Izgara tek çizimde `SystemMetric.all` sonucunu bir kez hesaplayıp tüm kartlara verir.
    static func make(_ kind: PanelCardKind, _ data: PanelData,
                     metrics: [SystemMetric]? = nil) -> PanelCardModel {
        switch kind {
        case .cpu, .gpu, .memory, .disk: system(kind, data, metrics ?? SystemMetric.all(data, showTemperatures: false))
        case .temperature: temperature(data)
        case .download: network(.download, data)
        case .upload: network(.upload, data)
        }
    }

    /// Yük yüzdesine göre değer rengi: normalde birincil, yüksekte turuncu/kırmızı.
    private static func loadTint(_ fraction: Double) -> Color? {
        fraction >= 0.9 ? .red : (fraction >= 0.75 ? .orange : nil)
    }

    private static func system(_ kind: PanelCardKind, _ data: PanelData, _ all: [SystemMetric]) -> PanelCardModel {
        let metricKind: SystemMetric.Kind = switch kind {
        case .cpu: .cpu
        case .gpu: .gpu
        case .memory: .memory
        default: .disk
        }
        guard let m = all.first(where: { $0.kind == metricKind }) else {
            return PanelCardModel(kind: kind, value: "—", caption: "", tint: .secondary, spokenValue: "veri yok")
        }
        let tint: Color = kind == .disk ? .indigo : m.tint
        switch kind {
        case .disk:
            let free = data.snapshot.map { Format.gigabytes($0.disk.availableBytes) } ?? "—"
            return PanelCardModel(kind: kind, value: free.replacingOccurrences(of: " GB", with: ""), unit: free == "—" ? "" : "GB boş",
                                  caption: m.fraction > 0 ? "\(Format.percent(m.fraction)) dolu" : "",
                                  tint: tint, fraction: m.fraction,
                                  spokenValue: "\(free) boş", help: m.detail.isEmpty ? m.help : m.detail)
        case .gpu:
            let caption = data.snapshot?.gpu?.frequencyMHz.map(Format.gigahertz) ?? "meşgul süre"
            return PanelCardModel(kind: kind, value: m.value, caption: data.snapshot?.gpu == nil ? "" : caption, tint: tint,
                                  valueTint: loadTint(m.fraction), history: m.history ?? [],
                                  spokenValue: spokenPercent(m.fraction, available: data.snapshot?.gpu != nil),
                                  help: m.detail.isEmpty ? m.help : m.detail)
        case .memory:
            return PanelCardModel(kind: kind, value: m.value, caption: m.tileSecondary.isEmpty ? "" : "\(m.tileSecondary) boş",
                                  tint: tint, valueTint: loadTint(m.fraction), history: m.history ?? [],
                                  spokenValue: spokenPercent(m.fraction, available: data.snapshot != nil),
                                  help: m.detail.isEmpty ? m.help : m.detail)
        default:
            let load = data.snapshot?.cpu.loadAverage.first.map { $0.formatted(loadFormat) }
            return PanelCardModel(kind: kind, value: m.value, caption: load.map { "yük \($0)" } ?? "", tint: tint,
                                  valueTint: loadTint(m.fraction), history: m.history ?? [],
                                  spokenValue: spokenPercent(m.fraction, available: data.snapshot != nil),
                                  help: m.detail.isEmpty ? m.help : m.detail)
        }
    }

    private static func spokenPercent(_ fraction: Double, available: Bool) -> String {
        available ? "yüzde \(Int((min(1, max(0, fraction)) * 100).rounded()))" : "veri yok"
    }

    private static func temperature(_ data: PanelData) -> PanelCardModel {
        let t = data.snapshot?.temperature
        guard let current = t?.cpu ?? t?.cpuMax else {
            return PanelCardModel(kind: .temperature, value: "—", caption: "sensör yok", tint: .orange, spokenValue: "sensör okunamıyor")
        }
        let tint: Color = current >= 85 ? .red : .orange
        let hottest = t?.cpuMax.map { "en sıcak \(Int($0.rounded()))°" } ?? ""
        return PanelCardModel(kind: .temperature, value: "\(Int(current.rounded()))°", caption: hottest, tint: tint,
                              valueTint: current >= 95 ? .red : (current >= 85 ? .orange : nil),
                              history: data.temperatureHistory, scale: .fitted(minSpan: 12),
                              spokenValue: "\(Int(current.rounded())) derece",
                              help: "İşlemci ortalama sıcaklığı" + (t?.cpuMax.map { ", en sıcak çekirdek \(Int($0.rounded())) °C" } ?? ""))
    }

    private static func network(_ kind: PanelCardKind, _ data: PanelData) -> PanelCardModel {
        let isDown = kind == .download
        let n = data.snapshot?.network
        let rate = isDown ? n?.downloadBytesPerSecond ?? 0 : n?.uploadBytesPerSecond ?? 0
        let (number, unit) = splitRate(Format.rate(rate))
        let total = isDown ? data.downToday : data.upToday
        return PanelCardModel(kind: kind, value: number, unit: unit,
                              caption: total > 0 ? "bugün \(Format.bytes(total))" : "",
                              tint: isDown ? .cyan : .pink,
                              history: isDown ? data.downHistory : data.upHistory,
                              scale: .zeroBased(floor: 50_000),
                              spokenValue: "\(Format.rate(rate).replacingOccurrences(of: "/s", with: " bölü saniye"))",
                              help: isDown ? "Anlık indirme hızı" : "Anlık yükleme hızı")
    }

    /// "12,4 MB/s" → ("12,4", "MB/s")
    static func splitRate(_ text: String) -> (String, String) {
        guard let space = text.lastIndex(of: " ") else { return (text, "") }
        return (String(text[..<space]), String(text[text.index(after: space)...]))
    }
}
