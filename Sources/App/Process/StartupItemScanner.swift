import Foundation

/// ~/Library/LaunchAgents ve /Library/LaunchAgents içindeki plist'leri okur (salt okunur).
/// Durum: plist'teki `Disabled` anahtarı; macOS 13+ "Giriş Öğeleri" geçersiz kılmaları (`launchctl disable`) okunamadığı için
/// `Disabled` yoksa etkin sayılır ("Bilinmiyor" yalnızca plist okunamazsa).
enum StartupItemScanner {
    static func directories() -> [(url: URL, scope: StartupItem.Scope)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [(home.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory), .user),
                (URL(filePath: "/Library/LaunchAgents", directoryHint: .isDirectory), .allUsers)]
    }

    static func scan() -> [StartupItem] {
        var items: [StartupItem] = []
        for (dir, scope) in directories() {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "plist" {
                if let item = parse(url: file, scope: scope) { items.append(item) }
            }
        }
        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func parse(url: URL, scope: StartupItem.Scope) -> StartupItem? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return StartupItem(label: url.deletingPathExtension().lastPathComponent, name: friendlyName(label: url.deletingPathExtension().lastPathComponent),
                               plistPath: url.path, program: nil, scope: scope, status: .unknown, runsAtLoad: false)
        }
        let label = (plist["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
        let disabled = (plist["Disabled"] as? Bool) ?? false
        let runsAtLoad = (plist["RunAtLoad"] as? Bool) ?? false
        return StartupItem(label: label, name: name(program: program, label: label), plistPath: url.path, program: program,
                           scope: scope, status: disabled ? .disabled : .enabled, runsAtLoad: runsAtLoad)
    }

    /// Çalıştırılan dosya bir `.app` içindeyse uygulamanın adı; yoksa etiketten türetilen kısa ad.
    static func name(program: String?, label: String) -> String {
        if let program, program.contains(".app/") {
            let app = AppNaming.outermostApp(of: program)
            return ((app as NSString).lastPathComponent as NSString).deletingPathExtension
        }
        return friendlyName(label: label)
    }

    static func friendlyName(label: String) -> String {
        let parts = label.split(separator: ".")
        guard parts.count > 2, let last = parts.last else { return label }
        return String(last)
    }
}
