import Foundation

/// OFFICE-CTRL-01: ofisten cevaplanan Claude Code istekleri (izin ve AskUserQuestion). İçerik (araç girdisi özeti, soru metni,
/// seçenekler, öneri metni) YALNIZCA bu türlerde ve `PendingDecisionStore` belleğinde yaşar; `AgentEvent`, `/v1/state`, SSE, web
/// görüntüsü ve loglara ASLA girmez.

enum DecisionKind: String, Sendable {
    case permission, question
}

/// "İzin ver" ile birlikte seçilebilen mod. `bypassPermissions` (ve auto/dontAsk) bilerek YOKTUR; betik de reddeder.
enum DecisionPermissionMode: String, CaseIterable, Sendable, Identifiable {
    case `default` = "default", acceptEdits, plan
    var id: String { rawValue }
    var title: String {
        switch self {
        case .default: "Varsayılan"
        case .acceptEdits: "Düzenlemeleri kabul et"
        case .plan: "Plan"
        }
    }
}

/// "Hep izin ver" kapsamı: `user` = Claude Code `userSettings` (kalıcı, Claude Code kendisi yazar), `session` = yalnız bu oturum.
enum DecisionScope: String, Sendable {
    case user, session
}

/// Hook girdisindeki `permission_suggestions` öğesinin okunur özeti. `index` özgün listedeki konumdur (betik geri eşler).
struct DecisionSuggestion: Equatable, Sendable, Identifiable {
    var index: Int
    var label: String
    var id: Int { index }
}

struct DecisionQuestion: Equatable, Sendable {
    struct Option: Equatable, Sendable {
        var label: String
        var description: String?
    }
    var question: String
    var header: String?
    var multiSelect: Bool
    var options: [Option]
}

/// Sıkı sınırlar (güvenilmeyen girdi).
enum DecisionLimits {
    static let maxPreview = 1500
    static let maxLabel = 200
    static let maxQuestion = 500
    static let maxDescription = 300
    static let maxHeader = 60
    static let maxSuggestions = 6
    static let maxQuestions = 4
    static let maxOptions = 8
    /// Hook zaman aşımı 600 sn; betik bunun altında kalır.
    static let maxHold: TimeInterval = 590
    static let maxIdentifier = 200
}

/// `POST /v1/decision` gövdesi (decide.py → Adalmon). Anahtarlar beyaz listelidir; bilinmeyenler okunmaz.
struct DecisionRequest: Equatable, Sendable {
    var kind: DecisionKind
    var sessionID: String
    var agentID: String?
    var agentType: String?
    var toolName: String
    var permissionMode: String?
    var project: String?
    var promptID: String?
    var inputHash: String?
    var timestamp: Date?
    var hold: TimeInterval
    var preview: String?
    var suggestions: [DecisionSuggestion]
    var questions: [DecisionQuestion]

    /// Betiğin gönderdiği anahtarların tümü.
    static let allowedKeys: Set<String> = [
        "kind", "session_id", "agent_id", "agent_type", "tool_name", "permission_mode", "project", "prompt_id", "input_hash",
        "ts", "hold", "preview", "suggestions", "questions",
    ]

    init(kind: DecisionKind, sessionID: String, agentID: String? = nil, agentType: String? = nil, toolName: String,
         permissionMode: String? = nil, project: String? = nil, promptID: String? = nil, inputHash: String? = nil,
         timestamp: Date? = nil, hold: TimeInterval = DecisionLimits.maxHold, preview: String? = nil,
         suggestions: [DecisionSuggestion] = [], questions: [DecisionQuestion] = []) {
        self.kind = kind
        self.sessionID = sessionID
        self.agentID = agentID
        self.agentType = agentType
        self.toolName = toolName
        self.permissionMode = permissionMode
        self.project = project
        self.promptID = promptID
        self.inputHash = inputHash
        self.timestamp = timestamp
        self.hold = min(DecisionLimits.maxHold, max(1, hold))
        self.preview = preview
        self.suggestions = suggestions
        self.questions = questions
    }

    /// Kontrol karakterleri (satır sonu ve sekme hariç) atılır, uçlar kırpılır, kısaltılır; boş kalırsa nil.
    /// decide.py `clean` ile BİREBİR aynı kural (cevap anahtarları eşleşsin): Python `str.strip()` boşlukları ve Unicode kod noktası
    /// sayısına göre kısaltma (Swift `Character` kümesine göre değil).
    static func clean(_ value: Any?, max: Int, multiline: Bool = false) -> String? {
        guard let text = value as? String else { return nil }
        var scalars = Array(text.unicodeScalars.filter { scalar in
            if scalar.properties.generalCategory == .control { return multiline && (scalar == "\n" || scalar == "\t") }
            return true
        })
        while let last = scalars.last, isPythonSpace(last) { scalars.removeLast() }
        let start = scalars.firstIndex { !isPythonSpace($0) } ?? scalars.endIndex
        let kept = scalars[start...]
        if kept.isEmpty { return nil }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: kept.prefix(max))
        return String(result)
    }

    /// Python `str.isspace()`: Zs/Zl/Zp ve \t \n \v \f \r, U+001C–U+001F, U+0085 (kontrol olanlar zaten atılmıştır).
    private static func isPythonSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator: return true
        default: return (9...13).contains(scalar.value) || (0x1C...0x1F).contains(scalar.value) || scalar.value == 0x85
        }
    }

    /// Güvenilmeyen JSON. nil = geçersiz (nesne değil, tür/oturum/araç yok; soru türünde geçerli soru yok).
    init?(json data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kindText = Self.clean(object["kind"], max: 20), let kind = DecisionKind(rawValue: kindText),
              let session = Self.clean(object["session_id"], max: DecisionLimits.maxIdentifier),
              let tool = Self.clean(object["tool_name"], max: DecisionLimits.maxIdentifier) else { return nil }
        func id(_ key: String) -> String? { Self.clean(object[key], max: DecisionLimits.maxIdentifier) }
        var suggestions: [DecisionSuggestion] = []
        for case let item as [String: Any] in (object["suggestions"] as? [Any] ?? []).prefix(DecisionLimits.maxSuggestions) {
            guard let index = (item["index"] as? NSNumber).flatMap({ CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : Int(exactly: $0.int64Value) }),
                  index >= 0, index < 1000, let label = Self.clean(item["label"], max: DecisionLimits.maxLabel),
                  !suggestions.contains(where: { $0.index == index }) else { continue }
            suggestions.append(DecisionSuggestion(index: index, label: label))
        }
        var questions: [DecisionQuestion] = []
        for case let item as [String: Any] in (object["questions"] as? [Any] ?? []).prefix(DecisionLimits.maxQuestions) {
            guard let text = Self.clean(item["question"], max: DecisionLimits.maxQuestion) else { continue }
            var options: [DecisionQuestion.Option] = []
            for case let option as [String: Any] in (item["options"] as? [Any] ?? []).prefix(DecisionLimits.maxOptions) {
                guard let label = Self.clean(option["label"], max: DecisionLimits.maxLabel),
                      !options.contains(where: { $0.label == label }) else { continue }
                options.append(.init(label: label, description: Self.clean(option["description"], max: DecisionLimits.maxDescription)))
            }
            guard !options.isEmpty else { continue }
            questions.append(DecisionQuestion(question: text, header: Self.clean(item["header"], max: DecisionLimits.maxHeader),
                                              multiSelect: (item["multiSelect"] as? Bool) == true, options: options))
        }
        if kind == .question, questions.isEmpty { return nil }
        let hold = (object["hold"] as? NSNumber).map(\.doubleValue) ?? DecisionLimits.maxHold
        self.init(kind: kind, sessionID: session, agentID: id("agent_id"), agentType: id("agent_type"), toolName: tool,
                  permissionMode: id("permission_mode"), project: id("project"), promptID: id("prompt_id"), inputHash: id("input_hash"),
                  timestamp: (object["ts"] as? Double).map { Date(timeIntervalSince1970: $0) }, hold: hold.isFinite ? hold : DecisionLimits.maxHold,
                  preview: kind == .permission ? Self.clean(object["preview"], max: DecisionLimits.maxPreview, multiline: true) : nil,
                  suggestions: kind == .permission ? suggestions : [], questions: kind == .question ? questions : [])
    }
}

/// Ofiste bekleyen karar. Yalnızca bellekte yaşar.
struct PendingDecision: Equatable, Identifiable, Sendable {
    let id: UUID
    let request: DecisionRequest
    let receivedAt: Date
    let deadline: Date

    init(id: UUID = UUID(), request: DecisionRequest, receivedAt: Date = .now) {
        self.id = id
        self.request = request
        self.receivedAt = receivedAt
        self.deadline = receivedAt.addingTimeInterval(request.hold)
    }

    var sessionID: String { request.sessionID }
    var agentID: String? { request.agentID }
    /// Ofis üyesi kimliği (`OfficeMember.members(from:)` ile aynı biçim).
    var memberID: String { request.agentID.map { "\(request.sessionID)#\($0)" } ?? request.sessionID }
}

/// Kullanıcının tıklamasının sonucu.
enum DecisionVerdict: Equatable, Sendable {
    case allow(suggestion: Int? = nil, scope: DecisionScope = .session, mode: DecisionPermissionMode? = nil)
    case deny
    /// Soru cevapları: soru metni → seçilen etiketler (tek seçimde bir etiket).
    case answer([String: [String]])
    /// Karar terminalde verilsin (bekleyen bağlantı bırakılır).
    case release

    /// Denetim kaydı için kısa ad (içerik yok).
    var auditName: String {
        switch self {
        case .allow: "allow"
        case .deny: "deny"
        case .answer: "answer"
        case .release: "release"
        }
    }

    /// decide.py'nin okuduğu yanıt gövdesi; `release` için nil (204 gider, betik sessiz çıkar).
    var wireJSON: Data? {
        var object: [String: Any]
        switch self {
        case .allow(let suggestion, let scope, let mode):
            object = ["verdict": "allow", "scope": scope.rawValue]
            if let suggestion { object["suggestion"] = suggestion }
            if let mode { object["mode"] = mode.rawValue }
        case .deny:
            object = ["verdict": "deny"]
        case .answer(let answers):
            object = ["verdict": "answer", "answers": answers]
        case .release:
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
