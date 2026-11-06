import Foundation

/// Ham host'u okunur bir gruba indirger:
/// - bilinen servisler marka adıyla (googlevideo → YouTube, amazonaws → Amazon AWS, akamaiedge → Akamai (CDN) …),
/// - diğer alan adları kayıtlı alan adına (cdn.example.com.tr → example.com.tr),
/// - yerel/loopback adresler tek bir kovaya ("Yerel ağ" / "SpoofDPI üzerinden"),
/// - genel ham IP'ler olduğu gibi.
///
/// `group` idempotenttir: çıktısı tekrar verilirse aynı değeri döndürür (saatlik tabloda gruplanmış adlar saklanır).
enum DomainGrouper {
    /// Özel/link-local/ULA/mDNS adresler ve `*.local` adları.
    static let localName = "Yerel ağ"
    /// Loopback adresi: filtre loopback akışlarını yalnızca yerel proxy'ye (SpoofDPI) giderse sayar, yani bu bayt gerçek
    /// internet trafiğidir; hedef (CONNECT okunmadığı için) bilinmez.
    static let viaProxyName = "SpoofDPI üzerinden"
    static let unknownName = "Bilinmeyen"

    private static let localSuffixes = [".local", ".lan", ".home.arpa", ".localdomain"]
    private static let twoLevelTLDs: Set<String> = [
        "com.tr", "net.tr", "org.tr", "gov.tr", "edu.tr", "k12.tr", "av.tr", "co.uk", "org.uk", "ac.uk", "gov.uk", "com.au", "net.au",
        "co.jp", "co.kr", "co.in", "co.nz", "co.za", "com.br", "com.mx", "com.ar", "com.cn", "com.hk", "com.sg", "com.tw", "com.sa",
        "com.ua",
    ]

    static func group(_ host: String) -> String {
        var h = host.trimmingCharacters(in: .whitespaces).lowercased()
        if h.hasSuffix(".") { h.removeLast() }
        if h.isEmpty || h == "?" || h == "unknown" { return unknownName }
        if let canonical = canonicalSpecialName(h) { return canonical }

        if let ip = IPAddressClass.parse(h) {
            switch ip.kind {
            case .loopback: return viaProxyName
            case .publicAddress: return ip.text
            default: return localName
            }
        }
        if h == "localhost" || h.hasSuffix(".localhost") { return viaProxyName }
        if localSuffixes.contains(where: { h.hasSuffix($0) }) { return localName }
        if let service = DomainServiceTable.service(for: h) { return service }
        return registrable(h)
    }

    /// Kayıtlı alan adı: `a.b.example.com.tr` → `example.com.tr`.
    static func registrable(_ h: String) -> String {
        let parts = h.split(separator: ".")
        guard parts.count > 2 else { return h }
        let lastTwo = parts.suffix(2).joined(separator: ".")
        if twoLevelTLDs.contains(lastTwo) { return parts.suffix(3).joined(separator: ".") }
        return lastTwo
    }

    /// Grup adının listedeki sırası (adlı alan adları → proxy → ham IP → yerel ağ).
    static func category(ofGroup name: String) -> DomainCategory {
        switch name {
        case localName: .local
        case viaProxyName: .viaProxy
        case unknownName: .address
        default: IPAddressClass.parse(name) != nil ? .address : .named
        }
    }

    /// En çok bayt harcayan `limit` grubu seçer, sonra gösterim sırasına dizer: adlı alan adları (bayta göre), proxy,
    /// ham IP'ler, en sonda "Yerel ağ".
    static func displayOrder<T>(_ items: [T], limit: Int, name: (T) -> String, bytes: (T) -> UInt64) -> [T] {
        let top = items.sorted { a, b in
            bytes(a) != bytes(b) ? bytes(a) > bytes(b) : name(a) < name(b)
        }.prefix(max(0, limit))
        return top.sorted { a, b in
            let (ca, cb) = (category(ofGroup: name(a)), category(ofGroup: name(b)))
            if ca != cb { return ca < cb }
            return bytes(a) != bytes(b) ? bytes(a) > bytes(b) : name(a) < name(b)
        }
    }

    private static func canonicalSpecialName(_ lower: String) -> String? {
        switch lower {
        case localName.lowercased(): localName
        case viaProxyName.lowercased(): viaProxyName
        case unknownName.lowercased(): unknownName
        default: DomainServiceTable.canonicalNames[lower]
        }
    }
}
