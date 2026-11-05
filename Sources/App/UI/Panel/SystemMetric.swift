import SwiftUI

/// Sistem bölümündeki bir metriğin görüntülenecek değerleri. Karo, kart ve satır görünümleri aynı modeli paylaşır.
struct SystemMetric: Identifiable {
    enum Kind: String { case cpu, gpu, memory, disk }

    let kind: Kind
    let title: String
    let systemImage: String
    /// Büyük değer: "%23", "312 GB".
    let value: String
    /// Kısa ek bilgi: "54 °C", "6,1 GB boş".
    let secondary: String
    /// Karoya sığan kısa ek bilgi (dar alan); boşsa `secondary` kullanılır.
    var tileSecondary: String = ""
    /// Kartlardaki tek satırlık özet.
    let summary: String
    /// Dokununca açılan ayrıntı satırı.
    let detail: String
    let tint: Color
    let history: [Double]?
    /// 0...1 doluluk (satır görünümündeki çubuk, disk karosu).
    let fraction: Double
    let help: String

    var id: Kind { kind }

    var accessibilityLabel: String {
        [title, value, secondary].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func all(_ data: PanelData, showTemperatures: Bool) -> [SystemMetric] {
        let s = data.snapshot
        let temps = showTemperatures ? s?.temperature : nil
        return [cpu(s, temps, data.cpuHistory), gpu(s, temps, data.gpuHistory), memory(s, data.memHistory), disk(s)]
    }

    private static func degrees(_ t: Double?) -> String? { t.map { "\(Int($0.rounded())) °C" } }

    private static func cpu(_ s: SystemSnapshot?, _ temps: TemperatureStats?, _ history: [Double]) -> SystemMetric {
        let c = s?.cpu
        let load = c?.loadAverage.first.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "–"
        var detail: [String] = []
        if let c {
            detail.append("\(c.performanceCores)P+\(c.efficiencyCores)E")
            detail.append("yük \(load)")
            detail.append("kullanıcı \(Format.percent(c.user)) · sistem \(Format.percent(c.system))")
        }
        if let max = degrees(temps?.cpuMax) { detail.append("en sıcak \(max)") }
        return SystemMetric(kind: .cpu, title: "CPU", systemImage: "cpu",
                            value: Format.percent(c?.total ?? 0),
                            secondary: degrees(temps?.cpu) ?? "yük \(load)",
                            summary: c.map { "\($0.performanceCores)P+\($0.efficiencyCores)E · yük \(load)" } ?? "",
                            detail: detail.joined(separator: " · "),
                            tint: .blue, history: history, fraction: c?.total ?? 0,
                            help: "İşlemci kullanımı")
    }

    private static func gpu(_ s: SystemSnapshot?, _ temps: TemperatureStats?, _ history: [Double]) -> SystemMetric {
        let g = s?.gpu
        var detail: [String] = []
        if let g {
            detail.append(gpuBusyAndFrequency(g))
            if let r = g.rendererUtilization { detail.append("çizim \(Format.percent(r))") }
            if let m = g.memoryUsedBytes { detail.append("bellek \(Format.bytes(m))") }
        }
        let help = g?.load == nil
            ? "GPU meşgul süre oranı (Device Utilization). Yük yoğunluğunu değil, GPU'nun boş olmadığı zamanı gösterir."
            : "GPU gerçek yükü: aktif sürenin o anki frekansla ağırlıklandırılmış hali, en yüksek frekansa göre "
                + "(IOReport GPU P-state dağılımı). Meşgul: GPU'nun boş olmadığı süre oranı (Device Utilization); "
                + "düşük frekansta meşgul olmak daha az yük demektir."
        return SystemMetric(kind: .gpu, title: "GPU", systemImage: "square.stack.3d.up",
                            value: g.map { Format.percent($0.displayLoad) } ?? "—",
                            secondary: degrees(temps?.gpu) ?? "",
                            summary: g?.load != nil ? g.map(gpuBusyAndFrequency) ?? ""
                                : "meşgul süre" + (g?.memoryUsedBytes.map { " · \(Format.bytes($0))" } ?? ""),
                            detail: detail.joined(separator: " · "),
                            tint: .purple, history: history, fraction: g?.displayLoad ?? 0,
                            help: help)
    }

    /// "meşgul %31 · 1,1 GHz"; frekans yoksa yalnız meşgul süre.
    static func gpuBusyAndFrequency(_ g: GPUStats) -> String {
        guard g.load != nil else { return "meşgul süre (Device Utilization)" }
        var parts = ["meşgul \(Format.percent(g.utilization))"]
        if let f = g.frequencyMHz { parts.append(Format.gigahertz(f)) }
        return parts.joined(separator: " · ")
    }

    private static func memory(_ s: SystemSnapshot?, _ history: [Double]) -> SystemMetric {
        let m = s?.memory
        let free = m.map { $0.totalBytes > $0.usedBytes ? $0.totalBytes - $0.usedBytes : 0 } ?? 0
        let pressure = switch m?.pressure {
        case .critical: "kritik"
        case .warning: "uyarı"
        default: "normal"
        }
        let tint: Color = switch m?.pressure {
        case .critical: .red
        case .warning: .yellow
        default: .teal
        }
        var detail: [String] = []
        if let m {
            detail.append("\(Format.gigabytes(m.usedBytes)) / \(Format.gigabytes(m.totalBytes))")
            detail.append("baskı \(pressure)")
            if m.swapUsedBytes > 0 { detail.append("swap \(Format.gigabytes(m.swapUsedBytes))") }
        }
        return SystemMetric(kind: .memory, title: "RAM", systemImage: "memorychip",
                            value: Format.percent(m?.usedFraction ?? 0),
                            secondary: m == nil ? "" : "\(Format.gigabytes(free)) boş",
                            tileSecondary: m == nil ? "" : Format.gigabytes(free),
                            summary: m.map { "\(Format.gigabytes($0.usedBytes)) / \(Format.gigabytes($0.totalBytes)) · \(pressure)" } ?? "",
                            detail: detail.joined(separator: " · "),
                            tint: tint, history: history, fraction: m?.usedFraction ?? 0,
                            help: "Bellek kullanımı ve boş alan")
    }

    private static func disk(_ s: SystemSnapshot?) -> SystemMetric {
        let d = s?.disk
        let detail = d.map {
            "Okuma \(Format.rate($0.readBytesPerSecond)) · Yazma \(Format.rate($0.writeBytesPerSecond)) · \(Format.percent($0.usedFraction)) dolu"
        } ?? ""
        return SystemMetric(kind: .disk, title: "Disk", systemImage: "internaldrive",
                            value: d.map { Format.gigabytes($0.availableBytes) } ?? "—",
                            secondary: "boş",
                            summary: d.map { "O \(Format.rate($0.readBytesPerSecond)) · Y \(Format.rate($0.writeBytesPerSecond))" } ?? "",
                            detail: detail,
                            tint: .orange, history: nil, fraction: d?.usedFraction ?? 0,
                            help: "Ana diskte kullanılabilir alan")
    }
}
