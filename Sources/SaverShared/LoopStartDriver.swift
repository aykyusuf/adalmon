import AVFoundation

/// `LoopStartSequence`'i gerçek AVPlayer üzerinde yürütür: anahtarları arka planda yükler, oynatıcı hazır olunca arar,
/// preroll yapar ve ancak sonra oynatır. Video katmanının görünmesi (`reveal`) çağırana bırakılır.
@MainActor
final class LoopStartDriver {
    private var sequence: LoopStartSequence
    private let player: AVPlayer
    private let asset: AVAsset
    private let startTime: CMTime
    private let onReveal: @MainActor () -> Void
    private var statusObservation: NSKeyValueObservation?
    private var cancelled = false
    /// Başlangıç dizisi bitmeden kullanıcı duraklattıysa `play` atlanır.
    var paused = false

    var hasStartedPlaying: Bool { sequence.hasStartedPlaying }

    init(player: AVPlayer, asset: AVAsset, start: CMTime?, onReveal: @escaping @MainActor () -> Void) {
        self.player = player
        self.asset = asset
        self.startTime = start ?? .zero
        self.sequence = LoopStartSequence(needsSeek: (start?.seconds ?? 0) > 0)
        self.onReveal = onReveal
    }

    func begin() { send(.begin) }

    /// `AVPlayerLayer.isReadyForDisplay` true olduğunda çağrılır.
    func layerReady() { send(.readyForDisplay) }

    func cancel() {
        cancelled = true
        statusObservation = nil
        player.cancelPendingPrerolls()
    }

    private func send(_ event: LoopStartSequence.Event) {
        guard !cancelled else { return }
        for action in sequence.handle(event) { perform(action) }
    }

    private func perform(_ action: LoopStartSequence.Action) {
        switch action {
        case .loadKeys:
            let asset = asset
            Task { [weak self] in
                _ = try? await asset.load(.duration, .tracks)        // ağır iş ana iş parçacığında değil
                self?.send(.keysLoaded)
            }
        case .awaitPlayer:
            statusObservation = player.observe(\.status, options: [.initial, .new]) { [weak self] player, _ in
                let status = player.status
                guard status != .unknown else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.statusObservation != nil else { return }
                    self.statusObservation = nil
                    self.send(status == .readyToPlay ? .playerReady : .playerFailed)
                }
            }
        case .seekToStart:
            player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor [weak self] in self?.send(.seeked) }
            }
        case .preroll:
            player.preroll(atRate: 1) { [weak self] finished in
                Task { @MainActor [weak self] in self?.send(.prerolled(success: finished)) }
            }
        case .play(let disableStallWaiting):
            if disableStallWaiting { player.automaticallyWaitsToMinimizeStalling = false }
            if !paused { player.play() }
        case .reveal:
            onReveal()
        }
    }
}

extension CALayer {
    /// Katmanı ~0,4 sn'de saydamdan görünüre getirir (poster / sabit görüntü üstünde).
    func fadeIn(duration: CFTimeInterval = LoopStartSequence.revealDuration) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        opacity = 1
        CATransaction.commit()
        guard duration > 0 else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        add(animation, forKey: "reveal")
    }
}
