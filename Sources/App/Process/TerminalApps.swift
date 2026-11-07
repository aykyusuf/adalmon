import Foundation

/// Alt süreç başlatan terminal / IDE uygulamaları. Bunların coalition'ı süreç başına bölünür: terminalden başlatılan
/// `xcodebuild`, `swift-frontend`, `claude`, `node` gibi araçlar terminalin değil kendi adlarına yazılır.
enum TerminalApps {
    /// `.app` paket adı (küçük harf, uzantısız).
    static let bundleStems: Set<String> = [
        "warp", "terminal", "iterm", "iterm2", "ghostty", "alacritty", "kitty", "wezterm",
        "visual studio code", "visual studio code - insiders", "code", "cursor", "vscodium", "windsurf",
        "hyper", "tabby", "rio",
    ]

    /// - Parameter key: uygulama anahtarı (`.app` yolu).
    static func isTerminal(key: String) -> Bool {
        guard key.hasPrefix("/"), key.hasSuffix(".app"), !TerminalChildKey.isChild(key) else { return false }
        let stem = ((key as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
        return bundleStems.contains(stem)
    }
}
