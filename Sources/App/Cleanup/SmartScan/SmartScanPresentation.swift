import Foundation

/// Sonuç ekranındaki metinler (saf işlevler; testlenebilir).
enum SmartScanPresentation {
    /// Proje artığı türü, kullanıcıya anlamlı adla.
    static func artifactKind(_ folderName: String) -> String {
        switch folderName {
        case "node_modules": "Node bağımlılıkları (node_modules)"
        case ".build": "Swift derleme çıktısı (.build)"
        case "DerivedData": "Xcode DerivedData"
        case "target": "Rust derleme çıktısı (target)"
        case "Pods": "CocoaPods (Pods)"
        case "build": "Gradle derleme çıktısı (build)"
        default: folderName
        }
    }

    /// Proje adı: artığın üst klasörü.
    static func projectName(_ item: CleanupItem) -> String {
        ((item.path as NSString).deletingLastPathComponent as NSString).lastPathComponent
    }

    /// "3 ay önce" gibi göreli tarih.
    static func relativeDate(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "tarih yok" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// Satırın ikinci satırı. Proje artığı: tür + son değişiklik (+ yeniyse neden seçilmediği); diğerleri: kısa yol.
    static func detail(_ item: CleanupItem, home: String, now: Date = Date()) -> String {
        if item.category == .projectArtifacts {
            var text = "\(artifactKind(item.name)) · son değişiklik \(relativeDate(item.modified, now: now))"
            if item.blockedReason != nil {
                text += " · \(item.blockedReason ?? "")"
            } else if SmartScanSelection.isRecent(item, now: now) {
                text += " · son \(SmartScanSelection.staleDays) günde kullanılmış, seçilmedi"
            }
            return text
        }
        return FolderWatchList.displayPath(item.path, home: home)
    }

    static func title(_ item: CleanupItem) -> String {
        item.category == .projectArtifacts ? projectName(item) : item.name
    }

    /// Erişimi reddedilen kökler için kısa metin ("Belgeler, Masaüstü").
    static func deniedText(_ roots: [String], home: String) -> String {
        roots.map { FolderWatchList.displayPath($0, home: home) }.joined(separator: ", ")
    }
}
