import AVFoundation

/// Tek bir klibin oynatıcısı + katmanı (çapraz geçiş motorunda "mevcut" ve "gelen" örnek).
/// Kırpma: öğenin `forwardPlaybackEndTime`'ı + başlangıca sıfır toleranslı arama.
@MainActor
final class LoopInstance {
    let clip: LoopClip
    let index: Int
    let layer = AVPlayerLayer()
    let player: AVPlayer
    let asset: AVURLAsset
    let item: AVPlayerItem
    var boundaryToken: Any?
    var readyObservation: NSKeyValueObservation?
    var statusObservation: NSKeyValueObservation?
    var endObserver: NSObjectProtocol?

    init(clip: LoopClip, index: Int) {
        self.clip = clip
        self.index = index
        asset = AVURLAsset(url: clip.url)         // varlık erken oluşur; anahtarları arka planda yüklenir
        item = AVPlayerItem(asset: asset)
        if clip.range.isTrimmed { item.forwardPlaybackEndTime = clip.range.endTime }
        player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.volume = 0
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .pause          // aralık bitince son karede durur; döngüyü motor yönetir
        layer.videoGravity = .resizeAspectFill
        layer.player = player
    }

    func seekToStart() {
        let start = clip.range.start
        guard start > 0 else { return }
        player.seek(to: clip.range.startTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Her gözlemciyi, aynı oynatıcıdan kaldırarak bırakır; çözücü oturumu da serbest kalır.
    func teardown() {
        if let boundaryToken { player.removeTimeObserver(boundaryToken) }
        boundaryToken = nil
        readyObservation = nil
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        layer.player = nil
        layer.removeAllAnimations()
        layer.removeFromSuperlayer()
    }
}
