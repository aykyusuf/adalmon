import AppKit
import Foundation

/// Süreç genelinde tek örnek: ekran koruyucu örneklerinin kaydı, `willstop` dinleyicisi ve `exit(0)` çaresi.
///
/// Bilinen macOS 26/27 hataları (bkz. docs): `stopAnimation` çağrılmayabilir, her başlatmada yeni `ScreenSaverView` oluşur ve
/// eskisi yok olmaz, legacyScreenSaver süreci hiç sonlanmaz. Çareler: (1) yeni örnek eskisini ezer, (2) `com.apple.screensaver.willstop`
/// ve `didstop` dağıtık bildirimlerinde hepsi kapatılır, (3) kısa gecikmeyle `exit(0)` (yalnızca tam çalıştırma sonrası, önizleme yokken).
@MainActor
final class SaverHost {
    static let shared = SaverHost()
    static let exitDelay: Duration = .seconds(2)

    private struct Weak { weak var view: AdalmonSaverView? }

    private var registry = SaverLifecycleRegistry()
    private var views: [Int: Weak] = [:]
    private var observers: [NSObjectProtocol] = []
    private var exitTask: Task<Void, Never>?
    private var hostExitEnabled = true

    private init() {}

    /// Dinleyicileri bir kez kurar (ilk örnekte).
    private func installObserversIfNeeded() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.screensaver.willstop", "com.apple.screensaver.didstop"] {
            observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hostWillStop() }
            })
        }
    }

    func register(_ view: AdalmonSaverView, screenKey: String, isPreview: Bool, hostExitOnStop: Bool) {
        installObserversIfNeeded()
        exitTask?.cancel()
        exitTask = nil
        hostExitEnabled = hostExitOnStop
        let token = view.token
        let evicted = registry.register(token: token, screenKey: screenKey, isPreview: isPreview)
        views[token] = Weak(view: view)
        for t in evicted {
            views[t]?.view?.evict()
            views[t] = nil
        }
        sweepOrphans(except: token)
    }

    func reclassify(_ view: AdalmonSaverView, isPreview: Bool) {
        registry.reclassify(token: view.token, isPreview: isPreview)
    }

    func unregister(_ view: AdalmonSaverView) {
        registry.remove(token: view.token)
        views[view.token] = nil
    }

    /// Penceresi olmayan ya da yok olmuş eski örnekler (yığılan örnekler) durdurulur.
    private func sweepOrphans(except token: Int) {
        for (t, box) in views where t != token {
            guard let view = box.view else { registry.remove(token: t); views[t] = nil; continue }
            if view.window == nil { view.evict(); registry.remove(token: t); views[t] = nil }
        }
    }

    private func hostWillStop() {
        for t in registry.hostWillStop() { views[t]?.view?.evict() }
        scheduleExitIfAllowed()
    }

    private func scheduleExitIfAllowed() {
        exitTask?.cancel()
        guard registry.canExitHost(enabled: hostExitEnabled) else { return }
        exitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.exitDelay)
            guard !Task.isCancelled, let self, self.registry.canExitHost(enabled: self.hostExitEnabled) else { return }
            exit(0)
        }
    }
}
