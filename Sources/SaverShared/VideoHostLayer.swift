import AVFoundation
import QuartzCore

/// Üst üste dizilen `AVPlayerLayer`'ların kabı: alt katmanlar her zaman kabın sınırını doldurur.
final class VideoHostLayer: CALayer {
    /// Oturma biçimi; değişince mevcut video katmanlarına hemen uygulanır (yeniden kurma gerekmez).
    var fit: LoopFit = .fill {
        didSet {
            guard fit != oldValue else { return }
            for case let player as AVPlayerLayer in sublayers ?? [] { player.videoGravity = fit.videoGravity }
        }
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in sublayers ?? [] { layer.frame = bounds }
        CATransaction.commit()
    }
}
