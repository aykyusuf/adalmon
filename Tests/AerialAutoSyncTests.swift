import XCTest
@testable import Adalmon

/// "Kilit ekranında da göster": kararlar (saf) ve geçici manifest üzerinde tek kayıt değiştirme. Gerçek ~/Library'ye dokunulmaz.
final class AerialAutoSyncTests: XCTestCase {
    private func item(_ name: String, kind: WallpaperKind = .video, size: Int64 = 100, exists: Bool = true, id: UUID = UUID()) -> WallpaperItem {
        let path = exists ? "/etc/hosts" : "/nonexistent/\(name)"
        return WallpaperItem(id: id, name: name, path: path, kind: kind, addedAt: .now, byteSize: size, info: nil)
    }

    func testCurrentItemPrefersDefaultThenFirstUsableVideo() {
        let image = item("img", kind: .image), gone = item("gone", exists: false), a = item("a"), b = item("b")
        XCTAssertEqual(AerialAutoSync.currentItem(items: [image, gone, a, b], defaultID: b.id)?.id, b.id)
        XCTAssertEqual(AerialAutoSync.currentItem(items: [image, gone, a, b], defaultID: nil)?.id, a.id)
        XCTAssertEqual(AerialAutoSync.currentItem(items: [image, gone, a, b], defaultID: image.id)?.id, a.id, "görüntü ya da eksik dosya seçilmez")
        XCTAssertNil(AerialAutoSync.currentItem(items: [image, gone], defaultID: gone.id))
    }

    func testActionDecisions() {
        let a = AerialRegistration(itemID: UUID(), byteSize: 1), b = AerialRegistration(itemID: UUID(), byteSize: 1)
        func act(enabled: Bool = true, canInstall: Bool = true, status: AerialStatus = .installed(count: 1), current: AerialRegistration? = a,
                 registered: AerialRegistration? = a, failed: AerialRegistration? = nil) -> AerialAutoSync.Action {
            AerialAutoSync.action(enabled: enabled, canInstall: canInstall, status: status, current: current, registered: registered, failed: failed)
        }
        XCTAssertEqual(act(), .none, "aynı video zaten kayıtlı")
        XCTAssertEqual(act(current: b), .register(b), "video değişti -> değiştir")
        XCTAssertEqual(act(registered: nil), .register(a), "kayıt bilgisi yok")
        XCTAssertEqual(act(status: .drifted), .register(a), "Apple listeyi yenilemiş")
        XCTAssertEqual(act(status: .notInstalled), .register(a))
        XCTAssertEqual(act(enabled: false, current: b), .none, "kapalıyken hiçbir şey yazılmaz")
        XCTAssertEqual(act(canInstall: false, current: b), .none)
        XCTAssertEqual(act(current: nil), .none)
        XCTAssertEqual(act(current: b, failed: b), .none, "aynı kayıtta hata aldıysak döngüye girme")
        let sized = AerialRegistration(itemID: a.itemID, byteSize: 2)
        XCTAssertEqual(act(current: sized), .register(sized), "dosya değişti (boyut) -> yenile")
    }

    func testSettingsDefaultsAndDecoding() throws {
        XCTAssertFalse(WallpaperSettings().showInSystem)
        let old = try JSONDecoder().decode(WallpaperSettings.self, from: Data(#"{"enabled":true,"experimentalAerialAcknowledged":true}"#.utf8))
        XCTAssertFalse(old.showInSystem)
        XCTAssertTrue(old.experimentalAerialAcknowledged)
    }

    // MARK: Geçici manifest: tek kayıt değiştirme

    private var tmp: URL!
    private var root: URL!
    private var support: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appending(path: "aerial-auto-\(UUID().uuidString)", directoryHint: .isDirectory)
        root = tmp.appending(path: "aerials", directoryHint: .isDirectory)
        support = tmp.appending(path: "support", directoryHint: .isDirectory)
        for d in ["manifest", "videos", "thumbnails"] { try FileManager.default.createDirectory(at: root.appending(path: d), withIntermediateDirectories: true) }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func fakeItem(_ name: String) throws -> AerialInstaller.Item {
        let v = tmp.appending(path: "\(name).mov"), t = tmp.appending(path: "\(name).png")
        try Data("video-\(name)".utf8).write(to: v); try Data("png-\(name)".utf8).write(to: t)
        return .init(name: name, videoFile: v, thumbnailFile: t)
    }

    func testReplacingTheSingleEntryKeepsAppleEntriesAndBackup() throws {
        let original = try AerialManifest.serialize(AerialManifestTests.fixture())
        let manifestURL = root.appending(path: "manifest/entries.json")
        try original.write(to: manifestURL)
        let installer = AerialInstaller(root: root, supportDirectory: support, osVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 2, patchVersion: 0))
        let appleBefore = (try AerialManifest.parse(original)["assets"] as! [[String: Any]]).count

        let first = try installer.install([try fakeItem("birinci")])
        func manifest() throws -> [String: Any] { try AerialManifest.parse(Data(contentsOf: manifestURL)) }
        XCTAssertEqual(AerialManifest.ourAssetIDs(in: try manifest()), first.assetIDs)
        XCTAssertEqual(installer.status(), .installed(count: 1))

        // Video değişti: tek kayıt yenisiyle değişir.
        let second = try installer.install([try fakeItem("ikinci")])
        let ours = AerialManifest.ourAssetIDs(in: try manifest())
        XCTAssertEqual(ours, second.assetIDs)
        XCTAssertEqual(ours.count, 1, "her zaman tek Adalmon kaydı")
        XCTAssertNotEqual(ours, first.assetIDs)
        XCTAssertEqual((try manifest()["assets"] as! [[String: Any]]).count, appleBefore + 1, "Apple kayıtları aynen duruyor")
        let entry = try XCTUnwrap((try manifest()["assets"] as! [[String: Any]]).first { ($0["id"] as? String) == second.assetIDs[0] })
        XCTAssertEqual(entry["showInTopLevel"] as? Bool, true)
        XCTAssertEqual(entry["accessibilityLabel"] as? String, "ikinci")
        // Eski kaydın dosyaları süpürüldü.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "videos").path).count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "thumbnails").path).count, 1)
        // Yedek hiçbir zaman bizim kaydımızı içermez.
        XCTAssertEqual(try Data(contentsOf: installer.backupDirectory.appending(path: "entries.original.json")), original)

        // Anahtar kapatıldı: otomatik geri alma -> özgün dosya birebir.
        XCTAssertEqual(try installer.uninstall(), .restoredBackup)
        XCTAssertEqual(try Data(contentsOf: manifestURL), original)
    }
}
