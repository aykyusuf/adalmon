import Foundation

/// Ofis konuşma balonu metni (saf mantık): araç türü → Türkçe fiil, isteğe bağlı kısa hedef, kısaltma, süre.
/// Varsayılan yalnızca araç türünü söyler ("Dosya düzenliyor"); hedef (dosya adı / komut adı) yalnızca betik gönderdiyse
/// ("main.swift düzenliyor"). Metin en çok `maxLength` karakter, tek satırdır.
enum OfficeBubbleText {
    static let maxLength = 24
    /// Bilinmeyen araç adının üst sınırı (toplam metin yine `maxLength` ile kısaltılır).
    static let maxToolName = 18
    /// Ajan bu süre hiçbir olay göndermezse balon kaybolur.
    static let lifetime: TimeInterval = 10
    static let thinking = "Düşünüyor…"

    private enum Kind { case command, edit, read, search, web, agent }

    private static func kind(of tool: String) -> Kind? {
        switch tool {
        case "Bash": .command
        case "Edit", "Write", "MultiEdit", "NotebookEdit": .edit
        case "Read": .read
        case "Grep", "Glob": .search
        case "WebSearch", "WebFetch": .web
        case "Task", "Agent": .agent
        default: nil
        }
    }

    /// Balon metni; ajan çalışmıyorsa (boşta, bitti, izin bekliyor, kapandı) nil. Araç adı `activity`, yoksa durumun kendisinden gelir.
    static func text(status: AgentStatus, activity: String?, target: String?) -> String? {
        switch status {
        case .thinking: return thinking
        case .tool(let name):
            let tool = activity ?? name
            guard let kind = kind(of: tool) else {
                let shown = sanitizedToolName(tool)
                return shown.map { fit(prefix: $0, suffix: "kullanıyor") } ?? "Araç kullanıyor"
            }
            switch kind {
            case .command: return withTarget(target, verb: "çalıştırıyor", fallback: "Komut çalıştırıyor")
            case .edit: return withTarget(target, verb: "düzenliyor", fallback: "Dosya düzenliyor")
            case .read: return withTarget(target, verb: "okuyor", fallback: "Dosya okuyor")
            case .search: return "Arıyor"
            case .web: return "Web'de geziniyor"
            case .agent: return "Ajan çağırıyor"
            }
        case .waitingPermission, .idle, .done, .ended: return nil
        }
    }

    private static func withTarget(_ target: String?, verb: String, fallback: String) -> String {
        guard let target = target.flatMap(sanitizedTarget) else { return fallback }
        return fit(prefix: target, suffix: verb)
    }

    /// "<önek> <sonek>" en çok `maxLength` karakter: önek gerekirse "…" ile kısalır, sonek her zaman tam kalır.
    static func fit(prefix: String, suffix: String) -> String {
        let budget = maxLength - suffix.count - 1
        guard budget >= 1 else { return String(suffix.prefix(maxLength)) }
        let head = prefix.count <= budget ? prefix : String(prefix.prefix(max(1, budget - 1))) + "…"
        return "\(head) \(suffix)"
    }

    /// Bilinmeyen araç adı: MCP adlarında son bileşen, yalnızca [A-Za-z0-9_.:-], en çok 18 karakter; boş kalırsa nil.
    static func sanitizedToolName(_ raw: String) -> String? {
        var name = raw
        if name.hasPrefix("mcp__"), let last = name.components(separatedBy: "__").last { name = last }
        let kept = String(name.filter { $0.isASCII && ($0.isLetter || $0.isNumber || "_.:-".contains($0)) })
        return kept.isEmpty ? nil : String(kept.prefix(maxToolName))
    }

    /// Hedef (zaten betikte süzülmüş): tek satır, kontrol karakteri yok; boşsa nil.
    static func sanitizedTarget(_ raw: String) -> String? {
        let kept = raw.unicodeScalars.filter { $0.properties.generalCategory != .control }
        let text = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    /// `activityAt` yoksa (demo/statik) balon sönmez.
    static func isExpired(activityAt: Date?, now: Date) -> Bool {
        guard let activityAt else { return false }
        return now.timeIntervalSince(activityAt) >= lifetime
    }

    /// Balonun sönmesine kalan süre; süresiz ise nil, dolmuşsa 0.
    static func remaining(activityAt: Date?, now: Date) -> TimeInterval? {
        guard let activityAt else { return nil }
        return max(0, lifetime - now.timeIntervalSince(activityAt))
    }
}
