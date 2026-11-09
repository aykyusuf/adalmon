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
        /// Süreç durdurulmuş (Ctrl+Z / SIGSTOP): terminalde arka plana atılmış, çalışmıyor.
        var stopped = false
        /// Projenin en son transkript değişimi (≈ oturumun son etkinliği).
        var lastActivity: Date?
    }

    struct Found: Equatable, Sendable {
        var pid: Int32
        var project: String
        var lastActivity: Date?
    }

    /// Saf ayıklama: etkileşimli Claude CLI oturumları. Başsız (`-p`/`--print`) çalıştırmalar, MCP/native-host yardımcıları elenir.
    static func filter(_ candidates: [Candidate]) -> [Found] {
        var out: [Found] = []
        for c in candidates {
            guard !c.stopped, let first = c.argv.first, (first as NSString).lastPathComponent == "claude" else { continue }
            let rest = c.argv.dropFirst()
            if rest.contains(where: { $0 == "-p" || $0 == "--print" || $0 == "mcp" || $0.contains("native-host") || $0 == "--mcp" }) { continue }
            let name = (c.cwd as NSString).lastPathComponent
            out.append(Found(pid: c.pid, project: name.isEmpty || name == "/" ? "?" : name, lastActivity: c.lastActivity))
        }
        return out.sorted { $0.pid < $1.pid }
    }

    /// Sistem taraması (birkaç ms; yalnızca açılışta / uygulama öne gelince, en çok 10 sn'de bir çağrılır).
    static func scan() -> [Found] {
        var candidates: [Candidate] = []
        let me = getpid()
        for pid in CoalitionAPI.listPIDs() where pid != me {
            guard let argv = arguments(of: pid), let first = argv.first, (first as NSString).lastPathComponent == "claude" else { continue }
            let cwd = workingDirectory(of: pid) ?? ""
            candidates.append(Candidate(pid: pid, argv: argv, cwd: cwd, stopped: isStopped(pid), lastActivity: lastTranscriptActivity(cwd: cwd)))
        }
        return filter(candidates)
    }

    /// Claude Code'un transkript klasör adı: çalışma yolunda harf/rakam dışındaki her karakter "-" olur
    /// (`/Users/x/adaltek-social/adaltek_social` → `-Users-x-adaltek-social-adaltek-social`).
    static func transcriptDirectoryName(forCWD cwd: String) -> String {
        String(String.UnicodeScalarView(cwd.unicodeScalars.map { ($0.isASCII && (CharacterSet.alphanumerics.contains($0))) ? $0 : "-" }))
    }

    /// Projenin en yeni `*.jsonl` transkriptinin değişim zamanı (oturum son ne zaman çalıştı); yoksa nil.
    static func lastTranscriptActivity(cwd: String, projectsRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects", directoryHint: .isDirectory)) -> Date? {
        guard !cwd.isEmpty else { return nil }
        let dir = projectsRoot.appending(path: transcriptDirectoryName(forCWD: cwd), directoryHint: .isDirectory)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        return files.filter { $0.pathExtension == "jsonl" }
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
    }

    /// Süreç durmuş mu (`SSTOP`)?
    static func isStopped(_ pid: Int32) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        return info.pbi_status == 4   // SSTOP
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
