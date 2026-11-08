import AppKit
import SpriteKit
import SwiftUI

/// `OfficeScene`'i barındıran SKView. Pencere görünürlüğü (örtülü/küçültülmüş/başka sayfa) değişince ev sahibine haber verir.
final class OfficeHostView: SKView {
    var onVisibilityChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let window {
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onVisibilityChange?() }
                })
            }
        }
        onVisibilityChange?()
    }

    override func viewDidHide() { super.viewDidHide(); onVisibilityChange?() }
    override func viewDidUnhide() { super.viewDidUnhide(); onVisibilityChange?() }

    isolated deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    var isReallyVisible: Bool {
        guard let window else { return false }
        return window.occlusionState.contains(.visible) && !window.isMiniaturized && !isHiddenOrHasHiddenAncestor
    }
}

/// SwiftUI köprüsü: üyeler değişince yalnızca sahneye uygulanır. Duraklatma kuralı: pencere görünür VE sahnede animasyon var.
struct OfficeSceneView: NSViewRepresentable {
    let members: [OfficeMember]

    @MainActor
    final class Coordinator {
        var scene: OfficeScene?
        var lastMembers: [OfficeMember]?
        var wanderTimer: Timer?
        var pauseTask: Task<Void, Never>?
        weak var view: OfficeHostView?

        /// SKView'i ayarlar: 12 fps; sahne durağansa (ya da pencere görünmüyorsa) duraklatılır.
        func refreshRunState() {
            guard let view, let scene else { return }
            pauseTask?.cancel()
            let visible = view.isReallyVisible
            if visible && scene.isAnimating {
                view.isPaused = false
            } else if visible {
                // Son kare çizilsin, sonra durakla.
                view.isPaused = false
                pauseTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled, let self, let view = self.view, let scene = self.scene else { return }
                    view.isPaused = !view.isReallyVisible || !scene.isAnimating
                }
            } else {
                view.isPaused = true
            }
            updateWanderTimer(active: visible && (scene.actorCount > 0))
        }

        private func updateWanderTimer(active: Bool) {
            if active, wanderTimer == nil {
                let timer = Timer(timeInterval: 12, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let scene = self.scene, self.view?.isReallyVisible == true else { return }
                        if scene.wanderTick() { self.refreshRunState() }
                    }
                }
                timer.tolerance = 6
                RunLoop.main.add(timer, forMode: .common)
                wanderTimer = timer
            } else if !active {
                wanderTimer?.invalidate()
                wanderTimer = nil
            }
        }

        func tearDown() {
            pauseTask?.cancel()
            wanderTimer?.invalidate()
            wanderTimer = nil
            view?.isPaused = true
            view?.presentScene(nil)
            scene?.onAnimationStateChange = nil
            scene = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> OfficeHostView {
        let view = OfficeHostView(frame: NSRect(x: 0, y: 0, width: 960, height: 600))
        view.preferredFramesPerSecond = 12
        view.ignoresSiblingOrder = true
        view.allowsTransparency = false
        context.coordinator.view = view
        guard let assets = OfficeAssets.shared else { return view }
        let scene = OfficeScene(assets: assets, size: view.bounds.size)
        let coordinator = context.coordinator
        scene.onAnimationStateChange = { [weak coordinator] _ in coordinator?.refreshRunState() }
        coordinator.scene = scene
        view.onVisibilityChange = { [weak coordinator] in coordinator?.refreshRunState() }
        view.presentScene(scene)
        scene.apply(members: members, animated: false)
        coordinator.lastMembers = members
        coordinator.refreshRunState()
        return view
    }

    func updateNSView(_ view: OfficeHostView, context: Context) {
        let c = context.coordinator
        guard let scene = c.scene, c.lastMembers != members else { return }
        c.lastMembers = members
        scene.apply(members: members, animated: view.isReallyVisible)
        c.refreshRunState()
    }

    static func dismantleNSView(_ view: OfficeHostView, coordinator: Coordinator) {
        view.onVisibilityChange = nil
        MainActor.assumeIsolated { coordinator.tearDown() }
    }
}
