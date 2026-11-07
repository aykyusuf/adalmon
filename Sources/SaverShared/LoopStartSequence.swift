import Foundation

/// Soğuk başlangıç sırası (SAF durum makinesi; AVFoundation'a dokunmaz). Amaç: siyah kare ve ilk kare takılması olmasın.
///
///   begin → anahtarlar yüklenir (`duration`, `tracks`; ana iş parçacığı dışında) → oynatıcı hazır
///         → (kırpma varsa) başlangıca sıfır toleranslı arama → `preroll(atRate: 1)` → ancak sonra `play`.
/// Video katmanı poster/sabit görüntünün ÜSTÜNDE şeffaf (opaklık 0) bekler; ilk kare hazır olunca (`isReadyForDisplay`)
/// ve oynatma konumu doğruysa (arama bitti) yumuşakça belirir. Kırpma girişindeki siyah kare asla gösterilmez.
struct LoopStartSequence: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle, loadingKeys, waitingForPlayer, seeking, prerolling, playing, failed
    }

    enum Event: Equatable, Sendable {
        case begin
        case keysLoaded
        case playerReady
        case playerFailed
        case seeked
        case prerolled(success: Bool)
        case readyForDisplay
    }

    enum Action: Equatable, Sendable {
        case loadKeys
        case awaitPlayer
        case seekToStart
        case preroll
        /// `automaticallyWaitsToMinimizeStalling` yalnızca preroll BAŞARILI olduktan sonra kapatılır.
        case play(disableStallWaiting: Bool)
        case reveal
    }

    /// Süre (sn) kaydıran poster/katman geçişi.
    static let revealDuration = 0.4

    private(set) var phase: Phase = .idle
    private(set) var isReadyForDisplay = false
    private(set) var isPositioned = false
    private(set) var isRevealed = false
    let needsSeek: Bool

    init(needsSeek: Bool) { self.needsSeek = needsSeek }

    var hasStartedPlaying: Bool { phase == .playing }

    mutating func handle(_ event: Event) -> [Action] {
        var actions: [Action] = []
        switch (phase, event) {
        case (.idle, .begin):
            phase = .loadingKeys
            actions.append(.loadKeys)
        case (.loadingKeys, .keysLoaded):
            // Anahtar yükleme hatası da buradan geçer: oynatıcı kendi durumuyla hatayı bildirir.
            phase = .waitingForPlayer
            actions.append(.awaitPlayer)
        case (.waitingForPlayer, .playerReady):
            if needsSeek {
                phase = .seeking
                actions.append(.seekToStart)
            } else {
                isPositioned = true
                phase = .prerolling
                actions.append(.preroll)
            }
        case (.seeking, .seeked):
            isPositioned = true
            phase = .prerolling
            actions.append(.preroll)
        case (.prerolling, .prerolled(let success)):
            phase = .playing
            actions.append(.play(disableStallWaiting: success))
        case (.failed, _), (.playing, .playerFailed):
            break
        case (_, .playerFailed):
            phase = .failed
        case (_, .readyForDisplay):
            isReadyForDisplay = true
        default:
            break
        }
        if isReadyForDisplay, isPositioned, !isRevealed, phase != .failed {
            isRevealed = true
            actions.append(.reveal)
        }
        return actions
    }
}
