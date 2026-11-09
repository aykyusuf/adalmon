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

    // Fare: tıklama (oda seç), sürükleme ve tekerlek (kaydırma), Esc (seçimi kaldır). Olaylar doğrudan sahneye gider.
    private var officeScene: OfficeScene? { scene as? OfficeScene }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        officeScene?.pointerDown(at: convert(event.locationInWindow, from: nil), clickCount: event.clickCount)
    }

    // Üzerine gelme: ipucu + el imleci.
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) { officeScene?.hover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { officeScene?.hover(at: nil) }

    override func mouseDragged(with event: NSEvent) { officeScene?.pointerDragged(to: convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) { officeScene?.pointerUp(at: convert(event.locationInWindow, from: nil)) }

    override func scrollWheel(with event: NSEvent) {
        // Fare tekerleği (kesikli) satır birimindedir: piksele çevir.
        let k: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        officeScene?.scroll(deltaX: event.scrollingDeltaX * k, deltaY: event.scrollingDeltaY * k)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, let officeScene { officeScene.escape() } else { super.keyDown(with: event) }
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
    /// Odaklanılan oda (tıklama/Esc sahneden, "Hepsini göster" sayfadan değiştirir).
    @Binding var selectedRoom: String?
    var lightingMode: OfficeLightingMode = .auto
    var theme: OfficeTheme = .default
    var panoActive = false
    @Binding var card: OfficeDetailCard?

    @MainActor
    final class Coordinator {
        var scene: OfficeScene?
        var lastMembers: [OfficeMember]?
        var wanderTimer: Timer?
        var pauseTask: Task<Void, Never>?
        weak var view: OfficeHostView?
        var setSelection: (String?) -> Void = { _ in }
        /// Sahne ile bağlama son eşitlenen odak (sahnenin eşzamansız bildirimi güncellemeyle yarışmasın).
        var knownSelection: String?
        var knownLighting: OfficeLightingMode?
        var knownTheme: OfficeTheme?
        var knownPano: Bool?
        /// Bağlamaya son yazılan kart (kapat düğmesi bağlamayı nil yapınca sahneyi de kapatmak için).
        var pushedCard: OfficeDetailCard?

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

        /// Kamera animasyonu süresince 60 kare/sn (akıcı yakınlaşma), sonra pil için 12'ye döner.
        private var boostTask: Task<Void, Never>?
        static let idleFramesPerSecond = 12
        static let boostedFramesPerSecond = 60

        func boostFrameRate(for duration: TimeInterval) {
            view?.preferredFramesPerSecond = Self.boostedFramesPerSecond
            boostTask?.cancel()
            boostTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration + 0.2))
                guard !Task.isCancelled else { return }
                self?.view?.preferredFramesPerSecond = Self.idleFramesPerSecond
            }
        }

        func tearDown() {
            boostTask?.cancel()
            pauseTask?.cancel()
            wanderTimer?.invalidate()
            wanderTimer = nil
            view?.isPaused = true
            view?.presentScene(nil)
            scene?.onAnimationStateChange = nil
            scene?.onActivity = nil
            scene?.onCameraAnimation = nil
            scene?.onSelectionChange = nil
            scene?.onCardChange = nil
            scene?.onHoverChange = nil
            scene?.shutdown()
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
        let scene = OfficeScene(assets: assets, size: view.bounds.size, theme: theme)
        context.coordinator.knownTheme = theme
        let coordinator = context.coordinator
        let selection = $selectedRoom
        scene.onAnimationStateChange = { [weak coordinator] _ in coordinator?.refreshRunState() }
        scene.onActivity = { [weak coordinator] in coordinator?.refreshRunState() }
        scene.onCameraAnimation = { [weak coordinator] d in coordinator?.boostFrameRate(for: d) }
        scene.onSelectionChange = { [weak coordinator] id in coordinator?.knownSelection = id; coordinator?.setSelection(id) }
        coordinator.setSelection = { id in DispatchQueue.main.async { selection.wrappedValue = id } }
        let cardBinding = $card
        scene.onCardChange = { [weak coordinator] card in
            DispatchQueue.main.async { coordinator?.pushedCard = card; cardBinding.wrappedValue = card }
        }
        scene.onHoverChange = { hand in (hand ? NSCursor.pointingHand : NSCursor.arrow).set() }
        scene.setLightingMode(lightingMode, animated: false)
        coordinator.knownLighting = lightingMode
        scene.setBackdropStyle(.themed)
        scene.panoMode = panoActive
        coordinator.knownPano = panoActive
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
        guard let scene = c.scene else { return }
        let selection = $selectedRoom
        c.setSelection = { id in DispatchQueue.main.async { selection.wrappedValue = id } }
        if c.knownTheme != theme {
            c.knownTheme = theme
            scene.setTheme(theme)
            c.refreshRunState()
        }
        if c.knownPano != panoActive {
            c.knownPano = panoActive
            scene.panoMode = panoActive
            c.refreshRunState()
        }
        if c.knownLighting != lightingMode {
            c.knownLighting = lightingMode
            scene.setLightingMode(lightingMode, animated: view.isReallyVisible)
            c.refreshRunState()
        }
        if card == nil, c.pushedCard != nil { c.pushedCard = nil; scene.setSelectedMember(nil) }
        if c.knownSelection != selectedRoom {
            c.knownSelection = selectedRoom
            scene.select(selectedRoom, animated: view.isReallyVisible)
            c.refreshRunState()
        }
        guard c.lastMembers != members else { return }
        c.lastMembers = members
        scene.apply(members: members, animated: view.isReallyVisible)
        c.refreshRunState()
    }

    static func dismantleNSView(_ view: OfficeHostView, coordinator: Coordinator) {
        view.onVisibilityChange = nil
        MainActor.assumeIsolated { coordinator.tearDown() }
    }
}
