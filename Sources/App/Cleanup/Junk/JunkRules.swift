import Foundation

/// Sistem çöpü kuralları: günlükler ve tarayıcı önbellekleri. Kural listeleri bu projenin kendi yazdığı listelerdir
/// (dış bir kuralı kopyalamaz); yalnızca kullanıcı Library'sindeki yeniden üretilebilir veriyi kapsar.
enum JunkRules {
    /// Önbelleği temizlenebilen tarayıcı: kapalıyken (paket kimliği çalışmıyorken) silinebilir.
    struct BrowserCache: Sendable, Equatable {
        let name: String
        let bundleID: String
        /// Ev klasörüne göre önbellek klasörleri; öğeler bunların doğrudan çocukları (profil klasörleri) olur.
        let relativePaths: [String]
    }

    /// Yalnızca Chrome ve Edge. Firefox desteklenmez (kullanıcı kuralı); Safari önbelleği de kapsam dışıdır.
    static let browsers: [BrowserCache] = [
        BrowserCache(name: "Google Chrome", bundleID: "com.google.Chrome",
                     relativePaths: ["Library/Caches/Google/Chrome", "Library/Caches/com.google.Chrome"]),
        BrowserCache(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac",
                     relativePaths: ["Library/Caches/Microsoft Edge", "Library/Caches/com.microsoft.edgemac"]),
    ]

    /// Günlük klasöründe dokunulmayanlar: çökme raporları tanılama için kalır.
    static let logsSkipNames: Set<String> = ["DiagnosticReports"]

    static func roots(home: String) -> [CleanupRoot] {
        var roots: [CleanupRoot] = [
            CleanupRoot(category: .logs, path: home + "/Library/Logs", skipNames: logsSkipNames),
        ]
        for browser in browsers {
            for rel in browser.relativePaths {
                roots.append(CleanupRoot(category: .browserCaches, path: home + "/" + rel, blockingBundleIDs: [browser.bundleID]))
            }
        }
        return roots
    }

    /// Tarayıcı adı (kartta "Chrome açık" gibi göstermek için) ya da nil.
    static func browserName(bundleID: String) -> String? {
        browsers.first { $0.bundleID == bundleID }?.name
    }

    /// Çalışanlar arasındaki desteklenen tarayıcılar.
    static func runningBrowsers(_ running: Set<String>) -> [String] {
        browsers.filter { running.contains($0.bundleID) }.map(\.name)
    }
}
