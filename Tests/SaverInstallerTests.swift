import AppKit
import XCTest
@testable import Adalmon

/// Kurulum dosya işlemleri YALNIZCA geçici dizinde; gerçek ~/Library/Screen Savers ASLA kullanılmaz.
final class SaverInstallerTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appending(path: "saver-install-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func makeBundle(at url: URL, identifier: String = SaverPaths.bundleIdentifier, build: String = "1", code: String = "code-A") throws {
        let macOS = url.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": build, "CFBundleExecutable": "AdalmonSaver"]
        (info as NSDictionary).write(to: url.appending(path: "Contents/Info.plist"), atomically: true)
        try Data(code.utf8).write(to: macOS.appending(path: "AdalmonSaver"))
    }

    private func installer(embedded: URL? = nil) -> SaverInstaller {
        SaverInstaller(embeddedURL: embedded ?? tmp.appending(path: "App/AdalmonSaver.saver"), installDirectory: tmp.appending(path: "ScreenSavers"))
    }

    func testInstallUpdateUninstallCycle() throws {
        let embedded = tmp.appending(path: "App/AdalmonSaver.saver")
        try makeBundle(at: embedded)
        let sut = installer()
        XCTAssertEqual(sut.status(), .notInstalled)

        try sut.install()                    // dizin yokken de oluşturur
        guard case .installed(let fp) = sut.status() else { return XCTFail("kurulu olmalı: \(sut.status())") }
        XCTAssertEqual(fp.version, "0.1.0 (1)")

        // Aynı sürüm numarası ama kod değişti -> güncelleme gerekli (sürüm timestamp'i sabit kalırsa da yakalanır)
        try makeBundle(at: embedded, build: "1", code: "code-B")
        guard case .updateNeeded = sut.status() else { return XCTFail("güncelleme gerekli olmalı: \(sut.status())") }
        try sut.install()
        guard case .installed = sut.status() else { return XCTFail("güncellenmiş olmalı") }
        XCTAssertEqual(try String(contentsOf: sut.installedURL.appending(path: "Contents/MacOS/AdalmonSaver"), encoding: .utf8), "code-B")

        // Sürüm farkı da güncelleme sayılır
        try makeBundle(at: embedded, build: "2", code: "code-B")
        guard case .updateNeeded(let old, let new) = sut.status() else { return XCTFail() }
        XCTAssertEqual(old.version, "0.1.0 (1)"); XCTAssertEqual(new.version, "0.1.0 (2)")

        XCTAssertTrue(try sut.uninstall())
        XCTAssertEqual(sut.status(), .notInstalled)
        XCTAssertFalse(try sut.uninstall(), "ikinci kaldırma bir şey silmez")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: sut.installDirectory.path)
        XCTAssertTrue(leftovers.isEmpty, "geçici paket artığı kalmamalı: \(leftovers)")
    }

    func testForeignBundleWithSameNameIsNeverOverwrittenOrDeleted() throws {
        try makeBundle(at: tmp.appending(path: "App/AdalmonSaver.saver"))
        let sut = installer()
        try makeBundle(at: sut.installedURL, identifier: "com.someone.else", code: "theirs")
        XCTAssertEqual(sut.status(), .foreign)
        XCTAssertThrowsError(try sut.install()) { XCTAssertEqual($0 as? SaverInstaller.InstallError, .foreignBundle) }
        XCTAssertThrowsError(try sut.uninstall())
        XCTAssertTrue(FileManager.default.fileExists(atPath: sut.installedURL.path))
    }

    func testMissingEmbeddedBundleIsUnavailable() {
        let sut = SaverInstaller(embeddedURL: tmp.appending(path: "yok.saver"), installDirectory: tmp.appending(path: "ScreenSavers"))
        XCTAssertEqual(sut.status(), .unavailable)
        XCTAssertThrowsError(try sut.install())
        XCTAssertThrowsError(try SaverInstaller(embeddedURL: nil, installDirectory: tmp).install())
    }

    /// Derlemenin asıl çıktısı: uygulamanın içinde imzalı .saver var ve asıl sınıfı yüklenebiliyor.
    func testEmbeddedSaverIsPresentAndLoadsPrincipalClass() throws {
        let url = SaverInstaller.defaultEmbeddedURL
        let fp = try XCTUnwrap(SaverInstaller.fingerprint(of: url), "uygulamada Contents/Library/Screen Savers/AdalmonSaver.saver yok")
        XCTAssertEqual(fp.identifier, SaverPaths.bundleIdentifier)
        XCTAssertFalse(fp.executableDigest.isEmpty)
        let bundle = try XCTUnwrap(Bundle(url: url))
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "NSPrincipalClass") as? String, "AdalmonSaverView")
        XCTAssertTrue(bundle.load(), "paket yüklenemedi")
        let cls = try XCTUnwrap(bundle.principalClass as? NSView.Type, "ObjC görünür asıl sınıf yok")
        XCTAssertEqual(NSStringFromClass(cls), "AdalmonSaverView")
    }
}
