import XCTest
@testable import Adalmon

/// Soğuk başlangıç durum makinesi: siyah kare / takılma olmasın diye sıra (yükle → hazır → ara → preroll → oynat) ve katman görünürlüğü.
final class LoopStartSequenceTests: XCTestCase {
    typealias Event = LoopStartSequence.Event
    typealias Action = LoopStartSequence.Action

    private func run(_ seq: inout LoopStartSequence, _ events: [Event]) -> [Action] {
        events.flatMap { seq.handle($0) }
    }

    func testHappyPathWithTrimSeeksBeforePrerollAndPlaysLast() {
        var seq = LoopStartSequence(needsSeek: true)
        let actions = run(&seq, [.begin, .keysLoaded, .playerReady, .seeked, .prerolled(success: true), .readyForDisplay])
        XCTAssertEqual(actions, [.loadKeys, .awaitPlayer, .seekToStart, .preroll, .play(disableStallWaiting: true), .reveal])
        XCTAssertEqual(seq.phase, .playing)
        XCTAssertTrue(seq.hasStartedPlaying)
    }

    func testNoSeekWhenNotTrimmed() {
        var seq = LoopStartSequence(needsSeek: false)
        let actions = run(&seq, [.begin, .keysLoaded, .playerReady, .prerolled(success: true)])
        XCTAssertEqual(actions, [.loadKeys, .awaitPlayer, .preroll, .play(disableStallWaiting: true)])
        XCTAssertFalse(actions.contains(.seekToStart))
    }

    func testPlayNeverBeforePrerollCompletes() {
        var seq = LoopStartSequence(needsSeek: true)
        _ = run(&seq, [.begin, .keysLoaded, .playerReady, .seeked])
        XCTAssertEqual(seq.phase, .prerolling)
        XCTAssertFalse(seq.hasStartedPlaying)
        // preroll bitmeden gelen başka olaylar oynatmayı başlatmaz
        XCTAssertEqual(seq.handle(.readyForDisplay), [.reveal])
        XCTAssertFalse(seq.hasStartedPlaying)
        XCTAssertEqual(seq.handle(.keysLoaded), [])
    }

    func testFailedPrerollStillPlaysButKeepsStallWaiting() {
        var seq = LoopStartSequence(needsSeek: false)
        let actions = run(&seq, [.begin, .keysLoaded, .playerReady, .prerolled(success: false)])
        XCTAssertEqual(actions.last, .play(disableStallWaiting: false))
    }

    func testLayerStaysHiddenUntilPositioned() {
        var seq = LoopStartSequence(needsSeek: true)
        _ = run(&seq, [.begin, .keysLoaded])
        // ilk kare (kırpma öncesi siyah giriş) hazır görünse bile arama bitmeden katman AÇILMAZ
        XCTAssertEqual(seq.handle(.readyForDisplay), [])
        XCTAssertFalse(seq.isRevealed)
        XCTAssertEqual(seq.handle(.playerReady), [.seekToStart])
        XCTAssertEqual(seq.handle(.seeked), [.preroll, .reveal], "arama bitince, hazır kare zaten varsa hemen belirir")
        XCTAssertTrue(seq.isRevealed)
    }

    func testRevealHappensExactlyOnce() {
        var seq = LoopStartSequence(needsSeek: false)
        let actions = run(&seq, [.begin, .keysLoaded, .playerReady, .readyForDisplay, .readyForDisplay, .prerolled(success: true), .readyForDisplay])
        XCTAssertEqual(actions.filter { $0 == .reveal }.count, 1)
    }

    func testRevealCanPrecedePlayWhenFrameIsReadyEarly() {
        var seq = LoopStartSequence(needsSeek: false)
        let actions = run(&seq, [.begin, .keysLoaded, .readyForDisplay, .playerReady])
        XCTAssertEqual(actions, [.loadKeys, .awaitPlayer, .preroll, .reveal])
    }

    func testPlayerFailureIsTerminalAndNeverPlaysOrReveals() {
        var seq = LoopStartSequence(needsSeek: true)
        var actions = run(&seq, [.begin, .keysLoaded, .playerFailed])
        XCTAssertEqual(seq.phase, .failed)
        actions += run(&seq, [.playerReady, .seeked, .prerolled(success: true), .readyForDisplay])
        XCTAssertEqual(actions, [.loadKeys, .awaitPlayer])
    }

    func testOutOfOrderAndDuplicateEventsAreIgnored() {
        var seq = LoopStartSequence(needsSeek: true)
        XCTAssertEqual(seq.handle(.seeked), [], "begin öncesi")
        XCTAssertEqual(seq.handle(.prerolled(success: true)), [])
        XCTAssertEqual(seq.phase, .idle)
        XCTAssertEqual(seq.handle(.begin), [.loadKeys])
        XCTAssertEqual(seq.handle(.begin), [], "ikinci begin yok sayılır")
        XCTAssertEqual(seq.handle(.playerReady), [], "anahtarlar yüklenmeden hazır olayı geçmez")
    }

    func testFailureAfterPlayingIsIgnored() {
        var seq = LoopStartSequence(needsSeek: false)
        _ = run(&seq, [.begin, .keysLoaded, .playerReady, .prerolled(success: true)])
        _ = seq.handle(.playerFailed)
        XCTAssertEqual(seq.phase, .playing)
    }
}
