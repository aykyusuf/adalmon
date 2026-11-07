import CryptoKit
import XCTest
@testable import Adalmon

/// Aerial manifest düzenleme: yalnızca GEÇİCİ kopya üzerinde (gerçek ~/Library dosyasına asla dokunmaz).
final class AerialManifestTests: XCTestCase {
    private var tmp: URL!
    private var root: URL!
    private var support: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appending(path: "aerial-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        root = tmp.appending(path: "aerials", directoryHint: .isDirectory)
        support = tmp.appending(path: "support", directoryHint: .isDirectory)
        for d in ["manifest", "videos", "thumbnails"] { try FileManager.default.createDirectory(at: root.appending(path: d), withIntermediateDirectories: true) }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    /// Gerçek manifest'in (macOS 27.2'de gözlenen) şekline uygun küçük bir kurgu.
    static func fixture(version: Int = 1, extraAsset: Bool = false) -> [String: Any] {
        func asset(_ id: String, order: Int) -> [String: Any] {
            ["accessibilityLabel": "macOS", "categories": ["dynamic-aerials"], "id": id, "includeInShuffle": false,
             "localizedNameKey": "DYNAMIC_LIGHT_KEY", "pointsOfInterest": [String: Any](), "preferredOrder": order,
             "previewImage": "https://sylvan.apple.com/itunes-assets/x/y.png", "shotID": "GG_LM_H", "showInTopLevel": true,
             "subcategories": ["17647EAB-8357-48B0-BCD6-B892194267C5"], "url-4K-SDR-240FPS": "https://sylvan.apple.com/itunes-assets/z/GG.mov",
             "variant": ["appearance": "light", "orientation": "landscape"], "videoGravity": "resize"]
        }
        var assets = [asset("4DFE24ED-71CC-42D4-9FE8-3B8959B6CC19", order: 0), asset("11AB4259-C435-4F92-A108-D6B9CC6D2295", order: 1)]
        if extraAsset { assets.append(asset("99999999-C435-4F92-A108-D6B9CC6D2295", order: 2)) }
        let sub: [String: Any] = ["combineVariants": true, "id": "17647EAB-8357-48B0-BCD6-B892194267C5", "localizedDescriptionKey": "k", "localizedNameKey": "k",
                                  "preferredOrder": -500, "previewImage": "https://sylvan.apple.com/p.png", "representativeAssetID": "4DFE24ED-71CC-42D4-9FE8-3B8959B6CC19"]
        let cat: [String: Any] = ["id": "dynamic-aerials", "localizedDescriptionKey": "d", "localizedNameKey": "n", "preferredOrder": 0,
                                  "previewImage": "https://sylvan.apple.com/c.png", "representativeAssetID": "4DFE24ED-71CC-42D4-9FE8-3B8959B6CC19", "subcategories": [sub]]
        return ["assets": assets, "categories": [cat], "initialAssetCount": 4, "localizationVersion": "22L-1", "version": version]
    }

    private func writeFixture(_ obj: [String: Any]) throws -> Data {
        let data = try AerialManifest.serialize(obj)
        try data.write(to: root.appending(path: "manifest/entries.json"))
        return data
    }

    private func installer(os: Int = 26) -> AerialInstaller {
        AerialInstaller(root: root, supportDirectory: support, osVersion: OperatingSystemVersion(majorVersion: os, minorVersion: 2, patchVersion: 0))
    }

    private func fakeItems(_ n: Int) throws -> [AerialInstaller.Item] {
        try (0..<n).map { i in
            let v = tmp.appending(path: "src\(i).mov"), t = tmp.appending(path: "src\(i).png")
            try Data("video\(i)".utf8).write(to: v); try Data("png\(i)".utf8).write(to: t)
            return .init(name: "Test \(i)", videoFile: v, thumbnailFile: t)
        }
    }

    private func manifest() throws -> [String: Any] { try AerialManifest.parse(Data(contentsOf: root.appending(path: "manifest/entries.json"))) }

    func testInsertRemoveRoundTripInMemory() throws {
        let original = Self.fixture()
        let entry = AerialManifest.Entry(assetID: AerialManifest.newAssetID(), name: "A", videoURL: URL(filePath: "/tmp/a.mov"), thumbnailURL: URL(filePath: "/tmp/a.png"))
        let inserted = try AerialManifest.inserting([entry], into: original)
        XCTAssertEqual((inserted["assets"] as? [[String: Any]])?.count, 3)
        XCTAssertEqual((inserted["categories"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(AerialManifest.ourAssetIDs(in: inserted), [entry.assetID])
        let removed = AerialManifest.removing(from: inserted)
        XCTAssertTrue(NSDictionary(dictionary: original).isEqual(to: removed), "ekle + çıkar özgün manifest'e eşit olmalı")
    }

    func testInsertedCategoryHasRepresentativeAtBothLevels() throws {
        let entries = (0..<2).map { AerialManifest.Entry(assetID: AerialManifest.newAssetID(), name: "N\($0)", videoURL: URL(filePath: "/v\($0).mov"), thumbnailURL: URL(filePath: "/t\($0).png")) }
        let out = try AerialManifest.inserting(entries, into: Self.fixture())
        let cat = try XCTUnwrap((out["categories"] as? [[String: Any]])?.first { $0["id"] as? String == AerialManifest.categoryID })
        XCTAssertEqual(cat["representativeAssetID"] as? String, entries[0].assetID)
        let sub = try XCTUnwrap((cat["subcategories"] as? [[String: Any]])?.first)
        XCTAssertEqual(sub["representativeAssetID"] as? String, entries[0].assetID)
        XCTAssertTrue(entries.allSatisfy { $0.assetID.hasPrefix(AerialManifest.idPrefix) && UUID(uuidString: $0.assetID) != nil })
    }

    func testInsertIsIdempotent() throws {
        let e = AerialManifest.Entry(assetID: AerialManifest.newAssetID(), name: "A", videoURL: URL(filePath: "/a.mov"), thumbnailURL: URL(filePath: "/a.png"))
        let once = try AerialManifest.inserting([e], into: Self.fixture())
        let twice = try AerialManifest.inserting([e], into: once)
        XCTAssertEqual(AerialManifest.ourAssetIDs(in: twice).count, 1)
        XCTAssertEqual((twice["categories"] as? [[String: Any]])?.count, 2)
    }

    func testSerializedOutputKeepsSlashesUnescaped() throws {
        let text = try String(decoding: AerialManifest.serialize(Self.fixture()), as: UTF8.self)
        XCTAssertTrue(text.contains("https://sylvan.apple.com"))
        XCTAssertFalse(text.contains("\\/"))
    }

    func testFormatProblems() {
        XCTAssertFalse(AerialManifest.problems(in: Self.fixture(version: 2)).isEmpty)
        XCTAssertFalse(AerialManifest.problems(in: ["assets": [Any]()]).isEmpty)
        XCTAssertFalse(AerialManifest.problems(in: ["assets": [["id": "x"]], "categories": [[String: Any]](), "version": 1]).isEmpty)
        XCTAssertTrue(AerialManifest.problems(in: Self.fixture()).isEmpty)
    }

    func testCompatibilityGate() throws {
        _ = try writeFixture(Self.fixture())
        XCTAssertEqual(installer(os: 26).compatibility(), .supported)
        if case .warning(let m) = installer(os: 27).compatibility() { XCTAssertTrue(m.contains("macOS 27")) } else { XCTFail("macOS 27 uyarı vermeli") }
        XCTAssertFalse(installer(os: 15).compatibility().canInstall)
        XCTAssertFalse(installer(os: 28).compatibility().canInstall)
        _ = try writeFixture(Self.fixture(version: 3))
        XCTAssertFalse(installer(os: 27).compatibility().canInstall)
    }

    func testInstallThenUninstallRestoresBytesExactly() throws {
        let originalData = try writeFixture(Self.fixture())
        let inst = installer()
        let state = try inst.install(try fakeItems(2))
        XCTAssertEqual(state.assetIDs.count, 2)
        XCTAssertEqual(inst.status(), .installed(count: 2))
        // Dosyalar kopyalandı
        for id in state.assetIDs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "videos/\(id).mov").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "thumbnails/\(id).png").path))
        }
        // Yedekler: özgün + zaman damgalı
        XCTAssertEqual(try Data(contentsOf: inst.backupDirectory.appending(path: "entries.original.json")), originalData)
        let method = try inst.uninstall()
        XCTAssertEqual(method, .restoredBackup)
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "manifest/entries.json")), originalData)
        XCTAssertEqual(inst.status(), .notInstalled)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "videos").path).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "thumbnails").path).isEmpty)
    }

    func testUninstallAfterAppleRefreshRemovesOnlyOurEntries() throws {
        _ = try writeFixture(Self.fixture())
        let inst = installer()
        _ = try inst.install(try fakeItems(1))
        // Apple manifest'i yeniden yazdı: yeni bir Apple asset'i eklenmiş, bizimkiler duruyor.
        var current = try manifest()
        var assets = current["assets"] as! [[String: Any]]
        var extra = assets[0]; extra["id"] = "99999999-C435-4F92-A108-D6B9CC6D2295"
        assets.append(extra); current["assets"] = assets
        try AerialManifest.serialize(current).write(to: root.appending(path: "manifest/entries.json"))
        let method = try inst.uninstall()
        XCTAssertEqual(method, .removedOurEntries)
        let after = try manifest()
        XCTAssertTrue(AerialManifest.ourAssetIDs(in: after).isEmpty)
        let ids = (after["assets"] as! [[String: Any]]).compactMap { $0["id"] as? String }
        XCTAssertTrue(ids.contains("99999999-C435-4F92-A108-D6B9CC6D2295"), "Apple'ın yeni kaydı korunmalı")
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual((after["categories"] as! [[String: Any]]).count, 1)
    }

    func testDriftIsDetected() throws {
        _ = try writeFixture(Self.fixture())
        let inst = installer()
        _ = try inst.install(try fakeItems(1))
        _ = try writeFixture(Self.fixture()) // Apple özgün haline döndürdü
        XCTAssertEqual(inst.status(), .drifted)
    }

    func testUnsupportedFormatWritesNothing() throws {
        let data = try writeFixture(Self.fixture(version: 2))
        XCTAssertThrowsError(try installer().install(try fakeItems(1)))
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "manifest/entries.json")), data)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "videos").path).isEmpty)
    }

    func testReinstallDoesNotDuplicateAndBackupStaysClean() throws {
        let originalData = try writeFixture(Self.fixture())
        let inst = installer()
        _ = try inst.install(try fakeItems(1))
        _ = try inst.install(try fakeItems(2))
        XCTAssertEqual(AerialManifest.ourAssetIDs(in: try manifest()).count, 2)
        XCTAssertEqual(try inst.uninstall(), .restoredBackup)
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "manifest/entries.json")), originalData)
    }

    func testRealManifestPathIsNotUsedByTests() {
        XCTAssertNotEqual(root.path, AerialInstaller.defaultRoot.path)
        XCTAssertTrue(root.path.hasPrefix(FileManager.default.temporaryDirectory.path) || root.path.contains("/tmp") || root.path.contains("/var/folders"))
    }
}
