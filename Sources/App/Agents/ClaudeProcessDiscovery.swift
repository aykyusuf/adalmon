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

    /// Projenin son gerçek etkinliği: en yeni birkaç `*.jsonl` transkriptin İÇİNDEKİ son zaman damgalı kayıt (kullanıcı istemi, asistan çıktısı,
    /// araç sonucu, tur sonu). Dosyanın değişim zamanı KULLANILMAZ: Claude Code dosyanın sonuna düzenli aralıkla zaman damgasız durum kayıtları
    /// (`last-prompt`, `custom-title`, `session-owner`, `bridge-session`…) yazar; oturum saatlerdir boştayken bile dosya "değişir".
    /// Hiç damgalı kayıt bulunamazsa nil.
    static func lastTranscriptActivity(cwd: String, projectsRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects", directoryHint: .isDirectory)) -> Date? {
        guard !cwd.isEmpty else { return nil }
        let dir = projectsRoot.appending(path: transcriptDirectoryName(forCWD: cwd), directoryHint: .isDirectory)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        let newest = files.filter { $0.pathExtension == "jsonl" }
            .compactMap { url -> (URL, Date)? in
                guard let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
                return (url, m)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
        // Sonda yalnızca damgasız durum kayıtları birikmişse (çok uzun boşta) pencere büyütülerek bir kez daha denenir.
        return newest.compactMap { lastRecordTimestamp(in: $0.0) ?? lastRecordTimestamp(in: $0.0, tailBytes: 8 * 1024 * 1024) }.max()
    }

    /// Dosyanın sonundan (`tailBytes`) geriye doğru ilk zaman damgalı kaydın zamanı. Satır başına `"timestamp":"…"` aranır (tam JSON çözümü
    /// gerekmez); metin içindeki kaçışlı `\"timestamp\"` ifadeleri eşleşmez.
    static func lastRecordTimestamp(in url: URL, tailBytes: Int = 512 * 1024) -> Date? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }          // kesilmiş ilk satır
        let marker = Array("\"timestamp\":\"".utf8)
        for line in lines.reversed() {
            let bytes = Array(line)
            guard let at = find(marker, in: bytes) else { continue }
            let from = at + marker.count
            guard let end = bytes[from...].firstIndex(of: UInt8(ascii: "\"")) else { continue }
            let text = String(decoding: bytes[from..<end], as: UTF8.self)
            if let date = parseISO(text) { return date }
        }
        return nil
    }

    private static func find(_ needle: [UInt8], in hay: [UInt8]) -> Int? {
        guard needle.count <= hay.count, let first = needle.first else { return nil }
        var i = 0
        let last = hay.count - needle.count
        while i <= last {
            if hay[i] == first, hay[i..<(i + needle.count)].elementsEqual(needle) { return i }
            i += 1
        }
        return nil
    }

    static func parseISO(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: text) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
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
