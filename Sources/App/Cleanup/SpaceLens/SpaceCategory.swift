import Foundation

/// Treemap karosunun renk kategorisi: aynı tür aynı renk paletini alır. Salt ad/uzantı tablosu; diske dokunmaz.
enum SpaceCategory: String, CaseIterable, Sendable {
    case apps, media, developer, documents, archives, system, folder, file, other

    var title: String {
        switch self {
        case .apps: "Uygulamalar"
        case .media: "Medya"
        case .developer: "Geliştirici"
        case .documents: "Belgeler"
        case .archives: "Arşiv ve imajlar"
        case .system: "Sistem ve önbellek"
        case .folder: "Klasörler"
        case .file: "Dosyalar"
        case .other: "Diğer"
        }
    }

    static let mediaExtensions: Set<String> = ["mp4", "mov", "mkv", "avi", "m4v", "webm", "mp3", "wav", "flac", "aac", "m4a", "aiff",
                                               "jpg", "jpeg", "png", "heic", "gif", "tiff", "tif", "webp", "raw", "cr2", "arw", "dng", "psd"]
    static let documentExtensions: Set<String> = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers", "txt", "md", "rtf", "epub", "csv"]
    static let archiveExtensions: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "dmg", "iso", "pkg", "xip", "ipsw"]
    static let developerExtensions: Set<String> = ["swift", "o", "a", "dylib", "class", "jar", "xcarchive", "ipa", "apk", "aab", "py", "pyc", "js", "ts", "so"]
    static let developerNames: Set<String> = ["node_modules", ".git", "Developer", "DerivedData", "Xcode", ".npm", ".gradle", ".cargo", ".rustup",
                                              ".pub-cache", ".docker", ".colima", ".lima", ".orbstack", "Pods", ".venv", "venv", ".m2", ".android",
                                              "Android", "CoreSimulator", "build", ".build", "target", ".next", "vendor", "Carthage"]
    static let mediaNames: Set<String> = ["Movies", "Music", "Pictures", "Photos", "Podcasts", "Videos"]
    static let documentNames: Set<String> = ["Documents", "Desktop", "Downloads", "Books"]
    static let systemNames: Set<String> = ["Library", "Caches", ".cache", "Logs", ".Trash", "Trash", "tmp", "var", "private", "System"]

    static func of(_ node: SpaceNode) -> SpaceCategory {
        switch node.kind {
        case .locked, .skipped: return .other
        case .folder, .file: break
        }
        let name = node.name
        let ext = (name as NSString).pathExtension.lowercased()
        if ext == "app" || name == "Applications" { return .apps }
        if ext == "photoslibrary" || ext == "musiclibrary" || ext == "tvlibrary" || ext == "imovielibrary" || mediaNames.contains(name) { return .media }
        if developerNames.contains(name) { return .developer }
        if systemNames.contains(name) { return .system }
        if documentNames.contains(name) { return .documents }
        if node.isFolder { return .folder }
        if mediaExtensions.contains(ext) { return .media }
        if archiveExtensions.contains(ext) { return .archives }
        if developerExtensions.contains(ext) { return .developer }
        if documentExtensions.contains(ext) { return .documents }
        return .file
    }

    /// (ton, doygunluk, parlaklık); açık/koyu temada okunur beyaz yazı için orta parlaklık.
    var hsb: (h: Double, s: Double, b: Double) {
        switch self {
        case .apps: (0.76, 0.52, 0.72)
        case .media: (0.93, 0.50, 0.76)
        case .developer: (0.40, 0.55, 0.60)
        case .documents: (0.09, 0.62, 0.80)
        case .archives: (0.00, 0.55, 0.72)
        case .system: (0.53, 0.50, 0.66)
        case .folder: (0.61, 0.52, 0.76)
        case .file: (0.64, 0.14, 0.58)
        case .other: (0.00, 0.00, 0.50)
        }
    }
}
