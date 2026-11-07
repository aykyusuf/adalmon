import AVFoundation

/// Tek öğe + geçiş kapalı: tek `AVQueuePlayer` ve kırpılmış aralıkta kesintisiz `AVPlayerLooper`.
@MainActor
final class LoopingQueueBackend: LoopBackend {
    private let layer = AVPlayerLayer()
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?       // güçlü referans şart
    private var readyObservation: NSKeyValueObservation?
    private var starter: LoopStartDriver?

    init(host: VideoHostLayer, clip: LoopClip, onFirstFrame: @escaping @MainActor () -> Void) {
        player.isMuted = true
        player.volume = 0
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        let asset = AVURLAsset(url: clip.url)
        let template = AVPlayerItem(asset: asset)
        looper = AVPlayerLooper(player: player, templateItem: template, timeRange: clip.range.isTrimmed ? clip.range.timeRange : .invalid)
        layer.videoGravity = .resizeAspectFill
        layer.frame = host.bounds
        layer.opacity = 0                       // poster / sabit görüntü görünür kalır; ilk kare hazır olunca belirir
        layer.player = player
        host.addSublayer(layer)
        let driver = LoopStartDriver(player: player, asset: asset, start: clip.range.isTrimmed ? clip.range.startTime : nil) { [layer] in
            layer.fadeIn()
            onFirstFrame()
        }
        starter = driver
        readyObservation = layer.observe(\.isReadyForDisplay, options: [.new]) { layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor [weak driver] in driver?.layerReady() }
        }
        driver.begin()
    }

    func setPaused(_ paused: Bool) {
        starter?.paused = paused
        if paused { player.pause() } else if starter?.hasStartedPlaying ?? true { player.play() }
    }

    func reattach() {
        layer.player = nil
        layer.player = player
    }

    func transition(to clip: LoopClip) -> Bool { false }

    func stop() {
        starter?.cancel()
        starter = nil
        readyObservation = nil
        looper?.disableLooping()
        looper = nil
        player.pause()
        player.removeAllItems()
        layer.player = nil
        layer.removeFromSuperlayer()
    }
}
