import Darwin
import Foundation

/// Çalışan Claude Code CLI süreçlerini bulur. Adalmon bir oturumdan SONRA açılırsa (ya da oturum boşta bekleyip hiç olay üretmezse)
/// oturum yalnızca olaylardan tanınamaz; bu tarama pid + çalışma klasöründen "bekleyen oturum" üretir. Gerçek olay gelince yerini
/// gerçek oturum alır. Yalnızca aynı kullanıcının süreçleri okunur; komut satırı argümanları sadece ayıklama için bakılır, saklanmaz.
enum ClaudeProcessDiscovery {
    struct Candidate: Equatable, Sendable {
        var pid: Int32
        var argv: [String]
        var cwd: String
    }

    struct Found: Equatable, Sendable {
        var pid: Int32
        var project: String
    }

    /// Saf ayıklama: etkileşimli Claude CLI oturumları. Başsız (`-p`/`--print`) çalıştırmalar, MCP/native-host yardımcıları elenir.
    static func filter(_ candidates: [Candidate]) -> [Found] {
        var out: [Found] = []
        for c in candidates {
            guard let first = c.argv.first, (first as NSString).lastPathComponent == "claude" else { continue }
            let rest = c.argv.dropFirst()
            if rest.contains(where: { $0 == "-p" || $0 == "--print" || $0 == "mcp" || $0.contains("native-host") || $0 == "--mcp" }) { continue }
            let name = (c.cwd as NSString).lastPathComponent
            out.append(Found(pid: c.pid, project: name.isEmpty || name == "/" ? "?" : name))
        }
        return out.sorted { $0.pid < $1.pid }
    }

    /// Sistem taraması (birkaç ms; yalnızca açılışta / uygulama öne gelince, en çok 10 sn'de bir çağrılır).
    static func scan() -> [Found] {
        var candidates: [Candidate] = []
        let me = getpid()
        for pid in CoalitionAPI.listPIDs() where pid != me {
            guard let argv = arguments(of: pid), let first = argv.first, (first as NSString).lastPathComponent == "claude" else { continue }
            candidates.append(Candidate(pid: pid, argv: argv, cwd: workingDirectory(of: pid) ?? ""))
        }
        return filter(candidates)
    }

    /// `KERN_PROCARGS2`: argc, yürütülebilir yol, dolgu, sonra argv dizileri.
    static func arguments(of pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }          // yürütülebilir yol
        while index < size, buffer[index] == 0 { index += 1 }          // dolgu
        var args: [String] = []
        while index < size, args.count < min(argc, 64) {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            args.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return args
    }

    static func workingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }
}
