import Foundation

struct PerformanceStat: Identifiable, Equatable {
    var title: String
    var value: String
    var id: String { title }
}

/// Performans sekmesinin sağ alt istatistikleri. Kaynaklar var olan örnekleyicilerdir (yeni örnekleyici yok).
enum PerformanceStatsBuilder {
    static func stats(metric: PerformanceMetric, snapshot s: SystemSnapshot, processCount: Int, facts: AppModelFacts) -> [PerformanceStat] {
        switch metric {
        case .cpu: cpu(s, processCount: processCount)
        case .memory: memory(s)
        case .disk: disk(s)
        case .network: network(s, facts: facts)
        case .gpu: gpu(s)
        }
    }

    /// Ağ sekmesi için `AppModel`'den okunan değerler (kopya; testte AppModel gerekmez).
    struct AppModelFacts: Equatable {
        var downToday: UInt64 = 0
        var upToday: UInt64 = 0
        var downLast60: UInt64 = 0
        var upLast60: UInt64 = 0
    }

    private static func cpu(_ s: SystemSnapshot, processCount: Int) -> [PerformanceStat] {
        let c = s.cpu
        let cores = c.performanceCores + c.efficiencyCores
        var out = [
            PerformanceStat(title: "Kullanım", value: Format.percent(c.total)),
            PerformanceStat(title: "Kullanıcı / Sistem", value: "\(Format.percent(c.user)) / \(Format.percent(c.system))"),
            PerformanceStat(title: "Çekirdekler", value: cores > 0 ? "\(c.performanceCores) P + \(c.efficiencyCores) E" : "\(c.perCore.count)"),
            PerformanceStat(title: "İşlemler", value: processCount > 0 ? "\(processCount)" : "—"),
            PerformanceStat(title: "Çalışma süresi", value: uptime(ProcessInfo.processInfo.systemUptime)),
        ]
        if c.loadAverage.count == 3 {
            out.append(PerformanceStat(title: "Yük ortalaması", value: c.loadAverage.map { $0.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "tr_TR"))) }.joined(separator: " · ")))
        }
        if let t = s.temperature?.cpu { out.append(PerformanceStat(title: "Sıcaklık", value: "\(Int(t.rounded())) °C")) }
        return out
    }

    private static func memory(_ s: SystemSnapshot) -> [PerformanceStat] {
        let m = s.memory
        let pressure: String = switch m.pressure {
        case .normal: "Normal"
        case .warning: "Uyarı"
        case .critical: "Kritik"
        }
        return [
            PerformanceStat(title: "Kullanılan", value: "\(Format.gigabytes(m.usedBytes)) (\(Format.percent(m.usedFraction)))"),
            PerformanceStat(title: "Toplam", value: Format.gigabytes(m.totalBytes)),
            PerformanceStat(title: "Uygulama", value: Format.gigabytes(m.appBytes)),
            PerformanceStat(title: "Sabit (wired)", value: Format.gigabytes(m.wiredBytes)),
            PerformanceStat(title: "Sıkıştırılmış", value: Format.gigabytes(m.compressedBytes)),
            PerformanceStat(title: "Önbellek", value: Format.gigabytes(m.cachedBytes)),
            PerformanceStat(title: "Takas (swap)", value: m.swapTotalBytes > 0 ? "\(Format.gigabytes(m.swapUsedBytes)) / \(Format.gigabytes(m.swapTotalBytes))" : Format.gigabytes(m.swapUsedBytes)),
            PerformanceStat(title: "Bellek basıncı", value: pressure),
        ]
    }

    private static func disk(_ s: SystemSnapshot) -> [PerformanceStat] {
        let d = s.disk
        var out = [
            PerformanceStat(title: "Okuma hızı", value: Format.rate(d.readBytesPerSecond)),
            PerformanceStat(title: "Yazma hızı", value: Format.rate(d.writeBytesPerSecond)),
            PerformanceStat(title: "Boş alan", value: Format.gigabytes(d.freeBytes)),
            PerformanceStat(title: "Kullanılabilir (temizlenebilir dahil)", value: Format.gigabytes(d.availableBytes)),
            PerformanceStat(title: "Kapasite", value: Format.gigabytes(d.totalBytes)),
            PerformanceStat(title: "Doluluk", value: Format.percent(d.usedFraction)),
        ]
        if let t = s.temperature?.ssd { out.append(PerformanceStat(title: "SSD sıcaklığı", value: "\(Int(t.rounded())) °C")) }
        return out
    }

    private static func network(_ s: SystemSnapshot, facts: AppModelFacts) -> [PerformanceStat] {
        [
            PerformanceStat(title: "İndirme", value: "↓ \(Format.rate(s.network.downloadBytesPerSecond))"),
            PerformanceStat(title: "Yükleme", value: "↑ \(Format.rate(s.network.uploadBytesPerSecond))"),
            PerformanceStat(title: "Arayüz", value: s.network.primaryInterface.isEmpty ? "—" : s.network.primaryInterface),
            PerformanceStat(title: "Son 60 sn", value: "↓ \(Format.bytes(facts.downLast60))  ↑ \(Format.bytes(facts.upLast60))"),
            PerformanceStat(title: "Bugün", value: "↓ \(Format.bytes(facts.downToday))  ↑ \(Format.bytes(facts.upToday))"),
        ]
    }

    private static func gpu(_ s: SystemSnapshot) -> [PerformanceStat] {
        guard let g = s.gpu else { return [PerformanceStat(title: "Durum", value: "GPU verisi okunamadı")] }
        var out = [PerformanceStat(title: "Kullanım", value: Format.percent(g.displayLoad)),
                   PerformanceStat(title: "Meşgul süre", value: Format.percent(g.utilization))]
        if let f = g.frequencyMHz, f > 0 { out.append(PerformanceStat(title: "Frekans", value: Format.gigahertz(f))) }
        if let r = g.rendererUtilization { out.append(PerformanceStat(title: "Renderer", value: Format.percent(r))) }
        if let t = g.tilerUtilization { out.append(PerformanceStat(title: "Tiler", value: Format.percent(t))) }
        if let m = g.memoryUsedBytes { out.append(PerformanceStat(title: "GPU belleği", value: Format.gigabytes(m))) }
        if let t = s.temperature?.gpu { out.append(PerformanceStat(title: "Sıcaklık", value: "\(Int(t.rounded())) °C")) }
        return out
    }

    /// 93_700 → "1 g 2 sa 1 dk"
    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let d = total / 86_400, h = total % 86_400 / 3_600, m = total % 3_600 / 60
        if d > 0 { return "\(d) g \(h) sa \(m) dk" }
        if h > 0 { return "\(h) sa \(m) dk" }
        return "\(m) dk"
    }
}
