import Foundation

/// Sistem Ayarları'nda hangi ekran koruyucunun seçili olduğunu SALT OKUNUR öğrenir:
/// `defaults -currentHost read com.apple.screensaver moduleDict`. Hiçbir şey yazılmaz.
enum SaverSystemSelection {
    struct Module: Equatable, Sendable {
        var name: String?
        var path: String?
    }

    /// `defaults` çıktısını (eski tarz plist metni) ayrıştırır. Anahtar yoksa `nil`.
    static func parse(_ output: String) -> Module? {
        func value(_ key: String) -> String? {
            for raw in output.split(whereSeparator: \.isNewline) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix(key), let eq = line.firstIndex(of: "=") else { continue }
                guard line.dropFirst(key.count).trimmingCharacters(in: .whitespaces).hasPrefix("=") else { continue }
                var v = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if v.hasSuffix(";") { v.removeLast() }
                return v.trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespaces))
            }
            return nil
        }
        let module = Module(name: value("moduleName"), path: value("path"))
        return module.name == nil && module.path == nil ? nil : module
    }

    /// Seçili modül bizim paketimiz mi?
    static func isOurs(_ module: Module?) -> Bool {
        guard let module else { return false }
        if let path = module.path, path.hasSuffix("/\(SaverPaths.bundleName)") { return true }
        return module.name == SaverStatusLine.displayName
    }

    /// Gerçek sorgu (arka planda çağırın; ~10 ms). `nil` = komut çalıştırılamadı; anahtar yoksa (hiç özel seçim yok) `false`.
    /// Testte çağrılmaz.
    static func isOursSelected() -> Bool? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/defaults")
        process.arguments = ["-currentHost", "read", "com.apple.screensaver", "moduleDict"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return false }
        return isOurs(parse(String(data: data, encoding: .utf8) ?? ""))
    }
}
