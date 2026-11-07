import Foundation

/// `launchctl print-disabled <domain>` çıktısını ayrıştırır.
/// Satır biçimi: `"etiket" => enabled|disabled` (eski sürümlerde `true|false`). Sonuç: etiket → devre dışı mı.
enum LaunchctlDisabledParser {
    static func parse(_ output: String) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("\""), let arrow = line.range(of: "=>") else { continue }
            let key = line[line.startIndex..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
            guard key.count >= 2, key.hasPrefix("\""), key.hasSuffix("\"") else { continue }
            let label = String(key.dropFirst().dropLast())
            let value = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces).lowercased()
            switch value {
            case "disabled", "true": result[label] = true
            case "enabled", "false": result[label] = false
            default: continue
            }
        }
        return result
    }
}
