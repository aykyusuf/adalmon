import AppKit
import XCTest
@testable import Adalmon

/// Erişim nedeni tablosu, sahte deneme (PathProbe) ve didBecomeActive ile yeniden deneme. Gerçek kullanıcı klasörü denenmez;
/// uçtan uca test geçici sahte ev klasöründe chmod ile çalışır.
@MainActor
final class CleanupAccessTests: XCTestCase {
    private let home = "/Users/u"

    /// Yol başına sahte sonuç; çağrılar sayılır.
    private final class FakeProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [String: PathProbe.Raw] = [:]
        private var _calls: [String] = []
        var calls: [String] { lock.withLock { _calls } }
        func set(_ path: String, _ raw: PathProbe.Raw) { lock.withLock { results[path] = raw } }
        var probe: PathProbe {
            PathProbe { [self] path in
                lock.withLock {
                    _calls.append(path)
                    return results[path] ?? .missing
                }
            }
        }
    }

    // MARK: Neden tablosu

    func testAccessReasonTable() {
        let table: [(String, AccessReason)] = [
            ("/Users/u/Downloads", .filesAndFolders(.downloads)),
            ("/Users/u/Downloads/big.zip", .filesAndFolders(.downloads)),
            ("/Users/u/Desktop/x", .filesAndFolders(.desktop)),
            ("/Users/u/Documents", .filesAndFolders(.documents)),
            ("/Users/u/.Trash", .fullDiskAccess),
            ("/Users/u/Library/Application Support/MobileSync/Backup", .fullDiskAccess),
            ("/Users/u/Library/Safari", .fullDiskAccess),
            ("/Users/u/Library/Mail/V10", .fullDiskAccess),
            ("/Users/u/Library/Messages", .fullDiskAccess),
            ("/Users/u/Library/Containers/com.foo.Bar", .appData),
            ("/Users/u/Library/Group Containers/group.com.foo", .appData),
            ("/Applications/Foo.app", .appManagement),
            ("/Users/u/Applications/Foo.app", .appManagement),
            ("/System/Library/Caches", .systemProtected),
            ("/usr/lib", .systemProtected),
            ("/Users/u/Library/Caches", .fullDiskAccess),
        ]
        for (path, expected) in table {
            XCTAssertEqual(CleanupAccess.reason(for: path, home: home), expected, path)
        }
        XCTAssertNotEqual(CleanupAccess.reason(for: "/Users/u/DownloadsOld", home: home), .filesAndFolders(.downloads), "bileşen bazlı eşleşme")
    }

    func testReasonSettingsLinksAndTexts() {
        XCTAssertEqual(AccessReason.filesAndFolders(.downloads).settingsURL.map(anchor), "Privacy_FilesAndFolders")
        XCTAssertEqual(AccessReason.fullDiskAccess.settingsURL.map(anchor), "Privacy_AllFiles")
        XCTAssertEqual(AccessReason.appData.settingsURL.map(anchor), "Privacy_AllFiles")
        XCTAssertEqual(AccessReason.appManagement.settingsURL.map(anchor), "Privacy_AppBundles")
        XCTAssertNil(AccessReason.systemProtected.settingsURL)
        XCTAssertNil(AccessReason.systemProtected.buttonTitle)
        XCTAssertTrue(AccessReason.systemProtected.steps.isEmpty)
        XCTAssertEqual(AccessReason.filesAndFolders(.desktop).buttonTitle, "Dosyalar ve Klasörler'i aç")
        XCTAssertEqual(AccessReason.fullDiskAccess.buttonTitle, "Tam Disk Erişimi'ni aç")
        for reason in [AccessReason.filesAndFolders(.documents), .fullDiskAccess, .appData, .appManagement] {
            XCTAssertEqual(reason.steps.count, 3, "\(reason)")
            XCTAssertTrue(reason.steps.joined().contains("+"), "\(reason): + ile ekleme adımı")
        }
        XCTAssertTrue(AccessReason.filesAndFolders(.downloads).title.contains("İndirilenler"))
    }

    // MARK: Deneme

    func testScannerProbeReturnsReason() {
        let fake = FakeProbe()
        fake.set("/Users/u/Downloads", .denied)
        fake.set("/Users/u/Library/Caches", .ok)
        XCTAssertEqual(CleanupScanner.probe("/Users/u/Downloads", home: home, using: fake.probe), .noAccess(.filesAndFolders(.downloads)))
        XCTAssertEqual(CleanupScanner.probe("/Users/u/Library/Caches", home: home, using: fake.probe), .ok)
        XCTAssertEqual(CleanupScanner.probe("/Users/u/nothing", home: home, using: fake.probe), .missing)
    }

    func testFullDiskAccessBadgeProbesSafariFolder() {
        let fake = FakeProbe()
        XCTAssertNil(CleanupAccess.fullDiskAccessGranted(home: home, probe: fake.probe))
        XCTAssertEqual(fake.calls, ["/Users/u/Library/Safari"])
        fake.set("/Users/u/Library/Safari", .denied)
        XCTAssertEqual(CleanupAccess.fullDiskAccessGranted(home: home, probe: fake.probe), false)
        fake.set("/Users/u/Library/Safari", .ok)
        XCTAssertEqual(CleanupAccess.fullDiskAccessGranted(home: home, probe: fake.probe), true)
    }

    // MARK: Yeniden deneme

    func testObserverOnlyWhileBlockedAndReprobeUnblocks() {
        let fake = FakeProbe()
        let downloads = "/Users/u/Downloads"
        let caches = "/Users/u/Library/Caches"
        let monitor = CleanupAccessMonitor(home: home, probe: fake.probe)
        var freedPaths: [String] = []
        monitor.onUnblocked = { freedPaths += $0 }

        monitor.update(states: [caches: .scanned])
        XCTAssertFalse(monitor.isObserving, "engel yokken gözlemci kurulmaz")

        monitor.update(states: [downloads: .noAccess, caches: .scanned])
        XCTAssertTrue(monitor.isObserving)
        XCTAssertEqual(monitor.reason(for: downloads), .filesAndFolders(.downloads))

        fake.set(downloads, .denied)
        XCTAssertEqual(monitor.reprobe(), [])
        XCTAssertTrue(monitor.isObserving)
        XCTAssertFalse(monitor.suggestRestart, "ayarlar açılmadıysa yeniden başlatma önerilmez")

        fake.set(downloads, .ok)
        XCTAssertEqual(monitor.reprobe(), [downloads])
        XCTAssertEqual(freedPaths, [downloads])
        XCTAssertTrue(monitor.blocked.isEmpty)
        XCTAssertFalse(monitor.isObserving, "engel kalkınca gözlemci kaldırılır")
    }

    func testDidBecomeActiveTriggersReprobeAndRestartSuggestion() {
        let fake = FakeProbe()
        let trash = "/Users/u/.Trash"
        fake.set(trash, .denied)
        let monitor = CleanupAccessMonitor(home: home, probe: fake.probe)
        var opened: [URL] = []
        monitor.openURL = { opened.append($0) }
        monitor.setBlocked(trash, true)
        XCTAssertEqual(monitor.reason(for: trash), .fullDiskAccess)

        monitor.openSettings(for: .fullDiskAccess)
        XCTAssertEqual(opened.map(anchor), ["Privacy_AllFiles"])

        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertTrue(fake.calls.contains(trash), "öne gelince yeniden denenir")
        XCTAssertTrue(monitor.suggestRestart, "ayarlardan dönüldü ama engel sürüyor")

        fake.set(trash, .ok)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertTrue(monitor.blocked.isEmpty)
        XCTAssertFalse(monitor.suggestRestart)
        XCTAssertFalse(monitor.isObserving)

        let before = fake.calls.count
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(fake.calls.count, before, "engel yokken öne gelme hiçbir şey denemez")
    }

    /// Uçtan uca: sahte evde Caches kapalı (chmod 000) → .noAccess; açılınca yeniden deneme yeniden tarar → .scanned.
    func testViewModelBlockedThenScannedAfterReprobe() async throws {
        let fixture = FileManager.default.temporaryDirectory.appending(path: "access-\(UUID().uuidString)", directoryHint: .isDirectory)
        let caches = fixture.appending(path: "Library/Caches", directoryHint: .isDirectory)
        let file = caches.appending(path: "com.foo/x.bin")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: 2 << 20).write(to: file)
        defer {
            chmod(caches.path, 0o755)
            try? FileManager.default.removeItem(at: fixture)
        }
        XCTAssertEqual(chmod(caches.path, 0o000), 0)

        let vm = CleanupViewModel(home: fixture.path)
        vm.scan([.appCaches])
        try await waitIdle(vm)
        XCTAssertEqual(vm.rootStates[caches.path], .noAccess)
        XCTAssertEqual(vm.state(of: .appCaches), .noAccess)
        XCTAssertNotNil(vm.accessReason(for: .appCaches))
        XCTAssertTrue(vm.access.isObserving)

        XCTAssertEqual(chmod(caches.path, 0o755), 0)
        XCTAssertEqual(vm.access.reprobe(), [caches.path])
        try await waitIdle(vm)
        XCTAssertEqual(vm.rootStates[caches.path], .scanned)
        XCTAssertEqual(vm.items(in: .appCaches).map(\.name), ["com.foo"])
        XCTAssertFalse(vm.access.isObserving)
    }

    private func anchor(_ url: URL) -> String { url.absoluteString.components(separatedBy: "?").last ?? "" }

    private func waitIdle(_ vm: CleanupViewModel) async throws {
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(25))
            if !vm.isBusy { return }
        }
        XCTFail("tarama bitmedi")
    }
}
