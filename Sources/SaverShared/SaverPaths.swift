import Foundation

/// Uygulama ile ekran koruyucunun ORTAK sabitleri (iki hedefe de derlenir).
///
/// Konum kararı: legacyScreenSaver ana süreci sandbox'lıdır ama yetkilerinde
/// `com.apple.security.temporary-exception.files.absolute-path.read-only = ["/"]` vardır (macOS 27.2'de
/// `codesign -d --entitlements` ile doğrulandı). Yani MUTLAK yoldan her yeri okuyabilir. Ev dizinindeki yollar
/// (`~`, `NSHomeDirectory()`, `FileManager.urls(for:)`) konteynere yönlendirildiğinden KULLANILMAZ; bu yüzden
/// sabit, mutlak ve TCC korumasız `/Users/Shared/Adalmon/Saver` seçildi. Uygulama o dizine yazar (konteynere değil:
/// başka uygulamanın verisine yazma izni gerekmez), ekran koruyucu yalnızca okur.
enum SaverPaths {
    /// Ekran koruyucunun okuduğu klasör (videolar, posterler, `playlist.json`).
    static let defaultSharedDirectory = URL(filePath: "/Users/Shared/Adalmon/Saver", directoryHint: .isDirectory)
    /// Yalnızca testler: ortam değişkeni verilirse o dizin kullanılır (sandbox'lı ana süreçte değişken yoktur).
    static var sharedDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["ADALMON_SAVER_DIR_FOR_TESTS"], override.hasPrefix("/") {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        return defaultSharedDirectory
    }
    static let playlistFileName = "playlist.json"
    static let bundleName = "AdalmonSaver.saver"
    static let bundleIdentifier = "com.example.adalmon.saver"
    /// Sistem Ayarları > Ekran Koruyucu.
    static let settingsURLString = "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension"

    static func playlistURL(in directory: URL = sharedDirectory) -> URL {
        directory.appending(path: playlistFileName)
    }
}
