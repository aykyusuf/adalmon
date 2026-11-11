import AVFoundation
import AppKit

/// Tek bir ekran koruyucu örneğinin oynatıcısı: ortak `LoopingVideoEngine` (kırpma + çapraz geçiş), sessiz, en-boy doldurma.
/// Normalde yalnızca BİR AVPlayer çalışır (geçiş sırasında kısa süre iki); `stop()` hepsini serbest bırakır (VT çözücü oturumu dahil).
@MainActor
final class SaverPlayback {
    private let engine = LoopingVideoEngine()

    var layer: CALayer { engine.hostLayer }
    var isActive: Bool { engine.isActive }
    /// İlk video karesi görünür olunca (yalnızca ölçüm / iz için).
    var onFirstFrame: (@MainActor () -> Void)? {
        get { engine.onFirstFrame }
        set { engine.onFirstFrame = newValue }
    }

    init() {
        engine.hostLayer.backgroundColor = NSColor.clear.cgColor
    }

    var fit: LoopFit {
        get { engine.fit }
        set { engine.fit = newValue }
    }

    func start(sources: [LoopSource], timing: LoopTiming) {
        engine.start(sources: sources, timing: timing)
    }

    func setPaused(_ paused: Bool) {
        engine.setPaused(paused)
    }

    func stop() {
        engine.stop()
    }
}
