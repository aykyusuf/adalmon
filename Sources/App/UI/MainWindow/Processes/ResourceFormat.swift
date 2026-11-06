import Foundation

/// Süreç sayfalarının sayı metinleri (Türkçe). Saf mantık, test edilebilir.
enum ResourceFormat {
    private static let locale = Locale(identifier: "tr_TR")

    private static func number(_ v: Double, fraction: Int) -> String {
        v.formatted(.number.precision(.fractionLength(fraction)).locale(locale))
    }

    /// 45 → "45 sn", 185 → "3 dk 5 sn", 7_800 → "2 sa 10 dk"
    static func duration(seconds: Double) -> String {
        let s = Int(max(0, seconds).rounded())
        if s < 60 { return "\(s) sn" }
        if s < 3_600 { return s % 60 == 0 ? "\(s / 60) dk" : "\(s / 60) dk \(s % 60) sn" }
        let h = s / 3_600, m = (s % 3_600) / 60
        return m == 0 ? "\(h) sa" : "\(h) sa \(m) dk"
    }

    /// Çekirdek başına yüzde (birden çok çekirdekte %100'ü aşabilir). 10'un altında bir ondalık.
    static func percent(_ p: Double) -> String {
        let v = max(0, p)
        if v < 0.05 { return "%0" }
        return "%" + (v < 10 ? number(v, fraction: 1) : number(v.rounded(), fraction: 0))
    }

    static func watts(_ w: Double) -> String {
        let v = max(0, w)
        if v < 0.001 { return "0 W" }
        return v < 1 ? "\(Int((v * 1_000).rounded())) mW" : number(v, fraction: v < 10 ? 1 : 0) + " W"
    }

    /// nJ → Wh ("12,3 Wh", küçükse mWh).
    static func energy(nanojoules: Double) -> String {
        let wh = max(0, nanojoules) / 3.6e12
        return wh < 1 ? number(wh * 1_000, fraction: wh * 1_000 < 10 ? 1 : 0) + " mWh" : number(wh, fraction: wh < 10 ? 1 : 0) + " Wh"
    }

    static func bytes(_ v: Double) -> String { Format.bytes(UInt64(max(0, v))) }

    /// Geçmiş sıralamasının satır metni: (ana değer, ikincil). `coverage` = pencerenin kayıtla dolu süresi (sn), ortalama için.
    static func rankText(metric: ResourceMetric, value: Double, coverage: Double) -> (primary: String, secondary: String?) {
        let cov = max(60, coverage)
        switch metric {
        case .cpu: return (duration(seconds: value / 1e9), "ort. " + percent(value / 1e9 / cov * 100))
        case .gpu: return (duration(seconds: value / 1e9), "ort. " + percent(value / 1e9 / cov * 100))
        case .memoryPeak: return (bytes(value), "tepe")
        case .memoryAvg: return (bytes(value), "ort.")
        case .diskWrite: return (bytes(value), "yazdı")
        case .energy: return (energy(nanojoules: value), "ort. " + watts(value / 1e9 / cov))
        }
    }

    /// Seri grafiği için kova toplamını oranına çevirir (cpu/gpu → %, enerji → W, yazma → B/sn); bellek olduğu gibi.
    static func seriesValue(metric: ResourceMetric, bucketValue: Double, bucketSeconds: Int) -> Double {
        let sec = Double(max(1, bucketSeconds))
        switch metric {
        case .cpu, .gpu: return bucketValue / 1e9 / sec * 100
        case .energy: return bucketValue / 1e9 / sec
        case .diskWrite: return bucketValue / sec
        case .memoryPeak, .memoryAvg: return bucketValue
        }
    }

    static func axisLabel(metric: ResourceMetric, value: Double) -> String {
        switch metric {
        case .cpu, .gpu: percent(value)
        case .energy: watts(value)
        case .diskWrite: Format.rate(value)
        case .memoryPeak, .memoryAvg: bytes(value)
        }
    }

    /// Pencerenin kayıtla dolu süresi: kayıt henüz pencere kadar eskiye gitmiyorsa kısalır.
    static func coverage(window: ResourceWindow, firstRecord: Int?, now: Date = .now) -> Double {
        guard let firstRecord else { return 0 }
        return min(Double(window.seconds), max(60, now.timeIntervalSince1970 - Double(firstRecord) + 60))
    }
}
