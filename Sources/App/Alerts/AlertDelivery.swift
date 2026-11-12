import AppKit
import Foundation
@preconcurrency import UserNotifications

// NOTIF-01: uyarıların nasıl geleceği (uygulama içi balon / macOS sistem bildirimi / ikisi). Yönlendirme saf ve testlidir;
// gerçek bildirim yalnızca `UNSystemNotifier` üzerinden gider (testte sahte gönderici kullanılır).

enum AlertDelivery: String, CaseIterable, Identifiable, Sendable {
    case inApp, system, both

    var id: String { rawValue }
    var title: String {
        switch self {
        case .inApp: "Uygulama içi"
        case .system: "Sistem bildirimi"
        case .both: "İkisi de"
        }
    }

    var wantsSystem: Bool { self != .inApp }

    /// İzin yoksa (reddedildi ya da henüz sorulmadı) sistem bildirimi yerine uygulama içi gösterilir; uyarı kaybolmaz.
    func route(permission: NotificationPermission) -> AlertRoute {
        let system = permission == .authorized
        return switch self {
        case .inApp: AlertRoute(inApp: true, system: false)
        case .system: AlertRoute(inApp: !system, system: system)
        case .both: AlertRoute(inApp: true, system: system)
        }
    }
}

enum NotificationPermission: Sendable {
    case notDetermined, denied, authorized
}

struct AlertRoute: Equatable, Sendable {
    var inApp: Bool
    var system: Bool
}

/// Bir uyarının içeriği. Sistem bildirimi yolunda kimlik, kategori ve userInfo önceki haliyle aynen kullanılır.
struct AlertMessage: Equatable, Sendable {
    var id: String
    var title: String
    var body: String
    var sound = true
    var category: String?
    var userInfo: [String: String] = [:]
    /// Uygulama içi balondaki simge (SF Symbol).
    var symbol = "bell.badge.fill"
}

/// Uygulama içi balondaki isteğe bağlı düğme (ör. "Mobilde engelle").
struct InAppAlertAction {
    var title: String
    var run: @MainActor () -> Void
}

@MainActor
protocol SystemNotifying: AnyObject {
    /// Sistem bildirimindeki "Mobilde engelle" eylemi (uygulama anahtarı ile).
    var onBlock: ((String) -> Void)? { get set }
    func post(_ message: AlertMessage)
    func permission() async -> NotificationPermission
    func requestPermission() async -> NotificationPermission
}

/// Gerçek gönderici: UNUserNotificationCenter. İzin yalnızca `requestPermission` çağrılınca istenir.
@MainActor
final class UNSystemNotifier: NSObject, SystemNotifying, UNUserNotificationCenterDelegate {
    nonisolated static let blockAction = "BLOCK_ON_MOBILE"
    static let burstCategory = "BURST"

    var onBlock: ((String) -> Void)?
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        let block = UNNotificationAction(identifier: Self.blockAction, title: "Mobilde engelle", options: [.destructive])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.burstCategory, actions: [block], intentIdentifiers: [])])
    }

    func post(_ message: AlertMessage) {
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        if message.sound { content.sound = .default }
        if let category = message.category { content.categoryIdentifier = category }
        if !message.userInfo.isEmpty { content.userInfo = message.userInfo }
        center.add(UNNotificationRequest(identifier: message.id, content: content, trigger: nil))
    }

    func permission() async -> NotificationPermission {
        let status = await center.notificationSettings().authorizationStatus
        return switch status {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        default: .notDetermined
        }
    }

    func requestPermission() async -> NotificationPermission {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await permission()
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

    /// Sistem Ayarları › Bildirimler.
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
