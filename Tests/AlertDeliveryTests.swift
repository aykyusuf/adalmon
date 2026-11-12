import XCTest
@testable import Adalmon

/// NOTIF-01: uyarı yönlendirmesi (uygulama içi / sistem / ikisi) ve izin akışı. Gerçek bildirim gönderilmez (sahte gönderici).
@MainActor
final class AlertDeliveryTests: XCTestCase {
    final class FakeNotifier: SystemNotifying {
        var onBlock: ((String) -> Void)?
        var posted: [AlertMessage] = []
        var current: NotificationPermission
        var answer: NotificationPermission
        var requests = 0

        init(current: NotificationPermission, answer: NotificationPermission = .authorized) {
            self.current = current
            self.answer = answer
        }

        func post(_ message: AlertMessage) { posted.append(message) }
        func permission() async -> NotificationPermission { current }
        func requestPermission() async -> NotificationPermission { requests += 1; current = answer; return answer }
    }

    private func makeCenter(_ notifier: FakeNotifier, delivery: AlertDelivery) async -> (AlertCenter, () -> [AlertMessage]) {
        let center = AlertCenter(notifier: notifier)
        center.delivery = { delivery }
        var shown: [AlertMessage] = []
        center.presentInApp = { message, _ in shown.append(message) }
        await center.refreshPermission()
        return (center, { shown })
    }

    func testRouteTable() {
        XCTAssertEqual(AlertDelivery.inApp.route(permission: .authorized), AlertRoute(inApp: true, system: false))
        XCTAssertEqual(AlertDelivery.system.route(permission: .authorized), AlertRoute(inApp: false, system: true))
        XCTAssertEqual(AlertDelivery.both.route(permission: .authorized), AlertRoute(inApp: true, system: true))
        // No permission (denied or never asked): fall back to in-app, nothing is lost.
        for permission in [NotificationPermission.denied, .notDetermined] {
            XCTAssertEqual(AlertDelivery.system.route(permission: permission), AlertRoute(inApp: true, system: false))
            XCTAssertEqual(AlertDelivery.both.route(permission: permission), AlertRoute(inApp: true, system: false))
            XCTAssertEqual(AlertDelivery.inApp.route(permission: permission), AlertRoute(inApp: true, system: false))
        }
    }

    func testInAppDefaultNeverPostsOrAsks() async {
        let notifier = FakeNotifier(current: .notDetermined)
        let (center, shown) = await makeCenter(notifier, delivery: .inApp)
        center.notify(title: "Claude 5 saatlik limit: %80 kullanıldı", body: "1 sa sonra yenilenir")
        XCTAssertEqual(shown().map(\.title), ["Claude 5 saatlik limit: %80 kullanıldı"])
        XCTAssertTrue(notifier.posted.isEmpty)
        await center.deliveryChanged(to: .inApp)
        XCTAssertEqual(notifier.requests, 0)
    }

    func testSystemChoiceAsksOnceThenPostsWithSameContent() async {
        let notifier = FakeNotifier(current: .notDetermined, answer: .authorized)
        let (center, shown) = await makeCenter(notifier, delivery: .system)
        await center.deliveryChanged(to: .system)
        XCTAssertEqual(notifier.requests, 1)
        XCTAssertEqual(center.permission, .authorized)
        center.checkCap(used: 900, cap: 1000)
        XCTAssertEqual(notifier.posted.map(\.id), ["cap-80"])
        XCTAssertEqual(notifier.posted.first?.title, "Günlük mobil verinin %80'i kullanıldı")
        XCTAssertTrue(shown().isEmpty)
        // Already authorized: picking "İkisi de" does not ask again.
        await center.deliveryChanged(to: .both)
        XCTAssertEqual(notifier.requests, 1)
    }

    func testDeniedFallsBackToInApp() async {
        let notifier = FakeNotifier(current: .notDetermined, answer: .denied)
        let (center, shown) = await makeCenter(notifier, delivery: .system)
        await center.deliveryChanged(to: .system)
        XCTAssertEqual(center.permission, .denied)
        center.notify(title: "Kural devrede: X", body: "Y")
        XCTAssertTrue(notifier.posted.isEmpty)
        XCTAssertEqual(shown().map(\.title), ["Kural devrede: X"])
    }

    /// Yerel proxy'ye giden loopback trafiği (mobil değil) toplamı yüksek olsa da patlama uyarısı vermez.
    func testBurstUsesMobileBytesNotTotal() async {
        let notifier = FakeNotifier(current: .authorized)
        let (center, shown) = await makeCenter(notifier, delivery: .both)
        center.checkBursts([AppUsage(app: "/py", bytes: 465_000_000, mobileBytes: 0, domains: [])], threshold: 50_000_000, isMobile: true)
        XCTAssertTrue(notifier.posted.isEmpty)
        XCTAssertTrue(shown().isEmpty)
        center.checkBursts([AppUsage(app: "/py", bytes: 465_000_000, mobileBytes: 60_000_000, domains: [])], threshold: 50_000_000, isMobile: true)
        XCTAssertEqual(notifier.posted.first?.body.hasPrefix("Son 1 dakikada \(Format.bytes(60_000_000))"), true)
    }

    func testBothDeliversTwiceAndBurstKeepsActionAndCategory() async {
        let notifier = FakeNotifier(current: .authorized)
        let (center, shown) = await makeCenter(notifier, delivery: .both)
        var blocked: [String] = []
        center.onBlock = { blocked.append($0) }
        var action: InAppAlertAction?
        center.presentInApp = { _, a in action = a }
        center.checkBursts([AppUsage(app: "com.example.app", bytes: 80_000_000, mobileBytes: 80_000_000, domains: [])], threshold: 50_000_000, isMobile: true)
        XCTAssertEqual(notifier.posted.count, 1)
        XCTAssertEqual(notifier.posted.first?.id, "burst-com.example.app")
        XCTAssertEqual(notifier.posted.first?.category, UNSystemNotifier.burstCategory)
        XCTAssertEqual(notifier.posted.first?.userInfo, ["app": "com.example.app"])
        XCTAssertEqual(action?.title, "Mobilde engelle")
        action?.run()
        XCTAssertEqual(blocked, ["com.example.app"])
        // System notification action goes to the same handler.
        notifier.onBlock?("com.other")
        XCTAssertEqual(blocked, ["com.example.app", "com.other"])
        _ = shown
    }

    func testBatterySystemOnlyRespectsPermission() async {
        let denied = FakeNotifier(current: .denied)
        let (deniedCenter, deniedShown) = await makeCenter(denied, delivery: .inApp)
        deniedCenter.postSystemOnly(title: "Pil %10", body: "x")
        XCTAssertTrue(denied.posted.isEmpty)
        XCTAssertTrue(deniedShown().isEmpty)   // the battery bubble is shown by the battery presenter itself

        let granted = FakeNotifier(current: .authorized)
        let (grantedCenter, _) = await makeCenter(granted, delivery: .inApp)
        grantedCenter.postSystemOnly(title: "Pil %10", body: "x")
        XCTAssertEqual(granted.posted.map(\.title), ["Pil %10"])
    }

    func testInAppBubblesQueueInsteadOfReplacing() {
        let presenter = BatteryAlertPresenter()
        let message = AlertMessage(id: "a", title: "A", body: "a", sound: false)
        presenter.showMessage(message, action: nil)
        for i in 0..<6 { presenter.showMessage(AlertMessage(id: "\(i)", title: "\(i)", body: "", sound: false), action: nil) }
        XCTAssertTrue(presenter.isShowingBubble)
        XCTAssertEqual(presenter.pendingBubbles, BatteryAlertPresenter.maxPending)
        presenter.dismissBubble()
        XCTAssertTrue(presenter.isShowingBubble, "sıradaki balon açıldı")
        XCTAssertEqual(presenter.pendingBubbles, BatteryAlertPresenter.maxPending - 1)
        for _ in 0..<BatteryAlertPresenter.maxPending { presenter.dismissBubble() }
        XCTAssertFalse(presenter.isShowingBubble)
        XCTAssertEqual(presenter.pendingBubbles, 0)
    }
}
