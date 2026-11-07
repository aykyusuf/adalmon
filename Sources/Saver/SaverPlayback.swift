import AVFoundation
import AppKit

/// Tek bir ekran koruyucu örneğinin oynatıcısı: AVQueuePlayer (+ tek öğede AVPlayerLooper), sessiz, en-boy doldurma.
/// Her örnekte yalnızca BİR AVPlayer tutulur; `stop()` her şeyi serbest bırakır (VT çözücü oturumu dahil).
@MainActor
final class SaverPlayback {
    let layer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var urls: [URL] = []
    private var nextIndex = 0
    private var queued: Set<ObjectIdentifier> = []
    private var endObserver: NSObjectProtocol?

    var isActive: Bool { player != nil }

    init() {
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = NSColor.clear.cgColor
    }

    func start(urls: [URL]) {
        stop()
        guard !urls.isEmpty else { return }
        self.urls = urls
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.volume = 0
        queue.allowsExternalPlayback = false
        queue.preventsDisplaySleepDuringVideoPlayback = false
        queue.automaticallyWaitsToMinimizeStalling = false
        player = queue
        if urls.count == 1 {
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: urls[0]))   // güçlü referans şart
        } else {
            nextIndex = 0
            enqueueNext(on: queue)
            enqueueNext(on: queue)
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
                let id = (note.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated { self?.itemFinished(id) }
            }
        }
        layer.player = queue
        queue.play()
    }

    func setPaused(_ paused: Bool) {
        guard let player else { return }
        if paused { player.pause() } else { player.play() }
    }

    func stop() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        looper?.disableLooping()
        looper = nil
        player?.pause()
        player?.removeAllItems()
        layer.player = nil
        player = nil
        queued.removeAll()
        urls = []
    }

    private func enqueueNext(on queue: AVQueuePlayer) {
        guard !urls.isEmpty else { return }
        let item = AVPlayerItem(url: urls[nextIndex % urls.count])
        nextIndex += 1
        queued.insert(ObjectIdentifier(item))
        queue.insert(item, after: nil)
    }

    private func itemFinished(_ id: ObjectIdentifier?) {
        guard let id, queued.remove(id) != nil, let player else { return }
        enqueueNext(on: player)
    }
}
