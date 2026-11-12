import Foundation

enum StartupItemScanner {
    static func directories(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [(url: URL, scope: StartupItem.Scope)] {
        [(home.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory), .user),
         (URL(filePath: "/Library/LaunchAgents", directoryHint: .isDirectory), .allUsers),
         (URL(filePath: "/Library/LaunchDaemons", directoryHint: .isDirectory), .daemon)]
    }

    /// Plist'leri okur ve `launchctl print-disabled` geçersiz kılmalarını uygular (dosya G/Ç + 2 kısa `launchctl` çağrısı; ana iş parçacığında çağırmayın).
    static func scan(launchctl: any LaunchctlRunning = SystemLaunchctl(), uid: uid_t = getuid(),
                     directories: [(url: URL, scope: StartupItem.Scope)] = directories()) async -> [StartupItem] {
        let guiOverrides = LaunchctlDisabledParser.parse(await launchctl.run(.printDisabled(.gui(uid: uid))).output)
        let systemOverrides = LaunchctlDisabledParser.parse(await launchctl.run(.printDisabled(.system)).output)
        return readPlists(in: directories).map {
            applying(overrides: $0.scope == .daemon ? systemOverrides : guiOverrides, to: $0)
        }
    }

    static func readPlists(in directories: [(url: URL, scope: StartupItem.Scope)]) -> [StartupItem] {
        var items: [StartupItem] = []
        for (dir, scope) in directories {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "plist" {
                if let item = parse(url: file, scope: scope) { items.append(item) }
            }
        }
        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func parse(url: URL, scope: StartupItem.Scope) -> StartupItem? {
        parse(data: try? Data(contentsOf: url), path: url.path, scope: scope)
    }

    /// Yol kesin olarak yok mu? Yalnızca ENOENT/ENOTDIR "yok" sayılır; izin hataları (ör. TCC korumalı klasörler) "bilinmiyor".
    static func isDefinitelyMissing(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) != 0 && (errno == ENOENT || errno == ENOTDIR)
    }

    /// Bozuk ajan tespiti (saf). Yanlış alarmı önlemek için: Apple/Adalmon etiketleri, `BundleProgram` (uygulama paketine göreli)
    /// ve göreli ya da `/Volumes` (takılı olmayabilir) yolları işaretlenmez.
    static func problem(label: String, plist: [String: Any], program: String?,
                        isMissing: (String) -> Bool = isDefinitelyMissing) -> StartupItem.Problem? {
        if StartupItemPermissions.protectedPrefixes.contains(where: { label.hasPrefix($0) }) { return nil }
        if plist["BundleProgram"] != nil { return nil }
        guard let program, !program.isEmpty else { return .noProgram }
        guard program.hasPrefix("/"), !program.hasPrefix("/Volumes/") else { return nil }
        return isMissing(program) ? .programMissing(program) : nil
    }

    /// Saf ayrıştırma: `data` nil/bozuksa etiket dosya adından alınır ve durum `.unknown` olur.
    static func parse(data: Data?, path: String, scope: StartupItem.Scope,
                      isMissing: (String) -> Bool = isDefinitelyMissing) -> StartupItem? {
        let fileLabel = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        guard let data,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return StartupItem(label: fileLabel, name: friendlyName(label: fileLabel), plistPath: path, program: nil,
                               scope: scope, status: .unknown, runsAtLoad: false)
        }
        let label = (plist["Label"] as? String) ?? fileLabel
        let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
        let disabled = (plist["Disabled"] as? Bool) ?? false
        let runsAtLoad = (plist["RunAtLoad"] as? Bool) ?? false
        return StartupItem(label: label, name: name(program: program, label: label), plistPath: path, program: program,
                           scope: scope, status: disabled ? .disabled : .enabled, runsAtLoad: runsAtLoad,
                           problem: problem(label: label, plist: plist, program: program, isMissing: isMissing))
    }

    /// launchd'nin geçersiz kılma veritabanı plist'teki `Disabled` anahtarından önceliklidir.
    static func applying(overrides: [String: Bool], to item: StartupItem) -> StartupItem {
        guard let disabled = overrides[item.label] else { return item }
        var copy = item
        copy.status = disabled ? .disabled : .enabled
        return copy
    }

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
