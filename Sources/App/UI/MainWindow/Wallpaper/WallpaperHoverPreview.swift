import AppKit
import AVFoundation
import SwiftUI

/// Üzerine gelince oynayan sessiz önizleme. Oynatıcı yalnızca görünüm ekrandayken vardır (gezinme bitince serbest bırakılır).
struct WallpaperHoverPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PreviewView { PreviewView(url: url) }
    func updateNSView(_ nsView: PreviewView, context: Context) {}
    static func dismantleNSView(_ nsView: PreviewView, coordinator: ()) { nsView.stop() }

    final class PreviewView: NSView {
        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private let playerLayer = AVPlayerLayer()

        init(url: URL) {
            super.init(frame: .zero)
            wantsLayer = true
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(playerLayer)
            player.play()
        }

        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }

        func stop() {
            looper?.disableLooping()
            player.pause()
            player.removeAllItems()
            playerLayer.player = nil
        }
    }
}
