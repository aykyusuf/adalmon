import QuartzCore

/// Üst üste dizilen `AVPlayerLayer`'ların kabı: alt katmanlar her zaman kabın sınırını doldurur.
final class VideoHostLayer: CALayer {
    override func layoutSublayers() {
        super.layoutSublayers()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in sublayers ?? [] { layer.frame = bounds }
        CATransaction.commit()
    }
}
