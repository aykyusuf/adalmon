import AppKit
import AVFoundation

/// Masaüstü seviyesinde, tıklamayı geçiren, kenarlıksız pencere. Seviye TAM `.desktopWindow`
/// (+1 değil: macOS 27'de -622, "Fullscreen Backdrop" ile çakışır; levels-probe ile doğrulandı).
final class WallpaperWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hasShadow = false
        isOpaque = true
        backgroundColor = .black
        isReleasedWhenClosed = false
        canHide = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        setFrame(frame, display: false)
    }
}

/// Düz NSView + katmanlar (NSHostingView içine AVPlayerLayer eklemek macOS 26+'da desteklenmiyor).
final class WallpaperContentView: NSView {
    let stillLayer = CALayer()
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        stillLayer.contentsGravity = .resizeAspectFill
        stillLayer.masksToBounds = true
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(stillLayer)
        layer?.addSublayer(playerLayer)
        playerLayer.isHidden = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stillLayer.frame = bounds
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func setStill(_ image: CGImage?, scale: CGFloat) {
        stillLayer.contents = image
        stillLayer.contentsScale = scale
    }
}
