import Darwin
import Foundation
import SystemConfiguration

/// Sistem proxy'si yerel bir süreçteyse (SpoofDPI/ByeDPI) portunu ve o portu dinleyen süreci bulur.
enum ProxyDetector {
    struct Result: Sendable, Equatable {
        var ports: [Int]
        var ownerPaths: [String]
    }

    /// Ucuz: yalnızca sistem proxy ayarından yerel portları okur (süreç taraması yok).
    static func localProxyPorts() -> [Int] {
        guard let dict = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return [] }
        return ports(from: dict).sorted()
    }

    /// Pahalı: portları dinleyen süreçleri de bulur. Seyrek çağır.
    static func detect() -> Result {
        let ports = Set(localProxyPorts())
        guard !ports.isEmpty else { return Result(ports: [], ownerPaths: []) }
        return Result(ports: ports.sorted(), ownerPaths: listeningProcessPaths(ports: ports).sorted())
    }

    private static func ports(from dict: [String: Any]) -> Set<Int> {
        var ports = Set<Int>()
        let pairs: [(String, String, String)] = [
            (kSCPropNetProxiesHTTPEnable as String, kSCPropNetProxiesHTTPProxy as String, kSCPropNetProxiesHTTPPort as String),
            (kSCPropNetProxiesHTTPSEnable as String, kSCPropNetProxiesHTTPSProxy as String, kSCPropNetProxiesHTTPSPort as String),
            (kSCPropNetProxiesSOCKSEnable as String, kSCPropNetProxiesSOCKSProxy as String, kSCPropNetProxiesSOCKSPort as String),
        ]
        for (enableKey, hostKey, portKey) in pairs {
            guard (dict[enableKey] as? Int) == 1,
                  let host = dict[hostKey] as? String, ["127.0.0.1", "localhost", "::1"].contains(host),
                  let port = dict[portKey] as? Int else { continue }
            ports.insert(port)
        }
        return ports
    }

    /// Verilen TCP portlarını LISTEN durumunda tutan süreçlerin yolları (yalnızca erişilebilen kullanıcı süreçleri).
    private static func listeningProcessPaths(ports: Set<Int>) -> [String] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var result = Set<String>()
        for pid in pids.prefix(Int(max(0, n))) where pid > 0 {
            let fdSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard fdSize > 0 else { continue }
            let fdCount = Int(fdSize) / MemoryLayout<proc_fdinfo>.stride
            var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
            let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, fdSize)
            guard got > 0 else { continue }
            for fd in fds.prefix(Int(got) / MemoryLayout<proc_fdinfo>.stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
                var info = socket_fdinfo()
                let sz = Int32(MemoryLayout<socket_fdinfo>.size)
                guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, sz) == sz,
                      info.psi.soi_kind == Int32(SOCKINFO_TCP) else { continue }
                let tcp = info.psi.soi_proto.pri_tcp
                guard tcp.tcpsi_state == Int32(TSI_S_LISTEN) else { continue }
                let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport)))
                if ports.contains(port) {
                    var buf = [CChar](repeating: 0, count: 4096)
                    let len = proc_pidpath(pid, &buf, UInt32(buf.count))
                    if len > 0 { result.insert(String(decoding: buf.prefix(Int(len)).map { UInt8(bitPattern: $0) }, as: UTF8.self)) }
                }
            }
        }
        return Array(result)
    }
}
