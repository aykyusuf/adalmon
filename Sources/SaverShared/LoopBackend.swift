import Foundation

/// `LoopingVideoEngine`'in iki oynatma stratejisinin ortak yüzü.
@MainActor
protocol LoopBackend: AnyObject {
    func setPaused(_ paused: Bool)
    /// Uyku / kilit sonrası katmanı oynatıcıya yeniden bağlar (siyah kare önlemi).
    func reattach()
    /// Çalışan döngüyü hemen `clip`'e geçirir (çapraz geçişle). Desteklenmiyorsa `false`.
    func transition(to clip: LoopClip) -> Bool
    func stop()
}
