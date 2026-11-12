import AppKit
import CryptoKit
import Darwin

/// Tek kopya koruması. Yalnızca AYNI bundle yolundaki kopyalar sayılır: DerivedData'daki Debug kopyası ya da test sunucusu
/// `/Applications/Adalmon.app` ile birbirini engellemez.
///
/// Birincil koruma: Application Support altında bundle yoluna özgü kilit dosyası + `flock(LOCK_EX|LOCK_NB)`. Kilit açık dosya
/// tanımlayıcısına bağlıdır; süreç nasıl ölürse ölsün otomatik kalkar. `NSRunningApplication` listesi ise süreç başlar başlamaz
/// kayıtlı olmayabilir (iki `open` arka arkaya gelince ikisi de birbirini göremez); kilit bu yarışı kapatır.
/// Yedek: kilidi bilmeyen eski sürümler için eski kural (daha küçük PID'li aynı yoldaki kopya varsa yeni olan çıkar).
enum SingleInstance {
    enum Outcome {
        case proceed
        /// Başka bir kopya zaten çalışıyor; varsa öne getirilecek örnek (kilit tutucusu henüz listede olmayabilir).
        case yield(to: NSRunningApplication?)
    }

    /// Kilidin ömrü süreç ömrü kadardır; bilerek bırakılmaz.
    nonisolated(unsafe) private static var heldLock: Lock?

    static func claim(bundleURL: URL = Bundle.main.bundleURL, bundleID: String? = Bundle.main.bundleIdentifier,
                      myPID: pid_t = ProcessInfo.processInfo.processIdentifier,
                      lockDirectory: URL = AppEnvironment.supportDirectory) -> Outcome {
        let lockURL = lockFileURL(bundleURL: bundleURL, directory: lockDirectory)
        guard let lock = Lock.acquire(at: lockURL) else {
            // Kilit başkasında: o kopya (listede varsa) öne gelsin, biz çıkarız.
            return .yield(to: sameBundleApps(bundleURL: bundleURL, bundleID: bundleID, myPID: myPID).first)
        }
        heldLock = lock
        if let older = olderInstance(bundleURL: bundleURL, bundleID: bundleID, myPID: myPID) { return .yield(to: older) }
        return .proceed
    }

    /// Yedek kural: aynı yoldaki, benden daha küçük PID'li kopya.
    static func olderInstance(bundleURL: URL = Bundle.main.bundleURL, bundleID: String? = Bundle.main.bundleIdentifier,
                              myPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> NSRunningApplication? {
        let others = sameBundleApps(bundleURL: bundleURL, bundleID: bundleID, myPID: myPID)
        return pick(otherPIDs: others.map(\.processIdentifier), myPID: myPID).flatMap { pid in others.first { $0.processIdentifier == pid } }
    }

    static func sameBundleApps(bundleURL: URL, bundleID: String?, myPID: pid_t) -> [NSRunningApplication] {
        guard let bundleID else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter {
            !$0.isTerminated && $0.processIdentifier != myPID && isSameBundle($0.bundleURL, bundleURL)
        }
    }

    static func pick(otherPIDs: [pid_t], myPID: pid_t) -> pid_t? {
        otherPIDs.filter { $0 < myPID }.min()
    }

    /// Simge bağlantıları ve `/private` önekleri çözülerek karşılaştırılır.
    static func isSameBundle(_ a: URL?, _ b: URL) -> Bool {
        guard let a else { return false }
        return canonicalPath(a) == canonicalPath(b)
    }

    static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// `instance-<sha1(bundle yolu)[0..8]>.lock`: farklı yoldaki kopyalar farklı dosyayı kilitler.
    static func lockFileURL(bundleURL: URL, directory: URL) -> URL {
        let digest = Insecure.SHA1.hash(data: Data(canonicalPath(bundleURL).utf8))
        let hex = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "instance-\(hex).lock", directoryHint: .notDirectory)
    }

    /// `flock` tabanlı süreç kilidi. Dosya tanımlayıcısı `O_CLOEXEC` ile açılır: çocuk süreçler (Process) kilidi miras alıp
    /// ana süreç öldükten sonra da tutmasın.
    final class Lock {
        private var fd: Int32

        private init(fd: Int32) { self.fd = fd }

        /// Kilit başkasındaysa (ya da dosya açılamazsa) `nil`.
        static func acquire(at url: URL) -> Lock? {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
            guard fd >= 0 else { return nil }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return nil }
            // Tanı için PID yazılır (kilit mantığı bunu kullanmaz).
            _ = ftruncate(fd, 0)
            let pid = Array("\(getpid())\n".utf8)
            _ = pwrite(fd, pid, pid.count, 0)
            return Lock(fd: fd)
        }

        func release() {
            guard fd >= 0 else { return }
            flock(fd, LOCK_UN)
            close(fd)
            fd = -1
        }

        deinit { release() }
    }
}
