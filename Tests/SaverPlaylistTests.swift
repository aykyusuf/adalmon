import XCTest
@testable import Adalmon

/// Oynatma listesi JSON'u: gidiş-dönüş, şema sürümü, güvenli dosya adı, sıralama.
final class SaverPlaylistTests: XCTestCase {
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private func item(_ n: Int) -> SaverPlaylistItem {
        SaverPlaylistItem(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(n)")!, name: "Video \(n)", file: "v\(n).mov", poster: "v\(n).jpg",
                          width: 3840, height: 2160, duration: 12.5)
    }

    func testRoundTrip() throws {
        let list = SaverPlaylist(appVersion: "0.1.0", updatedAt: Date(timeIntervalSince1970: 1_800_000_000), shuffle: true, hostExitOnStop: false, items: [item(1), item(2)])
        let data = try list.encoded()
        let back = try SaverPlaylist.decode(data)
        XCTAssertEqual(back, list)
        XCTAssertEqual(back.schema, SaverPlaylist.currentSchema)
        XCTAssertFalse(back.hostExitOnStop)
    }

    func testDecodeToleratesUnknownKeysAndMissingOptionalFields() throws {
        let json = #"{"schema":1,"appVersion":"x","updatedAt":"2026-11-07T10:00:00Z","shuffle":false,"hostExitOnStop":true,"future":42,"items":[{"id":"00000000-0000-0000-0000-000000000001","name":"a","file":"a.mov","width":1920,"height":1080,"duration":3}]}"#
        let list = try SaverPlaylist.decode(Data(json.utf8))
        XCTAssertEqual(list.items.count, 1)
        XCTAssertNil(list.items[0].poster)
    }

    func testNewerSchemaIsRejected() {
        let json = #"{"schema":99,"appVersion":"x","updatedAt":"2026-11-07T10:00:00Z","shuffle":false,"hostExitOnStop":true,"items":[]}"#
        XCTAssertThrowsError(try SaverPlaylist.decode(Data(json.utf8))) { XCTAssertEqual($0 as? SaverPlaylist.PlaylistError, .unsupportedSchema(99)) }
    }

    func testResolveRejectsEscapingNames() {
        let dir = URL(filePath: "/tmp/x", directoryHint: .isDirectory)
        XCTAssertNotNil(SaverPlaylist.resolve("a.mov", in: dir))
        for bad in ["", ".", "..", "../etc/passwd", "sub/a.mov", "/etc/passwd", "a\0b"] {
            XCTAssertNil(SaverPlaylist.resolve(bad, in: dir), bad)
        }
    }

    func testPlayableFiltersMissingFilesAndPosters() {
        let list = SaverPlaylist(appVersion: "", updatedAt: .now, shuffle: false, items: [item(1), item(2)])
        let dir = URL(filePath: "/tmp/x", directoryHint: .isDirectory)
        let present: Set<String> = ["/tmp/x/v1.mov", "/tmp/x/v2.mov", "/tmp/x/v2.jpg"]
        let out = list.playable(in: dir) { present.contains($0.path) }
        XCTAssertEqual(out.map(\.item.name), ["Video 1", "Video 2"])
        XCTAssertNil(out[0].posterURL)
        XCTAssertNotNil(out[1].posterURL)
        XCTAssertTrue(list.playable(in: dir) { _ in false }.isEmpty)
    }

    func testOrderKeepsSequenceUnlessShuffleAndNeverRepeatsLastFirst() {
        let items = (1...5).map(item)
        let resolved = items.map { SaverPlaylist.Resolved(item: $0, videoURL: URL(filePath: "/tmp/\($0.file)"), posterURL: nil) }
        var g = SeededGenerator(state: 7)
        let plain = SaverPlaylist(appVersion: "", updatedAt: .now, shuffle: false, items: items)
        XCTAssertEqual(plain.order(resolved, using: &g), resolved)
        let shuffled = SaverPlaylist(appVersion: "", updatedAt: .now, shuffle: true, items: items)
        for seed in 0..<50 {
            var rng = SeededGenerator(state: UInt64(seed))
            let last = items[2].id
            let out = shuffled.order(resolved, avoidingFirst: last, using: &rng)
            XCTAssertEqual(Set(out.map(\.item.id)), Set(items.map(\.id)))
            XCTAssertNotEqual(out.first?.item.id, last)
        }
        let one = shuffled.order([resolved[0]], using: &g)
        XCTAssertEqual(one, [resolved[0]])
    }

    func testPathsAreAbsoluteAndNotHomeRelative() {
        XCTAssertTrue(SaverPaths.defaultSharedDirectory.path.hasPrefix("/Users/Shared/"))
        XCTAssertEqual(SaverPaths.playlistURL().lastPathComponent, "playlist.json")
        XCTAssertTrue(SaverPaths.settingsURLString.hasPrefix("x-apple.systempreferences:com.apple.ScreenSaver"))
    }
}
