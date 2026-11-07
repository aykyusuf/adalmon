import AVFoundation
import AppKit
import XCTest
@testable import Adalmon

/// Gerçek AVFoundation ile küçük duman testleri (birkaç KB'lık sentetik klip, bitince silinir).
@MainActor
final class LoopingVideoEngineTests: XCTestCase {
    private var dir: URL!
    private var window: NSWindow!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "loop-engine-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView?.wantsLayer = true
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
        window = nil
    }

    private func layers(_ engine: LoopingVideoEngine) -> [AVPlayerLayer] { (engine.hostLayer.sublayers ?? []).compactMap { $0 as? AVPlayerLayer } }

    private func wait(_ timeout: Double = 6, _ cond: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !cond(), Date() < end { try? await Task.sleep(for: .milliseconds(40)) }
    }

    private func makeEngine() -> LoopingVideoEngine {
        let engine = LoopingVideoEngine(reduceMotion: { false })
        engine.hostLayer.frame = window.contentView!.bounds
        window.contentView!.layer!.addSublayer(engine.hostLayer)
        return engine
    }

    /// Tek video + geçiş kapalı: AVPlayerLooper kırpma başlangıcından oynar; video katmanı önce şeffaf, sonra belirir.
    func testLooperStartsAtTrimStartAfterPrerollAndRevealsLayer() async throws {
        let url = dir.appending(path: "a.mov")
        try await TinyMedia.video(at: url, width: 64, height: 36, fps: 10, frames: 200, hue: 0.2)      // 20 sn
        let engine = makeEngine()
        var revealed = false
        engine.onFirstFrame = { revealed = true }
        engine.start(sources: [LoopSource(url: url, duration: 20)], timing: LoopTiming(trimStart: 5, trimEnd: 3, crossfade: 0))
        let layer = try XCTUnwrap(layers(engine).first)
        XCTAssertEqual(layer.opacity, 0, "başlangıçta şeffaf: poster görünür kalır")
        await wait { revealed }
        XCTAssertTrue(revealed)
        XCTAssertEqual(layer.opacity, 1)
        await wait { (layer.player?.rate ?? 0) > 0 }
        let t = try XCTUnwrap(layer.player?.currentTime().seconds)
        XCTAssertGreaterThanOrEqual(t, 4.9, "kırpma başlangıcından (5 sn) oynamalı")
        XCTAssertLessThan(t, 15)
        engine.stop()
        XCTAssertTrue(layers(engine).isEmpty)
        XCTAssertFalse(engine.isActive)
    }

    /// Çapraz geçiş: sonda ikinci katman hazırlanır, geçiş biter, tek katman kalır ve yeni örnek baştan oynar.
    func testCrossfadeCreatesSecondLayerThenReleasesOldOne() async throws {
        let url = dir.appending(path: "b.mov")
        try await TinyMedia.video(at: url, width: 64, height: 36, fps: 10, frames: 50, hue: 0.6)       // 5 sn
        let engine = makeEngine()
        engine.start(sources: [LoopSource(url: url, duration: 5)], timing: LoopTiming(trimStart: 0, trimEnd: 0, crossfade: 1))
        await wait { (self.layers(engine).first?.player?.rate ?? 0) > 0 }
        var sawTwo = false
        await wait(9) {
            if layers(engine).count == 2 { sawTwo = true }
            return sawTwo
        }
        XCTAssertTrue(sawTwo, "geçiş sırasında iki katman olmalı")
        await wait(4) { layers(engine).count == 1 && (layers(engine).first?.opacity ?? 0) == 1 }
        XCTAssertEqual(layers(engine).count, 1, "geçiş bitince eski oynatıcı bırakılmalı")
        engine.stop()
        XCTAssertTrue(layers(engine).isEmpty)
    }

    /// Geçişin ortasında duraklatma geçişi anında bitirir; duraklatılmışken ikinci oynatıcı kalmaz.
    func testPausingMidFadeCompletesTransitionInstantly() async throws {
        let url = dir.appending(path: "c.mov")
        try await TinyMedia.video(at: url, width: 64, height: 36, fps: 10, frames: 50, hue: 0.4)
        let engine = makeEngine()
        engine.start(sources: [LoopSource(url: url, duration: 5)], timing: LoopTiming(trimStart: 0, trimEnd: 0, crossfade: 1.2))
        await wait(9) { layers(engine).count == 2 && layers(engine).contains { $0.opacity == 1 } && layers(engine).contains { $0.animation(forKey: "crossfade") != nil } }
        guard layers(engine).count == 2 else { return XCTFail("geçiş yakalanamadı") }
        engine.setPaused(true)
        XCTAssertEqual(layers(engine).count, 1)
        XCTAssertEqual(layers(engine).first?.opacity, 1)
        XCTAssertEqual(layers(engine).first?.player?.rate, 0)
        engine.stop()
    }
}
