import Foundation

/// Uygulama ↔ filtre uzantısı bağlantısının durumu (ana pencere, panel alt satırı ve Ayarlar › Filtre okur).
enum FilterLinkState: Equatable, Sendable {
    /// Filtre ayarı açık ve XPC bağlantısı veri getiriyor.
    case connected
    /// Filtre ayarı açık ama uzantıya ulaşılamıyor (ör. uzantı değişti); geri çekilmeli olarak yeniden deneniyor.
    case reconnecting(since: Date)
    /// Filtre ayarının durumu henüz okunmadı (açılış).
    case checking
    /// Filtre kurulu değil, kapalı, onay bekliyor ya da hata verdi.
    case inactive

    /// `installer.state` + XPC sonucundan durum.
    static func make(installer: ExtensionInstaller.State, connected: Bool, disconnectedSince: Date?, now: Date) -> FilterLinkState {
        switch installer {
        case .active: connected ? .connected : .reconnecting(since: disconnectedSince ?? now)
        case .unknown: .checking
        default: .inactive
        }
    }

    var isConnected: Bool { self == .connected }
}

/// Filtre bağlı değilken sayfalarda gösterilecek uyarının ağırlığı. PanelData'ya yalnızca bu ayrık değer girer
/// (süre girmez): sayfalar her ölçüm adımında değil, yalnızca seviye değişince yeniden çizilir (pil).
enum FilterAlertLevel: Equatable, Sendable {
    case none
    /// Wi-Fi/kablolu ağda: küçük, nötr not.
    case note
    /// Mobil veride: kırmızı şerit; sınırlar ve engeller uygulanmıyor.
    case critical
}

/// Bağlantı koptuğunda yeniden deneme aralığı: 2 → 4 → 8 → 16 → 30 sn (üst sınır). Duvar saatine göredir;
/// ölçüm adımının aralığından (1 sn / ayar) bağımsızdır. Ayrı zamanlayıcı yok: kontrol `AppModel.step` içinde.
struct FilterBackoff: Equatable, Sendable {
    static let maxDelay: TimeInterval = 30
    /// Her kaç ardışık hatada bir uyarı günlüğe yazılır (ilk hata her zaman yazılır).
    static let logEvery = 10

    private(set) var failures = 0
    private(set) var nextAttempt: Date?
    /// İlk ardışık hatanın zamanı (bağlıyken nil).
    private(set) var failingSince: Date?

    static func delay(afterFailures n: Int) -> TimeInterval {
        guard n > 0 else { return 0 }
        return min(maxDelay, 2 * pow(2, Double(min(n, 16) - 1)))
    }

    func shouldAttempt(now: Date) -> Bool { nextAttempt.map { now >= $0 } ?? true }

    /// Hata kaydeder; günlüğe yazılması gerekiyorsa true (ilk hata ve her `logEvery`'de bir).
    @discardableResult
    mutating func recordFailure(now: Date) -> Bool {
        failures += 1
        if failingSince == nil { failingSince = now }
        nextAttempt = now.addingTimeInterval(Self.delay(afterFailures: failures))
        return failures == 1 || failures % Self.logEvery == 0
    }

    /// Bir sonraki denemeyi hemen yaptırır (ardışık hata sayısı ve başlangıç zamanı korunur).
    mutating func allowImmediateAttempt() { nextAttempt = nil }

    mutating func recordSuccess() {
        failures = 0
        nextAttempt = nil
        failingSince = nil
    }
}

/// Filtre bağlı değilken uyarı kararları: 60 sn tolerans, mobilde bildirim (durum sürdükçe en çok 30 dk'da bir).
/// Saf mantık; zaman dışarıdan verilir.
struct FilterLinkWatch: Equatable, Sendable {
    static let grace: TimeInterval = 60
    static let repeatInterval: TimeInterval = 30 * 60

    private(set) var downSince: Date?
    private(set) var lastAlert: Date?

    /// Durumu günceller; dönen seviye sayfalarda gösterilir, `alert` true ise bildirim gönderilmelidir.
    mutating func update(connected: Bool, isMobile: Bool, now: Date) -> (level: FilterAlertLevel, alert: Bool) {
        if connected {
            downSince = nil
            lastAlert = nil // yeni bir kopuşta yeniden bir kez bildirilsin
            return (.none, false)
        }
        let since = downSince ?? now
        downSince = since
        guard now.timeIntervalSince(since) > Self.grace else { return (.none, false) }
        guard isMobile else { return (.note, false) }
        let due = lastAlert.map { now.timeIntervalSince($0) >= Self.repeatInterval } ?? true
        if due { lastAlert = now }
        return (.critical, due)
    }
}

/// Elle engellenen bir uygulama ve kapsamı (Mobilde / Wi-Fi'de / Her yerde).
struct BlockedAppEntry: Equatable, Hashable, Identifiable, Sendable {
    let app: String
    let scope: BlockScope
    var id: String { app }

    /// Mobil sırası önce, ardından yalnızca Wi-Fi'de engellenenler; tekrar yok.
    static func list(mobile: [String], wifi: [String]) -> [BlockedAppEntry] {
        let wifiSet = Set(wifi)
        var seen = Set<String>()
        var out: [BlockedAppEntry] = []
        for app in mobile where seen.insert(app).inserted {
            out.append(BlockedAppEntry(app: app, scope: wifiSet.contains(app) ? .everywhere : .mobile))
        }
        for app in wifi where seen.insert(app).inserted {
            out.append(BlockedAppEntry(app: app, scope: .wifi))
        }
        return out
    }

    /// Şu anki ağda etkili mi.
    func isActive(onMobile: Bool) -> Bool { onMobile ? scope.blocksMobile : scope.blocksWiFi }
}
