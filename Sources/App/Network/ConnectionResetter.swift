import Darwin
import Foundation

/// XNU'nun özel `pid_shutdown_sockets` çağrısı (libsystem_kernel dışa aktarır). `level` 2 = DISCONNECT_ALL.
/// Aynı kullanıcının süreçleri için root gerekmez; başka kullanıcı / root süreçlerinde EPERM döner.
@_silgen_name("pid_shutdown_sockets")
private func pid_shutdown_sockets(_ pid: Int32, _ level: Int32) -> Int32

/// Bir uygulamanın açık (uzun ömürlü) bağlantılarını keser; uygulama kendi yeniden bağlanır ve
/// yeni bağlantılar filtreden / hız sınırından geçer. Süreç ölmez.
enum ConnectionResetter {
    private static let disconnectAll: Int32 = 2

    struct Candidate: Equatable, Sendable {
        var pid: Int32
        var path: String
        var uid: UInt32
    }

    struct Failure: Equatable, Sendable {
        var pid: Int32
        var errno: Int32
    }

    struct ResetResult: Equatable, Sendable {
        /// Eşleşen (hedeflenen) süreçler.
        var matchedPIDs: [Int32] = []
        /// Bağlantıları başarıyla kesilenler.
        var resetPIDs: [Int32] = []
        var failedPIDs: [Failure] = []

        /// Uygulama çalışıyor ama hiçbir süreçte sıfırlama yapılamadı → tek çare yeniden başlatma.
        var needsRestart: Bool { resetPIDs.isEmpty && !failedPIDs.isEmpty }
        var isRunning: Bool { !matchedPIDs.isEmpty }
    }

    /// `appKey`: `.app` paket yolu ya da (paketsiz araçlar için) çalıştırılabilir dosya yolu.
    /// Hızlıdır ama senkron çalışır; ana aktörden çağırma (`Task.detached` / yardımcı kuyruk).
    static func resetConnections(forApp appKey: String) -> ResetResult {
        let targets = targetPIDs(in: runningProcesses(), appKey: appKey, ownPID: getpid(), uid: getuid())
        var result = ResetResult(matchedPIDs: targets)
        for pid in targets {
            if pid_shutdown_sockets(pid, disconnectAll) == 0 {
                result.resetPIDs.append(pid)
            } else {
                let code = errno
                if code == ESRCH { // süreç bu arada çıktı
                    result.matchedPIDs.removeAll { $0 == pid }
                } else {
                    result.failedPIDs.append(Failure(pid: pid, errno: code))
                }
            }
        }
        return result
    }

    /// Saf eşleştirme: yolu paketin içinde (`appKey + "/"` öneki) ya da tam eşit olan, kendi sürecimiz
    /// olmayan ve `uid` kullanıcısına ait süreçler.
    static func targetPIDs(in processes: [Candidate], appKey: String, ownPID: Int32, uid: UInt32) -> [Int32] {
        var key = appKey
        while key.count > 1, key.hasSuffix("/") { key.removeLast() }
        guard !key.isEmpty else { return [] }
        let isBundle = key.hasSuffix(".app")
        let prefix = key + "/"
        return processes.compactMap { p in
            guard p.pid != ownPID, p.uid == uid else { return nil }
            if p.path == key || (isBundle && p.path.hasPrefix(prefix)) { return p.pid }
            return nil
        }
    }

    // MARK: libproc

    /// Tüm süreçler: önce ucuz uid kontrolü, sonra yol. Yolu okunamayanlar atlanır.
    private static func runningProcesses() -> [Candidate] {
        let me = getuid()
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        let capacity = Int(estimate) * 2 + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let filled = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }

        var pathBuffer = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_MAXSIZE
        var found: [Candidate] = []
        for pid in pids.prefix(min(Int(filled), capacity)) where pid > 0 {
            guard owner(of: pid) == me else { continue }
            let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            guard length > 0 else { continue }
            let bytes = pathBuffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
            found.append(Candidate(pid: pid, path: String(decoding: bytes, as: UTF8.self), uid: me))
        }
        return found
    }

    private static func owner(of pid: pid_t) -> uid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbi_uid
    }
}
