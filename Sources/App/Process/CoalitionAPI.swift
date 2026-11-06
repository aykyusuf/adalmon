import Darwin
import Foundation

/// Düşük seviye sistem çağrıları: coalition sayaçları (özel API, `dlsym`), süreç listesi, süreç yolu, süreç rusage.
/// Hepsi kök yetkisi gerektirmez. Özel semboller yoksa ya da saçma değer dönerse çağıran yedek yola düşer.
enum CoalitionAPI {
    private typealias CRUFn = @convention(c) (UInt64, UnsafeMutableRawPointer, Int) -> Int32
    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t

    private static let cruFn: CRUFn? = {
        guard let handle = dlopen(nil, RTLD_NOW), let sym = dlsym(handle, "coalition_info_resource_usage") else { return nil }
        return unsafeBitCast(sym, to: CRUFn.self)
    }()

    private static let responsibleFn: ResponsibleFn? = {
        guard let handle = dlopen(nil, RTLD_NOW), let sym = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    static var isCoalitionCounterAvailable: Bool { cruFn != nil }

    static let physicalMemory = ProcessInfo.processInfo.physicalMemory

    /// `PROC_PIDCOALITIONINFO` (SDK başlığında yok): coalition_id[2] + 3 ayrılmış alan.
    private struct ProcCoalitionInfo {
        var ids: (UInt64, UInt64) = (0, 0)
        var reserved1: UInt64 = 0
        var reserved2: UInt64 = 0
        var reserved3: UInt64 = 0
    }
    private static let procPidCoalitionInfo: Int32 = 20

    /// `struct coalition_resource_usage` (xnu osfmk/mach/coalition.h) indeksleri; sona ekleme olur, bunlar sabit.
    private enum Field {
        static let tasksStarted = 0, tasksExited = 1, cpuTime = 3, bytesRead = 6, bytesWritten = 7
        static let gpuTime = 8, energy = 11, footprint = 40
        static let count = 45
    }

    static func listPIDs() -> [pid_t] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 64)
        let r = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard r > 0 else { return [] }
        return pids.prefix(Int(r)).filter { $0 > 0 }
    }

    /// Kaynak coalition numarası (resource coalition); okunamazsa nil.
    static func coalitionID(of pid: pid_t) -> UInt64? {
        var info = ProcCoalitionInfo()
        let rc = proc_pidinfo(pid, procPidCoalitionInfo, 0, &info, Int32(MemoryLayout<ProcCoalitionInfo>.size))
        return rc > 0 && info.ids.0 != 0 ? info.ids.0 : nil
    }

    /// Sorumlu (lider) süreç; sembol yoksa ya da izin yoksa nil.
    static func responsiblePID(for pid: pid_t) -> pid_t? {
        guard let responsibleFn else { return nil }
        let r = responsibleFn(pid)
        return r > 0 ? r : nil
    }

    /// Coalition sayaçları. Başarısızlık ya da saçma değer (footprint > fiziksel RAM'in 4 katı) nil döner.
    static func counters(of coalition: UInt64) -> CoalitionCounters? {
        guard let cruFn else { return nil }
        let size = 512
        let buf = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { buf.deallocate() }
        memset(buf, 0, size)
        guard cruFn(coalition, buf, size) == 0 else { return nil }
        func field(_ i: Int) -> UInt64 { buf.load(fromByteOffset: i * 8, as: UInt64.self) }
        let c = CoalitionCounters(tasksStarted: field(Field.tasksStarted), tasksExited: field(Field.tasksExited),
                                  cpuTicks: field(Field.cpuTime), bytesRead: field(Field.bytesRead),
                                  bytesWritten: field(Field.bytesWritten), gpuNs: field(Field.gpuTime),
                                  energyNj: field(Field.energy), footprint: field(Field.footprint))
        return c.footprint > physicalMemory &* 4 ? nil : c
    }

    static func path(of pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4_096)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
    }

    /// Süreç rusage (yalnızca aynı kullanıcının süreçleri; diğerleri EPERM → nil).
    static func processCounters(of pid: pid_t) -> (key: ProcessKey, counters: ProcessCounters)? {
        var ru = rusage_info_v6()
        let rc = withUnsafeMutablePointer(to: &ru) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
        }
        guard rc == 0 else { return nil }
        let c = ProcessCounters(cpuTicks: ru.ri_user_time &+ ru.ri_system_time, bytesWritten: ru.ri_diskio_byteswritten,
                                bytesRead: ru.ri_diskio_bytesread, energyNj: ru.ri_energy_nj, footprint: ru.ri_phys_footprint)
        return (ProcessKey(pid: pid, start: ru.ri_proc_start_abstime), c)
    }
}
