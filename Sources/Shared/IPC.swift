import Foundation

/// Filtre ve uygulama arasında paylaşılan sabitler.
enum IPC {
    static let teamID = "BC62U5TGCQ"
    static let appBundleID = "com.yusufayik.adalmon"
    static let filterBundleID = "com.yusufayik.adalmon.filter"
    static let machServiceName = "BC62U5TGCQ.com.yusufayik.adalmon.filter"
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
}

extension FilterConfig {
    private enum CodingKeys: String, CodingKey { case proxyPorts, proxyOwnerPaths, blockedOnMobile, forceMobile, limits }

    /// Eksik alanlar varsayılana düşer (eski sürümün JSON'u da çözülür).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        proxyPorts = try c.decodeIfPresent([Int].self, forKey: .proxyPorts) ?? []
        proxyOwnerPaths = try c.decodeIfPresent([String].self, forKey: .proxyOwnerPaths) ?? []
        blockedOnMobile = try c.decodeIfPresent([String].self, forKey: .blockedOnMobile) ?? []
        forceMobile = try c.decodeIfPresent(Bool.self, forKey: .forceMobile) ?? false
        limits = try c.decodeIfPresent([String: AppLimit].self, forKey: .limits) ?? [:]
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
