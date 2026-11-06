/// Alan adı grubunun listedeki sırasını belirler: adlandırılmış alan adları, proxy, ham IP, yerel ağ.
enum DomainCategory: Int, Comparable, Sendable {
    /// Adlı alan adı ya da servis (YouTube, github.com …).
    case named
    /// Yerel proxy (SpoofDPI) üzerinden giden, hedefi bilinmeyen trafik.
    case viaProxy
    /// Ham (genel) IP adresi ya da bilinmeyen hedef.
    case address
    /// Yerel ağ (özel, link-local, mDNS …): hep en sonda.
    case local

    static func < (a: DomainCategory, b: DomainCategory) -> Bool { a.rawValue < b.rawValue }
}
