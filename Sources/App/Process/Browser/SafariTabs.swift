import Foundation

/// Safari'deki bir sekme (AppleScript: başlık + URL). Safari sekme ↔ süreç (PID) eşlemesini hiçbir public yolla vermez;
/// bu yüzden sekmede RAM alanı YOK.
struct SafariTab: Equatable, Sendable, Identifiable {
    /// 1'den başlayan pencere sırası (AppleScript `windows` sırası: öndeki pencere 1).
    var window: Int
    /// Pencere içindeki 1'den başlayan sekme sırası.
    var index: Int
    var title: String
    var url: String
    var id: String { "\(window)-\(index)" }
}

/// AppleScript betiği ve çıktısının ayrıştırılması (saf; testlerde gerçek Safari çağrılmaz).
enum SafariTabsScript {
    /// Kayıt ayırıcı (ASCII RS) ve alan ayırıcı (ASCII US): başlıklarda virgül/satır sonu olabilir, bunlar olmaz.
    static let recordSeparator: Character = "\u{1E}"
    static let fieldSeparator: Character = "\u{1F}"
    /// Safari çalışmıyorsa betik bunu döner (`tell application` Safari'yi BAŞLATMASIN diye önce kontrol edilir).
    static let notRunningMarker = "__ADALMON_SAFARI_NOT_RUNNING__"
    /// Betik içi zaman aşımı (sn). Swift tarafında ayrıca bir yarış zaman aşımı vardır.
    static let timeoutSeconds = 5

    /// Pencere başına iki Apple olayı (tüm başlıklar, tüm URL'ler); sekme başına olay göndermez.
    static let source = """
    if application id "com.apple.Safari" is running then
        set RS to character id 30
        set US to character id 31
        set out to ""
        with timeout of \(timeoutSeconds) seconds
            tell application id "com.apple.Safari"
                set wi to 0
                repeat with w in windows
                    set wi to wi + 1
                    try
                        set nms to name of every tab of w
                        set urls to URL of every tab of w
                        repeat with i from 1 to count of nms
                            set nm to item i of nms
                            if nm is missing value then set nm to ""
                            set u to ""
                            if i ≤ (count of urls) then
                                set u to item i of urls
                                if u is missing value then set u to ""
                            end if
                            set out to out & wi & US & i & US & nm & US & u & RS
                        end repeat
                    end try
                end repeat
            end tell
        end timeout
        return out
    else
        return "\(notRunningMarker)"
    end if
    """

    /// Betik çıktısını sekmelere ayırır. Bozuk kayıtlar atlanır; pencere/sekme sırası korunur.
    static func parse(_ output: String) -> [SafariTab] {
        guard output != notRunningMarker else { return [] }
        var tabs: [SafariTab] = []
        for record in output.split(separator: recordSeparator, omittingEmptySubsequences: true) {
            let fields = record.split(separator: fieldSeparator, maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4,
                  let window = Int(fields[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let index = Int(fields[1].trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
            tabs.append(SafariTab(window: window, index: index, title: String(fields[2]), url: String(fields[3])))
        }
        return tabs
    }

    /// Safari çalışmıyor işareti mi?
    static func isNotRunning(_ output: String) -> Bool { output == notRunningMarker }
}

/// Safari Otomasyon (Apple Events) izni durumu.
enum SafariAutomationPermission: Equatable, Sendable {
    case granted
    /// Henüz sorulmadı: ilk çağrı sistem izin penceresini açar.
    case notDetermined
    case denied
    case safariNotRunning
    case unknown(Int32)

    /// `AEDeterminePermissionToAutomateTarget` dönüş kodundan.
    static func from(status: Int32) -> SafariAutomationPermission {
        switch status {
        case 0: .granted
        case -1744: .notDetermined   // errAEEventWouldRequireUserConsent
        case -1743: .denied          // errAEEventNotPermitted
        case -600, -609: .safariNotRunning  // procNotFound, connectionInvalid
        default: .unknown(status)
        }
    }
}

/// Safari sekme listesi alınamadığında okunaklı hata.
enum SafariTabsError: Error, Equatable, Sendable {
    case notRunning
    case permissionDenied
    case permissionNotDetermined
    case timeout
    case scriptFailed(Int)

    /// AppleScript hata numarasından (`NSAppleScript.errorNumber`).
    static func from(appleScriptError code: Int) -> SafariTabsError {
        switch code {
        case -1743: .permissionDenied
        case -1744: .permissionNotDetermined
        case -600, -609, -10810: .notRunning
        case -1712: .timeout
        default: .scriptFailed(code)
        }
    }

    var message: String {
        switch self {
        case .notRunning: "Safari açık değil."
        case .permissionDenied:
            "Adalmon'un Safari'yi denetleme izni kapalı. Sistem Ayarları › Gizlilik ve Güvenlik › Otomasyon › Adalmon altında “Safari”yi açın."
        case .permissionNotDetermined: "Safari sekmelerini okumak için Otomasyon izni gerekiyor."
        case .timeout: "Safari zamanında yanıt vermedi (\(SafariTabsScript.timeoutSeconds) sn). Daha sonra yeniden denenecek."
        case .scriptFailed(let code): "Safari sekme listesi alınamadı (hata \(code))."
        }
    }
}

/// Safari WebContent süreci (Safari'nin sorumlu olduğu `com.apple.WebKit.WebContent`).
struct WebContentProcess: Equatable, Sendable, Identifiable {
    var pid: Int32
    /// Fiziksel ayak izi (bayt).
    var footprint: UInt64
    var id: Int32 { pid }
}

/// Safari WebContent RAM özeti. Sekme ↔ süreç eşlemesi olmadığı için sekme başına gerçek rakam YOK; yalnızca toplam ve
/// "ortalama" (toplam ÷ sekme sayısı) verilir. Safari arka plandaki sekmeleri boşaltabildiğinden yüklü sekme sayısı bilinmez.
struct SafariMemorySummary: Equatable, Sendable {
    /// RAM'e göre büyükten küçüğe.
    var processes: [WebContentProcess]
    var total: UInt64
    var tabCount: Int

    init(processes: [WebContentProcess], tabCount: Int) {
        self.processes = processes.sorted { $0.footprint != $1.footprint ? $0.footprint > $1.footprint : $0.pid < $1.pid }
        self.total = processes.reduce(UInt64(0)) { $0 &+ $1.footprint }
        self.tabCount = tabCount
    }

    /// Sekme başına ortalama (toplam ÷ tüm sekmeler); sekme yoksa nil.
    var averagePerTab: UInt64? { tabCount > 0 ? total / UInt64(tabCount) : nil }
}

/// WebContent süreçlerini seçme kuralı (saf): yolu `com.apple.WebKit.WebContent` içeren VE sorumlu süreci Safari olanlar.
/// Mail ve diğer WKWebView uygulamaları da WebContent çalıştırır; ada göre değil sorumlu sürece göre ayrılır.
enum SafariWebContentFilter {
    static func isWebContent(path: String) -> Bool {
        path.contains("com.apple.WebKit.WebContent") && !path.contains("Networking") && !path.contains("com.apple.WebKit.GPU")
    }

    static func select(pids: [Int32], safariPIDs: Set<Int32>, path: (Int32) -> String?, responsible: (Int32) -> Int32?,
                       footprint: (Int32) -> UInt64?) -> [WebContentProcess] {
        guard !safariPIDs.isEmpty else { return [] }
        var out: [WebContentProcess] = []
        for pid in pids {
            guard let owner = responsible(pid), safariPIDs.contains(owner), !safariPIDs.contains(pid),
                  let p = path(pid), isWebContent(path: p), let bytes = footprint(pid) else { continue }
            out.append(WebContentProcess(pid: pid, footprint: bytes))
        }
        return out
    }
}
