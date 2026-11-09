import Foundation

/// Pilde kalan süreyi anlık tüketimden hesaplar (Juicy gibi): kalan kapasite ÷ son birkaç dakikanın ortalama deşarj akımı.
/// macOS'un kendi tahmini (`Time to Empty`) fişi çektikten sonra bir süre "hesaplanıyor" der ve yük değişince geç tepki verir;
/// bu hesap ilk okumadan itibaren çalışır ve ağır iş başlayınca hemen kısalır. Yeni okuma/zamanlayıcı gerektirmez: izleyicinin
/// mevcut okumalarını (60 sn, panel açıkken 5 sn) kullanır. Saf mantık, durum yalnızca örnek penceresidir.
struct BatteryRuntimeEstimator: Sendable {
    /// Ortalama penceresi: kısa ani yükler süreyi zıplatmasın, ama iş değişince birkaç dakikada yansısın.
    static let window: TimeInterval = 300
    /// Bundan düşük ortalama akımda (boşta tıkanma) süre anlamsızdır: tahmin yok.
    static let minDrawMA = 40.0
    /// Üst sınır (dakika): daha uzun tahmin göstermeye değmez.
    static let maxMinutes = 48 * 60
    /// Bir örneğin ağırlığı en çok bu kadar saniye sayılır (uzun boşluklu örnekler ortalamayı ezmesin).
    static let maxWeight: TimeInterval = 90

    private struct Sample: Sendable { var at: Date; var ma: Double }
    private var samples: [Sample] = []

    /// Deşarj dışındaki durumda (fişte/şarjda/akım yok) pencere sıfırlanır; deşarjda örnek eklenir.
    mutating func record(_ r: BatteryReading) {
        guard !r.isPluggedIn, !r.isCharging, let a = r.amperageMA, a < 0 else { samples.removeAll(); return }
        if let last = samples.last, r.timestamp <= last.at { samples.removeLast() } // aynı an: sonuncuyu güncelle
        samples.append(Sample(at: r.timestamp, ma: Double(-a)))
        let cutoff = r.timestamp.addingTimeInterval(-Self.window)
        samples.removeAll { $0.at < cutoff }
    }

    /// Pilde kalan dakika; hesaplanamıyorsa (örnek yok, kapasite bilinmiyor, akım çok düşük) nil.
    func minutes(for r: BatteryReading) -> Int? {
        guard !r.isPluggedIn, !r.isCharging, let avg = averageDrawMA(), avg >= Self.minDrawMA else { return nil }
        guard let remaining = Self.remainingMAh(r), remaining > 0 else { return nil }
        let minutes = Int((remaining / avg * 60).rounded())
        return min(max(minutes, 0), Self.maxMinutes)
    }

    /// Penceredeki zaman ağırlıklı ortalama deşarj akımı (mA). Tek örnek varsa onun değeri.
    func averageDrawMA() -> Double? {
        guard let first = samples.first else { return nil }
        guard samples.count > 1 else { return first.ma }
        var sum = 0.0, weight = 0.0
        for (i, s) in samples.enumerated() {
            let dt = i + 1 < samples.count ? samples[i + 1].at.timeIntervalSince(s.at) : 5
            let w = min(max(dt, 0), Self.maxWeight)
            sum += s.ma * w
            weight += w
        }
        return weight > 0 ? sum / weight : first.ma
    }

    /// Kalan kapasite (mAh): gösterilen yüzdeyle tutarlı olsun diye `maksimum kapasite × seviye`; yoksa ham mevcut kapasite.
    static func remainingMAh(_ r: BatteryReading) -> Double? {
        if let max = r.rawMaxMAh, max > 0, r.level > 0 { return Double(max) * Double(r.level) / 100 }
        if let current = r.rawCurrentMAh, current > 0 { return Double(current) }
        return nil
    }

    var sampleCount: Int { samples.count }
}
