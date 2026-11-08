import Darwin
import Foundation

/// Gerçek süreç yoklaması: `kill(pid, 0)` (sinyal göndermez) + `sysctl KERN_PROC_PID` (başlangıç zamanı, zombi). Alt süreç yok.
struct SystemProcessProbe: ProcessLivenessProbing {
    func probe(pid: Int32) -> ProcessProbeResult {
        guard pid > 1 else { return .dead }
        // ESRCH = yok; EPERM = var ama başka kullanıcının (yaşıyor say); diğer hatalar da yaşıyor sayılır (yanlışlıkla kapatma yok).
        if kill(pid, 0) != 0, errno == ESRCH { return .dead }
        guard let info = Self.kernelInfo(pid: pid) else { return .alive(startedAt: nil) }
        if Int32(info.kp_proc.p_stat) == SZOMB { return .dead } // çıkmış ama henüz toplanmamış
        let start = info.kp_proc.p_un.__p_starttime
        return .alive(startedAt: Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000))
    }

    /// `nil` = süreç yok ya da okunamadı.
    static func kernelInfo(pid: Int32) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        return info
    }
}
