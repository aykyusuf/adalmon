import Foundation

/// Filtre ve uygulama arasında paylaşılan sabitler.
enum IPC {
    static let teamID = "YOUR_TEAM_ID"
    static let appBundleID = "com.example.adalmon"
    static let filterBundleID = "com.example.adalmon.filter"
    static let machServiceName = "YOUR_TEAM_ID.com.example.adalmon.filter"
    /// Filtreye yalnızca bizim imzalı uygulamamız bağlanabilir.
    static let appCodeRequirement =
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"\(appBundleID)\""
}

/// Uygulama → filtre XPC arayüzü. Veriler JSON `Data` olarak taşınır (NSSecureCoding derdi olmasın diye).
@objc(AdalmonFilterControl)
protocol FilterControl {
    /// `FilterConfig` JSON'u.
    func updateConfig(_ json: Data, reply: @escaping (Bool) -> Void)
    /// Biriken `[UsageBucket]` JSON'unu döndürür ve filtredeki tamponu temizler.
    func drainUsage(reply: @escaping (Data) -> Void)
    func ping(reply: @escaping (String) -> Void)
}

/// Uygulamanın filtreye gönderdiği çalışma ayarları.
struct FilterConfig: Codable, Sendable, Equatable {
    /// Sistem proxy'si 127.0.0.1/::1 üzerindeyse portları (HTTP/HTTPS/SOCKS).
    var proxyPorts: [Int] = []
    /// Proxy portunu dinleyen sürecin çalıştırılabilir yolu (örn. ~/Desktop/spoofdpi). Bu sürecin dış trafiği uygulamalara yazılmaz.
    var proxyOwnerPaths: [String] = []
    /// Mobil verideyken engellenecek uygulama anahtarları (`AppKey`).
    var blockedOnMobile: [String] = []
    /// Kullanıcı bu ağı elle "mobil veri" olarak işaretlediyse.
    var forceMobile: Bool = false
    /// Uygulama anahtarı (`AppKey`) → hız sınırı. Saydam proxy ve QUIC düşürme bunu kullanır.
    var limits: [String: AppLimit] = [:]
    /// Her ağda (Wi-Fi dahil) engellenecek uygulama anahtarları. "Tüm ağlar" ENGEL kuralları ve kademeli limit kesmesi.
    /// (Faz B; eski filtre bilinmeyen alanı yok sayar, eski uygulama göndermezse boş kalır.)
    var blockedAlways: Set<String> = []
    /// Veri Tasarrufu modu açık mı. Yalnızca mobil/pahalı yolda uygulanır; bkz. `FlowPolicy.shouldDropForDataSaver`.
    var dataSaverActive: Bool = false
    /// Veri Tasarrufu'nda her zaman izinli uygulama anahtarları.
    var dataSaverAllow: Set<String> = []
}

extension FilterConfig {
    private enum CodingKeys: String, CodingKey { case proxyPorts, proxyOwnerPaths, blockedOnMobile, forceMobile, limits
        case blockedAlways, dataSaverActive, dataSaverAllow
    }

    /// Eksik alanlar varsayılana düşer (eski sürümün JSON'u da çözülür).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        proxyPorts = try c.decodeIfPresent([Int].self, forKey: .proxyPorts) ?? []
        proxyOwnerPaths = try c.decodeIfPresent([String].self, forKey: .proxyOwnerPaths) ?? []
        blockedOnMobile = try c.decodeIfPresent([String].self, forKey: .blockedOnMobile) ?? []
        forceMobile = try c.decodeIfPresent(Bool.self, forKey: .forceMobile) ?? false
        limits = try c.decodeIfPresent([String: AppLimit].self, forKey: .limits) ?? [:]
        blockedAlways = try c.decodeIfPresent(Set<String>.self, forKey: .blockedAlways) ?? []
        dataSaverActive = try c.decodeIfPresent(Bool.self, forKey: .dataSaverActive) ?? false
        dataSaverAllow = try c.decodeIfPresent(Set<String>.self, forKey: .dataSaverAllow) ?? []
    }
}

enum FlowKind: Int, Codable, Sendable {
    /// Uygulama doğrudan internete çıktı.
    case direct = 0
    /// Uygulama yerel proxy'ye (SpoofDPI vb.) gitti; bu trafik o uygulamanın internet kullanımıdır.
    case proxied = 1
    /// Proxy sürecinin kendi dış trafiği — yalnızca kontrol için, uygulamalara eklenmez.
    case proxyEgress = 2
}

/// Dakikalık, uygulama + host bazlı toplanmış kullanım.
struct UsageBucket: Codable, Sendable, Hashable {
    /// Uygulama kimliği: en dıştaki .app yolu ya da çalıştırılabilir yol.
    var app: String
    /// Kod imza kimliği (varsa), örn. com.google.Chrome.helper
    var signingID: String
    /// Hedef host (CONNECT hedefi, remoteHostname ya da IP).
    var host: String
    var kind: FlowKind
    /// Trafik anında yol pahalı mıydı (mobil veri / hotspot).
    var expensive: Bool
    /// Unix dakikası (epoch / 60).
    var minute: Int
    var bytesIn: UInt64
    var bytesOut: UInt64

    struct Key: Hashable, Sendable {
        var app: String, signingID: String, host: String, kind: FlowKind, expensive: Bool, minute: Int
    }
    var key: Key { Key(app: app, signingID: signingID, host: host, kind: kind, expensive: expensive, minute: minute) }
}
