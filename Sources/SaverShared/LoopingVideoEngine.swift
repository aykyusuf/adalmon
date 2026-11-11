import AVFoundation
import AppKit

/// Duvar kâğıdı ve ekran koruyucunun ortak döngü motoru. Katmanı `hostLayer`'dır; içeriği iki stratejiden biri yönetir:
/// - tek video + geçiş kapalı → `LoopingQueueBackend` (kırpılmış aralıkta `AVPlayerLooper`);
/// - diğer her durum → `CrossfadeBackend` (JIT ikinci oynatıcı, çapraz geçiş ya da önceden hazırlanmış sert geçiş).
/// Duraklatılmışken hiçbir iş yapılmaz; bırakıldığında (`stop`) tüm oynatıcılar serbest kalır.
@MainActor
final class LoopingVideoEngine {
    let hostLayer = VideoHostLayer()
    /// İlk kare görüntülenince bir kez çağrılır (duvar kâğıdı: poster → video geçişi).
    var onFirstFrame: (@MainActor () -> Void)?

    private let reduceMotion: @MainActor () -> Bool
    private var backend: (any LoopBackend)?
    private var timing = LoopTiming.default
    private var paused = false
    private var generation = 0
    private var resolving: Task<Void, Never>?

    /// Oynatıcı var (ya da süre okunurken kuruluyor).
    /// Doldur / Sığdır; çalışan katmanlara hemen uygulanır.
    var fit: LoopFit {
        get { hostLayer.fit }
        set { hostLayer.fit = newValue }
    }

    var isActive: Bool { backend != nil || resolving != nil }

    init(reduceMotion: @escaping @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.reduceMotion = reduceMotion
    }

    /// Oynatmayı başlatır. Tüm süreler biliniyorsa oynatıcı eşzamanlı kurulur; bilinmeyenler dosyadan okunur.
    func start(sources: [LoopSource], timing newTiming: LoopTiming) {
        stop()
        guard !sources.isEmpty else { return }
        timing = newTiming.sanitized
        paused = false
        let known = sources.allSatisfy { ($0.duration ?? 0) > 0 }
        if known {
            launch(sources)
        } else {
            let gen = generation
            resolving = Task { [weak self] in
                var resolved: [LoopSource] = []
                for source in sources {
                    var copy = source
                    if (copy.duration ?? 0) <= 0 { copy.duration = await Self.readDuration(of: source.url) }
                    resolved.append(copy)
                }
                guard !Task.isCancelled, let self, self.generation == gen else { return }
                self.resolving = nil
                self.launch(resolved)
            }
        }
    }

    func setPaused(_ newValue: Bool) {
        paused = newValue
        backend?.setPaused(newValue)
    }

    func reattach() { backend?.reattach() }

    /// Çalışan döngüyü `source`'a çapraz geçişle geçirir (duvar kâğıdı çalma listesi). `false`: yapılamadı
    /// (durmuş, süre bilinmiyor, tek video+geçiş kapalı); çağıran eski yolu (durdur + yeniden başlat) izler.
    func transition(to source: LoopSource) -> Bool {
        guard let backend, !paused, let duration = source.duration, duration > 0 else { return false }
        return backend.transition(to: LoopClip(url: source.url, range: timing.range(duration: duration)))
    }

    func stop() {
        generation += 1
        resolving?.cancel()
        resolving = nil
        backend?.stop()
        backend = nil
    }

    private func launch(_ sources: [LoopSource]) {
        let clips = sources.map { LoopClip(url: $0.url, range: timing.range(duration: $0.duration)) }
        let announce: @MainActor () -> Void = { [weak self] in self?.onFirstFrame?() }
        if timing.usesLooper(clipCount: clips.count) {
            let looper = LoopingQueueBackend(host: hostLayer, clip: clips[0], onFirstFrame: announce)
            backend = looper
            if paused { looper.setPaused(true) }
        } else {
            let crossfade = CrossfadeBackend(host: hostLayer, timing: timing, clips: clips, paused: paused, reduceMotion: reduceMotion, onFirstFrame: announce)
            backend = crossfade
            crossfade.start()
        }
    }

    private nonisolated static func readDuration(of url: URL) async -> Double? {
        guard let seconds = try? await AVURLAsset(url: url).load(.duration).seconds, seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }
}
