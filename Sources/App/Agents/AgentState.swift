import Foundation

/// Model adı → rozet (claude-opus-*, claude-sonnet-*, claude-haiku-*, claude-fable-*).
enum AgentModelBadge: String, Equatable, Sendable, CaseIterable {
    case opus, sonnet, haiku, fable, unknown

    init(modelID: String?) {
        let id = modelID?.lowercased() ?? ""
        if id.contains("opus") { self = .opus } else if id.contains("sonnet") { self = .sonnet } else if id.contains("haiku") { self = .haiku }
        else if id.contains("fable") { self = .fable } else { self = .unknown }
    }

    var label: String {
        switch self {
        case .opus: "Opus"
        case .sonnet: "Sonnet"
        case .haiku: "Haiku"
        case .fable: "Fable"
        case .unknown: "bilinmiyor"
        }
    }
}

enum AgentStatus: Equatable, Sendable {
    case thinking
    case tool(String)
    case waitingPermission
    case idle
    case done
    case ended

    /// Çalışıyor sayılan durumlar (menü çubuğu sayacı).
    var isWorking: Bool {
        switch self {
        case .thinking, .tool, .waitingPermission: true
        case .idle, .done, .ended: false
        }
    }

    var label: String {
        switch self {
        case .thinking: "düşünüyor"
        case .tool(let name): name
        case .waitingPermission: "izin bekliyor"
        case .idle: "boşta"
        case .done: "bitti"
        case .ended: "kapandı"
        }
    }
}

struct AgentSubagent: Equatable, Identifiable, Sendable {
    var agentID: String
    var agentType: String
    var model: String?
    var status: AgentStatus
    var id: String { agentID }
}

struct AgentSession: Equatable, Identifiable, Sendable {
    var id: String
    var project: String
    var model: String?
    var status: AgentStatus
    var startedAt: Date
    var lastEventAt: Date
    var subagents: [AgentSubagent] = []

    var badge: AgentModelBadge { AgentModelBadge(modelID: model) }

    var workingCount: Int { (status.isWorking ? 1 : 0) + subagents.filter { $0.status.isWorking }.count }
}

/// Saf durum makinesi: olay → oturum ağacı. Zamanlayıcı/ağ yok; birim testlenir.
///
/// Varsayım (DOĞRULANMADI, testle belgelendi): alt ajan olaylarındaki `session_id` üst oturumunkiyle aynıdır.
/// Alt ajan içinden gelen araç olayları `agent_id` ile alt ajana, yoksa oturuma yazılır.
struct AgentState: Equatable, Sendable {
    /// Olay gelmeyen oturum bu süre sonra bayat sayılıp listeden düşer.
    static let staleAfter: TimeInterval = 30 * 60
    /// Kapanan oturum listede bu kadar kalır.
    static let endedLinger: TimeInterval = 60

    private(set) var sessions: [String: AgentSession] = [:]
    /// Agent aracının sonucu, `SubagentStart` gelmeden önce geldiyse model burada bekler.
    private var pendingSubagentModels: [String: String] = [:]

    /// Başlangıç sırasına göre (en yeni üstte).
    var orderedSessions: [AgentSession] { sessions.values.sorted { ($0.startedAt, $0.id) > ($1.startedAt, $1.id) } }

    /// Çalışan ajan sayısı: çalışan oturumlar + çalışan alt ajanlar.
    var workingAgentCount: Int { sessions.values.reduce(0) { $0 + $1.workingCount } }

    var isEmpty: Bool { sessions.isEmpty }

    @discardableResult
    mutating func apply(_ e: AgentEvent, now: Date) -> Bool {
        guard let name = e.name else { return false }
        let hadSession = sessions[e.sessionID] != nil
        if name == .sessionStart {
            sessions[e.sessionID] = AgentSession(id: e.sessionID, project: e.project ?? "?", model: e.model, status: .idle,
                                                  startedAt: now, lastEventAt: now)
            return true
        }
        // Adalmon oturum ortasında açıldıysa oturum ilk olayda oluşturulur.
        if !hadSession {
            if name == .sessionEnd { return false }
            sessions[e.sessionID] = AgentSession(id: e.sessionID, project: e.project ?? "?", model: e.model, status: .idle,
                                                  startedAt: now, lastEventAt: now)
        }
        guard var s = sessions[e.sessionID] else { return false }
        s.lastEventAt = now
        if let project = e.project, s.project == "?" { s.project = project }
        if s.model == nil, let model = e.model { s.model = model }

        switch name {
        case .sessionStart: break
        case .sessionEnd:
            s.status = .ended
            for i in s.subagents.indices { s.subagents[i].status = .ended }
        case .userPromptSubmit:
            s.subagents.removeAll { $0.status == .done || $0.status == .ended }
            s.status = .thinking
        case .preToolUse:
            Self.setStatus(.tool(e.toolName ?? "araç"), for: e.agentID, in: &s)
        case .postToolUse, .postToolUseFailure:
            Self.setStatus(.thinking, for: e.agentID, in: &s)
            if let id = e.resolvedAgentID, let model = e.resolvedModel {
                if let i = s.subagents.firstIndex(where: { $0.agentID == id }) { s.subagents[i].model = model } else {
                    pendingSubagentModels[id] = model
                }
            }
        case .permissionRequest:
            Self.setStatus(.waitingPermission, for: e.agentID, in: &s)
        case .notification:
            switch e.notificationType {
            case "permission_prompt": s.status = .waitingPermission
            case "idle_prompt": s.status = .idle
            default: break
            }
        case .stop:
            if let id = e.agentID, s.subagents.contains(where: { $0.agentID == id }) { break } // alt ajanın Stop'u oturumu bitirmez
            s.status = .done
        case .subagentStart:
            // agent_type boş olan iç/yardımcı ajanlar listelenmez.
            guard let id = e.agentID, let type = e.agentType else { break }
            if !s.subagents.contains(where: { $0.agentID == id }) {
                s.subagents.append(AgentSubagent(agentID: id, agentType: type, model: pendingSubagentModels.removeValue(forKey: id) ?? e.model,
                                                 status: .thinking))
            }
        case .subagentStop:
            guard let id = e.agentID, e.agentType != nil, let i = s.subagents.firstIndex(where: { $0.agentID == id }) else { break }
            s.subagents[i].status = .done
        case .postModelSwitch:
            if let model = e.toModel { s.model = model }
        }
        sessions[e.sessionID] = s
        return true
    }

    private static func setStatus(_ status: AgentStatus, for agentID: String?, in s: inout AgentSession) {
        if let id = agentID, let i = s.subagents.firstIndex(where: { $0.agentID == id }) {
            if s.subagents[i].status != .done, s.subagents[i].status != .ended { s.subagents[i].status = status }
        } else if s.status != .ended {
            s.status = status
        }
    }

    /// Bayat ve süresi dolan kapalı oturumları listeden düşürür; düşen kimlikleri döndürür.
    @discardableResult
    mutating func prune(now: Date) -> [String] {
        let dropped = sessions.values.filter { s in
            let age = now.timeIntervalSince(s.lastEventAt)
            return s.status == .ended ? age >= Self.endedLinger : age >= Self.staleAfter
        }.map(\.id)
        for id in dropped { sessions[id] = nil }
        if sessions.isEmpty { pendingSubagentModels = [:] }
        return dropped
    }

    /// Bir sonraki budama anı (olay yoksa hiçbir zamanlayıcı kurulmaz).
    func nextPruneDate() -> Date? {
        sessions.values.map { $0.lastEventAt.addingTimeInterval($0.status == .ended ? Self.endedLinger : Self.staleAfter) }.min()
    }
}
