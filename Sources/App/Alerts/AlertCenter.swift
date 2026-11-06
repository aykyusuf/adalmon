import Foundation
@preconcurrency import UserNotifications

/// Mobil veride ani kullanım ve günlük limit bildirimleri. "Mobilde engelle" eylemi taşır.
@MainActor
final class AlertCenter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let blockAction = "BLOCK_ON_MOBILE"
    static let burstCategory = "BURST"

    /// Bildirimdeki "engelle" tıklanınca çağrılır (uygulama anahtarı ile).
    var onBlock: ((String) -> Void)?

    private let center = UNUserNotificationCenter.current()
    private var lastBurst: [String: Date] = [:]
    private var capLevelsSent: Set<Int> = []
    private let calendar: Calendar
    private var capDay: String

    init(calendar: Calendar = UsageStore.keyCalendar) {
        self.calendar = calendar
        self.capDay = UsageStore.dayKey(calendar: calendar)
        super.init()
        center.delegate = self
        let block = UNNotificationAction(identifier: Self.blockAction, title: "Mobilde engelle", options: [.destructive])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.burstCategory, actions: [block], intentIdentifiers: [])])
        center.requestAuthorization(options: [.alert, .sound]) { @Sendable _, _ in }
    }

    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "info-\(title)", content: content, trigger: nil))
    }

    /// Bildirimden engelleme yapılınca sonucu teyit eder.
    func notifyBlocked(name: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(name) mobil veride engellendi"
        content.body = "Wi-Fi'de etkilenmez. Kaldırmak için Adalmon panelindeki listeyi kullan."
        center.add(UNNotificationRequest(identifier: "blocked-\(name)", content: content, trigger: nil))
    }

    /// Son 60 sn'de eşiği aşan uygulamalar için (uygulama başına 5 dakikada bir).
    func checkBursts(_ apps: [AppUsage], threshold: UInt64, isMobile: Bool) {
        guard isMobile else { return }
        for a in apps where a.bytes >= threshold {
            if let t = lastBurst[a.app], Date.now.timeIntervalSince(t) < 300 { continue }
            lastBurst[a.app] = .now
            let name = AppCatalog.shared.name(for: a.app)
            let domain = a.domains.first.map { " · \($0.name)" } ?? ""
            let content = UNMutableNotificationContent()
            content.title = "\(name) mobil veriyi hızlı harcıyor"
            content.body = "Son 1 dakikada \(Format.bytes(a.bytes))\(domain)"
            content.sound = .default
            content.categoryIdentifier = Self.burstCategory
            content.userInfo = ["app": a.app]
            center.add(UNNotificationRequest(identifier: "burst-\(a.app)", content: content, trigger: nil))
        }
    }

    /// Günlük mobil limitin %50 / %80 / %100'ünde bir kez.
    func checkCap(used: UInt64, cap: UInt64, now: Date = .now) {
        let day = UsageStore.dayKey(now, calendar: calendar)
        if day != capDay { capDay = day; capLevelsSent = [] }
        guard cap > 0 else { return }
        let pct = Int(Double(used) / Double(cap) * 100)
        for level in [100, 80, 50] where pct >= level {
            guard !capLevelsSent.contains(level) else { break }
            capLevelsSent.formUnion([50, 80, 100].filter { $0 <= level })
            let content = UNMutableNotificationContent()
            content.title = level >= 100 ? "Günlük mobil veri limiti aşıldı" : "Günlük mobil verinin %\(level)'i kullanıldı"
            content.body = "\(Format.bytes(used)) / \(Format.bytes(cap))"
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "cap-\(level)", content: content, trigger: nil))
            break
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let app = response.actionIdentifier == Self.blockAction
            ? response.notification.request.content.userInfo["app"] as? String : nil
        if let app { Task { @MainActor in self.onBlock?(app) } }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
