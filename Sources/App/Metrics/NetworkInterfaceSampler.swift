import Darwin
import Foundation
import SystemConfiguration

/// sysctl NET_RT_IFLIST2 ile fiziksel arayüz sayaçlarını ve birincil arayüz hızını okur.
final class NetworkInterfaceSampler {
    private static let excludedPrefixes = [
        "lo", "utun", "ipsec", "ppp", "gif", "stf", "awdl", "llw", "bridge", "anpi", "ap", "tun", "tap", "wg", "pktap", "nan"
    ]

    private let store = SCDynamicStoreCreate(nil, "Adalmon" as CFString, nil, nil)
    private var namesByIndex: [UInt16: String] = [:]
    private var buffer: [UInt8] = []
    private var previousIn: [String: UInt64] = [:]
    private var previousOut: [String: UInt64] = [:]

    func sample(elapsed: Double) -> InterfaceStats {
        let (cumulativeIn, cumulativeOut) = readCounters()
        let primary = choosePrimary(in: cumulativeIn, out: cumulativeOut)

        var download = 0.0
        var upload = 0.0
        if elapsed > 0, let beforeIn = previousIn[primary], let beforeOut = previousOut[primary] {
            let nowIn = cumulativeIn[primary] ?? 0
            let nowOut = cumulativeOut[primary] ?? 0
            // Sayaç geriye giderse (arayüz yeniden kuruldu) 0'a sabitle.
            download = nowIn >= beforeIn ? Double(nowIn - beforeIn) / elapsed : 0
            upload = nowOut >= beforeOut ? Double(nowOut - beforeOut) / elapsed : 0
        }
        previousIn = cumulativeIn
        previousOut = cumulativeOut

        return InterfaceStats(
            primaryInterface: primary,
            downloadBytesPerSecond: download,
            uploadBytesPerSecond: upload,
            cumulativeIn: cumulativeIn,
            cumulativeOut: cumulativeOut
        )
    }

    private func isPhysical(_ name: String) -> Bool {
        !Self.excludedPrefixes.contains { name.hasPrefix($0) }
    }

    /// SystemConfiguration birincil arayüzü fiziksel ise onu seçer. VPN (utun) vb. ise ya da bulunamazsa
    /// son örneğe göre en yoğun, o da yoksa kümülatif olarak en çok trafik görmüş fiziksel arayüzü seçer.
    private func choosePrimary(in cumulativeIn: [String: UInt64], out cumulativeOut: [String: UInt64]) -> String {
        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            if let name = primaryInterface(key: key), isPhysical(name), cumulativeIn[name] != nil {
                return name
            }
        }

        func total(_ name: String) -> UInt64 { (cumulativeIn[name] ?? 0) &+ (cumulativeOut[name] ?? 0) }
        func recent(_ name: String) -> UInt64 {
            let nowTotal = total(name)
            let before = (previousIn[name] ?? 0) &+ (previousOut[name] ?? 0)
            return nowTotal >= before && previousIn[name] != nil ? nowTotal - before : 0
        }
        let candidates = cumulativeIn.keys.sorted()
        let best = candidates.max { lhs, rhs in
            let l = (recent(lhs), lhs.hasPrefix("en") ? 1 : 0, total(lhs))
            let r = (recent(rhs), rhs.hasPrefix("en") ? 1 : 0, total(rhs))
            return l < r
        }
        return best ?? "en0"
    }

    private func primaryInterface(key: String) -> String? {
        guard let store,
              let value = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] else { return nil }
        return value["PrimaryInterface"] as? String
    }

    private func readCounters() -> ([String: UInt64], [String: UInt64]) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return ([:], [:]) }
        if buffer.count < length { buffer = [UInt8](repeating: 0, count: length * 2) }
        length = buffer.count
        let ok = buffer.withUnsafeMutableBytes { sysctl(&mib, UInt32(mib.count), $0.baseAddress, &length, nil, 0) == 0 }
        guard ok else { return ([:], [:]) }

        var received: [String: UInt64] = [:]
        var sent: [String: UInt64] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if let name = interfaceName(index: info.ifm_index), isPhysical(name) {
                        received[name] = info.ifm_data.ifi_ibytes
                        sent[name] = info.ifm_data.ifi_obytes
                    }
                }
                offset += messageLength
            }
        }
        return (received, sent)
    }

    private func interfaceName(index: UInt16) -> String? {
        if let cached = namesByIndex[index] { return cached }
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(UInt32(index), &name) != nil else { return nil }
        let result = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        namesByIndex[index] = result
        return result
    }
}
