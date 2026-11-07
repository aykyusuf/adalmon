import Foundation

/// `sfltool dumpbtm` çıktısından mevcut kullanıcının modern giriş öğelerini çıkarır (saf).
/// Yalnızca `login item` ve `agent` türleri alınır; `legacy agent` zaten LaunchAgents listesinde, `com.apple.` öğeleri hariç tutulur.
enum BackgroundItemParser {
    static func parse(_ text: String, uid: uid_t) -> [BackgroundItem] {
        let records = records(in: section(of: text, uid: uid))
        var namesByIdentifier: [String: String] = [:]
        for record in records {
            if let id = record["Identifier"], let name = record["Name"] { namesByIdentifier[id] = name }
        }
        var items: [BackgroundItem] = []
        for record in records {
            guard let kind = kind(of: record["Type"]),
                  let identifier = record["Identifier"], let ownName = record["Name"] else { continue }
            let bundleID = record["Bundle Identifier"] ?? identifier.replacing(/^\d+\./, with: "")
            if bundleID.hasPrefix("com.apple.") { continue }
            let parentName = record["Parent Identifier"].flatMap { namesByIdentifier[$0] }
            let hasDistinctParent = parentName != nil && parentName != ownName
            items.append(BackgroundItem(
                id: record["UUID"] ?? identifier,
                name: hasDistinctParent ? parentName! : ownName,
                detail: hasDistinctParent ? ownName : nil,
                developer: record["Developer Name"],
                identifier: bundleID,
                kind: kind,
                isEnabled: isEnabled(record["Disposition"])))
        }
        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: İç ayrıştırma

    private static func section(of text: String, uid: uid_t) -> [Substring] {
        var lines: [Substring] = []
        var inside = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.contains("Records for UID ") {
                inside = line.contains("Records for UID \(uid) :")
                continue
            }
            if inside { lines.append(line) }
        }
        return lines
    }

    /// `#N:` başlıklı bloklar; her blok ilk düzey `Anahtar: değer` satırlarından oluşan sözlük.
    private static func records(in lines: [Substring]) -> [[String: String]] {
        var records: [[String: String]] = []
        var current: [String: String]?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.wholeMatch(of: /#\d+:/) != nil {
                if let current { records.append(current) }
                current = [:]
                continue
            }
            guard current != nil, let colon = trimmed.range(of: ": ") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colon.lowerBound])
            if key.hasPrefix("#") || current?[key] != nil { continue }
            let value = trimmed[colon.upperBound...].trimmingCharacters(in: .whitespaces)
            if value != "(null)" { current?[key] = value }
        }
        if let current { records.append(current) }
        return records
    }

    private static func kind(of type: String?) -> BackgroundItem.Kind? {
        guard let type else { return nil }
        let name = type.replacing(/\s*\(0x[0-9a-fA-F]+\)\s*$/, with: "")
        switch name {
        case "login item": return .loginItem
        case "agent": return .agent
        default: return nil
        }
    }

    private static func isEnabled(_ disposition: String?) -> Bool {
        guard let disposition, let open = disposition.firstIndex(of: "["), let close = disposition.firstIndex(of: "]") else { return false }
        let tokens = disposition[disposition.index(after: open)..<close].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return tokens.contains("enabled")
    }
}
