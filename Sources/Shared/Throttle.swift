import Foundation

/// Bir uygulamanın hız sınırı. `nil` yön sınırsızdır.
struct AppLimit: Codable, Sendable, Equatable, Hashable {
    /// İndirme sınırı (byte/sn).
    var downBytesPerSec: Int?
    /// Yükleme sınırı (byte/sn).
    var upBytesPerSec: Int?
    /// Yalnızca mobil veride (pahalı / kısıtlı yol) uygula.
    var onlyOnMobile: Bool = false

    init(downBytesPerSec: Int? = nil, upBytesPerSec: Int? = nil, onlyOnMobile: Bool = false) {
        self.downBytesPerSec = downBytesPerSec
        self.upBytesPerSec = upBytesPerSec
        self.onlyOnMobile = onlyOnMobile
    }

    /// En az bir yönde pozitif sınır var mı.
    var hasCap: Bool { (downBytesPerSec ?? 0) > 0 || (upBytesPerSec ?? 0) > 0 }

    func rate(_ direction: ThrottleDirection) -> Int? {
        let r = direction == .down ? downBytesPerSec : upBytesPerSec
        guard let r, r > 0 else { return nil }
        return r
    }
}

enum ThrottleDirection: Sendable { case down, up }

/// Sanal-zaman (GCRA) tabanlı token kovası. Parça boyutu kova kapasitesinden büyük olsa da doğru çalışır:
/// her ayırma "sıradaki boş an"ı `bytes / rate` kadar ileri iter, çağırana ne kadar beklemesi gerektiğini döndürür.
/// Saat dışarıdan verilir (test edilebilir). İş parçacığı güvenliği çağıranın sorumluluğundadır.
struct TokenBucket: Sendable {
    private(set) var rate: Double
    /// Boşta biriken en fazla izin (sn cinsinden: rate * burstSeconds byte).
    let burstSeconds: Double
    /// Bir sonraki byte'ın gönderilebileceği an (saniye, monoton saat).
    private var nextFree: Double

    init(bytesPerSecond: Int, burstSeconds: Double = 0.25, now: Double) {
        self.rate = Double(max(1, bytesPerSecond))
        self.burstSeconds = burstSeconds
        self.nextFree = now
    }

    mutating func setRate(_ bytesPerSecond: Int) {
        let r = Double(max(1, bytesPerSecond))
        guard r != rate else { return }
        rate = r
    }

    /// `bytes` gönderilmeden önce beklenmesi gereken süre (sn). Ayırmayı kaydeder.
    mutating func reserve(_ bytes: Int, now: Double) -> Double {
        // Boşta kalınan süre en fazla `burstSeconds` kadar kredi biriktirir.
        let start = max(nextFree, now - burstSeconds)
        nextFree = start + Double(max(0, bytes)) / rate
        return max(0, start - now)
    }
}

/// Saydam proxy ve filtre için saf karar fonksiyonları (test edilir).
enum ThrottlePolicy {
    /// Şu anki ağ durumuna göre uygulamanın etkin sınırı.
    static func activeLimit(app: String, config: FilterConfig, expensive: Bool) -> AppLimit? {
        guard let l = config.limits[app], l.hasCap else { return nil }
        if l.onlyOnMobile, !expensive { return nil }
        return l
    }

    /// Saydam proxy bu TCP akışını üstlenmeli mi? `false` = sistem akışı doğrudan taşır (sıfır ek yük).
    static func shouldHandle(app: String, executablePath: String, signingID: String,
                             isLoopback: Bool, remotePort: Int, isTCP: Bool,
                             expensive: Bool, config: FilterConfig) -> Bool {
        guard isTCP else { return false }
        // Kendi akışlarımız (döngü olmasın) ve proxy sürecinin (SpoofDPI) kendisi asla.
        if signingID == IPC.filterBundleID || signingID == IPC.appBundleID { return false }
        if !executablePath.isEmpty, config.proxyOwnerPaths.contains(executablePath) { return false }
        // Loopback: yalnızca yerel proxy portuna giden akışlar (uygulama → SpoofDPI). Diğer yerel IPC'ye dokunma.
        if isLoopback, !config.proxyPorts.contains(remotePort) { return false }
        // Mobilde engellenen uygulama: filtre asıl akışı düşürsün, aktarıp engeli atlatmayalım.
        if expensive, config.blockedOnMobile.contains(app) { return false }
        return activeLimit(app: app, config: config, expensive: expensive) != nil
    }

    /// Sınırlı uygulamanın QUIC (UDP/443) akışını düşür ki tarayıcı TCP'ye (sınırlanabilir) geri dönsün.
    static func shouldDropQUIC(app: String, isUDP: Bool, remotePort: Int, isLoopback: Bool,
                               expensive: Bool, config: FilterConfig) -> Bool {
        guard isUDP, remotePort == 443, !isLoopback else { return false }
        return activeLimit(app: app, config: config, expensive: expensive) != nil
    }
}
