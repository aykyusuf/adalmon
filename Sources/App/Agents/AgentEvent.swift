import Foundation

/// Claude Code hook olayı (forward betiğinin süzdüğü izinli alanlar). İçerik alanları (prompt, tool_input, tool_response…)
/// bu türde YOKTUR; JSON'da gelseler bile okunmaz (`init(json:)` yalnızca izinli anahtarları alır).
struct AgentEvent: Equatable, Sendable {
    enum Name: String, Sendable, CaseIterable {
        case sessionStart = "SessionStart", sessionEnd = "SessionEnd", userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse", postToolUse = "PostToolUse", postToolUseFailure = "PostToolUseFailure"
        case permissionRequest = "PermissionRequest", notification = "Notification", stop = "Stop"
        case subagentStart = "SubagentStart", subagentStop = "SubagentStop", postModelSwitch = "PostModelSwitch"
    }

    /// Betiğin ilettiği tüm anahtarlar; başka anahtar asla okunmaz.
    static let allowedKeys: Set<String> = [
        "event", "session_id", "agent_id", "agent_type", "tool_name", "source", "model", "from_model", "to_model",
        "notification_type", "reason", "project", "permission_mode", "ts", "resolved_model", "resolved_agent_id", "session_title", "pid", "target",
    ]
    static let maxValueLength = 200

    /// `hook_event_name`; bilinmeyen olay adı da taşınır (reducer yok sayar).
    var event: String
    var sessionID: String
    var agentID: String?
    var agentType: String?
    var toolName: String?
    var source: String?
    var model: String?
    var fromModel: String?
    var toModel: String?
    var notificationType: String?
    var reason: String?
    var project: String?
    var permissionMode: String?
    var timestamp: Date?
    /// Agent/Task aracının PostToolUse yanıtından yalnızca `resolvedModel` ve `agentId`.
    var resolvedModel: String?
    var resolvedAgentID: String?
    /// Oturum adı (`/rename` ya da otomatik başlık); kontrol karakterleri temizlenmiş, en çok `maxValueLength` karakter.
    var sessionTitle: String?
    /// Hook komutunun üst süreci (Claude Code); canlılık yoklaması içindir. Yalnızca doğrulanmış tamsayı (>1), yoksa nil.
    var pid: Int32?
    /// PreToolUse için isteğe bağlı kısa hedef (yalnızca "Hedefi de göster" açıkken betik ekler): dosya adı ya da komutun ilk kelimesi.
    /// Kontrol karakterleri atılmış, en çok `maxTargetLength` karakter; içerik/argüman/yol asla.
    var target: String?

    var name: Name? { Name(rawValue: event) }

    init(event: String, sessionID: String, agentID: String? = nil, agentType: String? = nil, toolName: String? = nil,
         source: String? = nil, model: String? = nil, fromModel: String? = nil, toModel: String? = nil,
         notificationType: String? = nil, reason: String? = nil, project: String? = nil, permissionMode: String? = nil,
         timestamp: Date? = nil, resolvedModel: String? = nil, resolvedAgentID: String? = nil, sessionTitle: String? = nil,
         pid: Int32? = nil, target: String? = nil) {
        self.event = event
        self.sessionID = sessionID
        self.agentID = agentID
        self.agentType = agentType
        self.toolName = toolName
        self.source = source
        self.model = model
        self.fromModel = fromModel
        self.toModel = toModel
        self.notificationType = notificationType
        self.reason = reason
        self.project = project
        self.permissionMode = permissionMode
        self.timestamp = timestamp
        self.resolvedModel = resolvedModel
        self.resolvedAgentID = resolvedAgentID
        self.sessionTitle = sessionTitle.flatMap(Self.cleanTitle)
        self.pid = pid.flatMap { $0 > 1 ? $0 : nil }
        self.target = target.flatMap(Self.cleanTarget)
    }

    static let maxTargetLength = 40

    /// Hedef: kontrol karakterleri atılır (boşluğa çevrilmez), uçlar kırpılır, kısaltılır; boş kalırsa nil.
    static func cleanTarget(_ value: String) -> String? {
        let kept = String(String.UnicodeScalarView(value.unicodeScalars.filter { $0.properties.generalCategory != .control }))
        let trimmed = kept.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxTargetLength))
    }

    /// JSON'dan süreç kimliği: yalnızca tamsayı sayı (dize/ondalık/bool değil), Int32 aralığında ve >1.
    static func parsePID(_ value: Any?) -> Int32? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              !CFNumberIsFloatType(number), let pid = Int32(exactly: number.int64Value), pid > 1 else { return nil }
        return pid
    }

    /// Kontrol karakterlerini boşluğa çevirir, boşlukları sadeleştirir ve kısaltır; boş kalırsa nil.
    static func cleanTitle(_ value: String) -> String? {
        let mapped = String(String.UnicodeScalarView(value.unicodeScalars.map { $0.properties.generalCategory == .control ? " " : $0 }))
        let collapsed = mapped.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.isEmpty ? nil : String(collapsed.prefix(maxValueLength))
    }

    /// Güvenilmeyen JSON gövdesinden olay. `nil` = geçersiz (nesne değil, olay adı ya da oturum kimliği yok).
    init?(json data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func string(_ key: String) -> String? {
            guard Self.allowedKeys.contains(key), let value = object[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(Self.maxValueLength))
        }
        func allowed(_ key: String) -> Any? { Self.allowedKeys.contains(key) ? object[key] : nil }
        guard let event = string("event"), let session = string("session_id") else { return nil }
        self.init(event: event, sessionID: session, agentID: string("agent_id"), agentType: string("agent_type"),
                  toolName: string("tool_name"), source: string("source"), model: string("model"),
                  fromModel: string("from_model"), toModel: string("to_model"), notificationType: string("notification_type"),
                  reason: string("reason"), project: string("project"), permissionMode: string("permission_mode"),
                  timestamp: (object["ts"] as? Double).map { Date(timeIntervalSince1970: $0) },
                  resolvedModel: string("resolved_model"), resolvedAgentID: string("resolved_agent_id"),
                  sessionTitle: object["session_title"] as? String, pid: allowed("pid").flatMap(Self.parsePID),
                  target: object["target"] as? String)
    }
}
