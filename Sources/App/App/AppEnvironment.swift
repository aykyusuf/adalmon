import Foundation

/// Çalışma ortamı: testler uygulamayı host olarak yüklediği için gerçek kullanıcı verisine dokunmamalı.
enum AppEnvironment {
    /// XCTest altında mı (TEST_HOST = Adalmon.app olduğundan uygulama da test sırasında başlar).
    static let isRunningTests: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil || NSClassFromString("XCTestCase") != nil
    }()

    /// `~/Library/Application Support/Adalmon`; testlerde süreç başına geçici dizin.
    static let supportDirectory: URL = {
        let dir: URL
        if isRunningTests {
            dir = FileManager.default.temporaryDirectory.appending(path: "adalmon-tests-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)
        } else {
            dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "Adalmon", directoryHint: .isDirectory)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}
