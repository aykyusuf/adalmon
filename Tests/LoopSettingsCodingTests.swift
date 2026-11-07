import XCTest
@testable import Adalmon

/// Eski ↔ yeni JSON uyumu: duvar kâğıdı ayarları (UserDefaults) ve ekran koruyucu oynatma listesi.
final class LoopSettingsCodingTests: XCTestCase {
    private let id = "00000000-0000-0000-0000-000000000001"

    /// Döngü alanları eklenmeden ÖNCE yazılmış gerçek biçimli kayıt: ayarlar silinmemeli.
    func testOldWallpaperSettingsJSONStillDecodesAndKeepsValues() throws {
        let rules = try String(decoding: JSONEncoder().encode(WallpaperPauseRules()), as: UTF8.self)
        let json = #"{"enabled":true,"rules":\#(rules),"sameOnAllScreens":false,"defaultItemID":"\#(id)","perScreen":{},"playlistMode":"shuffle","rotationMinutes":15,"frameRateCap":24,"experimentalAerialAcknowledged":true}"#
        let s = try JSONDecoder().decode(WallpaperSettings.self, from: Data(json.utf8))
        XCTAssertTrue(s.enabled)
        XCTAssertFalse(s.sameOnAllScreens)
        XCTAssertEqual(s.defaultItemID, UUID(uuidString: id))
        XCTAssertEqual(s.playlistMode, .shuffle)
        XCTAssertEqual(s.rotationMinutes, 15)
        XCTAssertEqual(s.frameRateCap, .fps24)
        XCTAssertTrue(s.experimentalAerialAcknowledged)
        XCTAssertEqual(s.loop, LoopSettings(), "eksik döngü alanı varsayılan: 5 / 3 / çapraz geçiş 1,5")
    }

    func testWallpaperSettingsRoundTripWithLoop() throws {
        var s = WallpaperSettings()
        s.loop = LoopSettings(trimStart: 8, trimEnd: 2, transition: .off, crossfadeSeconds: 2.2)
        let back = try JSONDecoder().decode(WallpaperSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
        XCTAssertEqual(back.loop.timing, LoopTiming(trimStart: 8, trimEnd: 2, crossfade: 0))
    }

    func testPartialOrBrokenLoopObjectFallsBackPerField() throws {
        let partial = try JSONDecoder().decode(LoopSettings.self, from: Data(#"{"trimStart":9}"#.utf8))
        XCTAssertEqual(partial.trimStart, 9)
        XCTAssertEqual(partial.trimEnd, 3)
        XCTAssertEqual(partial.transition, .crossfade)
        let broken = try JSONDecoder().decode(LoopSettings.self, from: Data(#"{"trimStart":"x","transition":"spin","crossfadeSeconds":-1}"#.utf8))
        XCTAssertEqual(broken.trimStart, 5)
        XCTAssertEqual(broken.transition, .crossfade)
        XCTAssertEqual(broken.crossfadeSeconds, 1.5)
    }

    // MARK: Oynatma listesi

    func testOldPlaylistWithoutLoopKeysGetsDefaults() throws {
        let json = #"{"schema":1,"appVersion":"0.1.0","updatedAt":"2026-11-07T10:00:00Z","shuffle":true,"hostExitOnStop":false,"items":[{"id":"\#(id)","name":"a","file":"a.mov","width":1920,"height":1080,"duration":30}]}"#
        let list = try SaverPlaylist.decode(Data(json.utf8))
        XCTAssertEqual(list.schema, 1)
        XCTAssertEqual(list.timing, .default)
        XCTAssertFalse(list.hostExitOnStop)
        XCTAssertTrue(list.shuffle)
    }

    func testNewPlaylistRoundTripKeepsLoopAndSchemaStaysReadableByOldSavers() throws {
        let item = SaverPlaylistItem(id: UUID(uuidString: id)!, name: "a", file: "a.mov", poster: nil, width: 1, height: 1, duration: 30)
        let list = SaverPlaylist(appVersion: "x", updatedAt: Date(timeIntervalSince1970: 1_800_000_000), shuffle: false, trimStart: 7, trimEnd: 1, crossfade: 0, items: [item])
        let data = try list.encoded()
        let back = try SaverPlaylist.decode(data)
        XCTAssertEqual(back, list)
        XCTAssertEqual(back.timing, LoopTiming(trimStart: 7, trimEnd: 1, crossfade: 0))
        XCTAssertEqual(back.schema, 1, "ekleme uyumlu: şema artmaz (kurulu eski paket okuyabilsin)")

        // Eski ekran koruyucunun şeması: yeni anahtarları yok sayarak çözebilmeli.
        struct LegacyItem: Decodable { var id: UUID; var name: String; var file: String; var poster: String?; var width: Int; var height: Int; var duration: Double }
        struct LegacyPlaylist: Decodable { var schema: Int; var appVersion: String; var updatedAt: Date; var shuffle: Bool; var hostExitOnStop: Bool; var items: [LegacyItem] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let old = try dec.decode(LegacyPlaylist.self, from: data)
        XCTAssertEqual(old.items.count, 1)
        XCTAssertEqual(old.schema, 1)
    }

    func testPlaylistSanitizesBrokenLoopValues() throws {
        let json = #"{"schema":1,"appVersion":"x","updatedAt":"2026-11-07T10:00:00Z","shuffle":false,"trimStart":-9,"trimEnd":"oops","crossfade":42,"items":[]}"#
        let list = try SaverPlaylist.decode(Data(json.utf8))
        XCTAssertEqual(list.timing, LoopTiming(trimStart: 0, trimEnd: 3, crossfade: 3))
    }

    func testStoreRewriteLoopOnlyTouchesLoopFields() async throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "loop-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = SaverContentStore(directory: tmp)
        XCTAssertNoThrow(try store.rewritePlaylistLoop(.none), "liste yokken sessizce geçer")
        let src = tmp.deletingLastPathComponent().appending(path: "loop-src-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: src) }
        try await TinyMedia.video(at: src, frames: 6)
        let source = SaverContentStore.Source(id: UUID(), name: "v", url: src, byteSize: WallpaperMedia.fileSize(src), width: 128, height: 72, duration: 1)
        let written = try await store.sync([source], options: .init(shuffle: true, hostExitOnStop: false, appVersion: "t", loop: LoopTiming(trimStart: 2, trimEnd: 1, crossfade: 1)))
        XCTAssertEqual(written.timing, LoopTiming(trimStart: 2, trimEnd: 1, crossfade: 1))
        try store.rewritePlaylistLoop(.default)
        let after = try XCTUnwrap(store.currentPlaylist())
        XCTAssertEqual(after.timing, .default)
        XCTAssertTrue(after.shuffle)
        XCTAssertFalse(after.hostExitOnStop)
        XCTAssertEqual(after.items, written.items)
    }
}
