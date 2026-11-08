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
    /// Oturum adı (`session_title`); yoksa nil.
    var title: String?
    /// Claude Code sürecinin son bilinen kimliği (hook üst süreci); eski betikle kurulmuş oturumlarda nil.
    var pid: Int32?
    /// `pid` sürecinin ilk görüldüğündeki başlangıç zamanı; sonradan değişirse pid başka bir sürece geçmiştir.
    var pidStartedAt: Date?
    /// Süreç ölü bulunup kapatıldıysa o an (olay gelmeden kapandığı için `lastEventAt` yerine bu bekleme için kullanılır).
    var exitedAt: Date?

    /// Panelde ana başlık: oturum adı, yoksa proje klasörü adı.
    var displayName: String { title ?? project }
    /// Ana başlık oturum adıyken ikincil satırda gösterilen proje adı.
    var secondaryName: String? { title == nil || project == "?" ? nil : project }

    var badge: AgentModelBadge { AgentModelBadge(modelID: model) }

    var workingCount: Int { (status.isWorking ? 1 : 0) + subagents.filter { $0.status.isWorking }.count }
}

/// Saf durum makinesi: olay → oturum ağacı. Zamanlayıcı/ağ yok; birim testlenir.
///
/// Varsayım (DOĞRULANMADI, testle belgelendi): alt ajan olaylarındaki `session_id` üst oturumunkiyle aynıdır.
/// Alt ajan içinden gelen araç olayları `agent_id` ile alt ajana, yoksa oturuma yazılır.
struct AgentState: Equatable, Sendable {
    /// Pid'i bilinmeyen, çalışıyor/izin bekliyor durumundaki oturum olay gelmezse bu süre sonra bayat sayılıp düşer.
    static let staleAfter: TimeInterval = 30 * 60
    /// Pid'i bilinmeyen, `bitti`/`boşta` durumundaki oturum için daha kısa bayatlama (SessionEnd gelmemiş olabilir).
    static let restingStaleAfter: TimeInterval = 10 * 60
    /// Kapanan oturum listede bu kadar kalır.
    static let endedLinger: TimeInterval = 60
    /// Süreç ölüdür diye kapatılan oturum listede bu kadar kalır.
    static let exitedLinger: TimeInterval = 10
    /// Süreç başlangıcı, o sürecin olayından bu kadar sonra çıkarsa pid yeniden kullanılmıştır (saat/ölçüm payı).
    static let pidReuseSlack: TimeInterval = 2

    private(set) var sessions: [String: AgentSession] = [:]
    /// Agent aracının sonucu, `SubagentStart` gelmeden önce geldiyse model burada bekler.
    private var pendingSubagentModels: [String: String] = [:]

    /// Başlangıç sırasına göre (en yeni üstte).
    var orderedSessions: [AgentSession] { sessions.values.sorted { ($0.startedAt, $0.id) > ($1.startedAt, $1.id) } }

    /// Çalışan ajan sayısı: çalışan oturumlar + çalışan alt ajanlar.
    var workingAgentCount: Int { sessions.values.reduce(0) { $0 + $1.workingCount } }

    var isEmpty: Bool { sessions.isEmpty }

    /// Canlılığı yoklanacak oturumlar: kapanmamış ve pid'i bilinen.
    var livenessTargets: [(sessionID: String, pid: Int32)] {
        sessions.values.compactMap { s in s.status != .ended ? s.pid.map { (s.id, $0) } : nil }
    }

    @discardableResult
    mutating func apply(_ e: AgentEvent, now: Date) -> Bool {
        guard let name = e.name else { return false }
        let hadSession = sessions[e.sessionID] != nil
        if name == .sessionStart {
            sessions[e.sessionID] = AgentSession(id: e.sessionID, project: e.project ?? "?", model: e.model, status: .idle,
                                                  startedAt: now, lastEventAt: now, title: e.sessionTitle, pid: e.pid)
            return true
        }
        // Adalmon oturum ortasında açıldıysa oturum ilk olayda oluşturulur.
        if !hadSession {
            if name == .sessionEnd { return false }
            sessions[e.sessionID] = AgentSession(id: e.sessionID, project: e.project ?? "?", model: e.model, status: .idle,
                                                  startedAt: now, lastEventAt: now, title: e.sessionTitle, pid: e.pid)
        }
        guard var s = sessions[e.sessionID] else { return false }
        s.lastEventAt = now
        if let project = e.project, s.project == "?" { s.project = project }
        if s.model == nil, let model = e.model { s.model = model }
        if let title = e.sessionTitle { s.title = title } // boş/yok gelirse mevcut ad kalır
        if let pid = e.pid, pid != s.pid { s.pid = pid; s.pidStartedAt = nil } // pid yoksa son bilinen kalır

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

    /// Oturumun listeden düşeceği an; düşmeyecekse nil. Kapalı oturum: kısa bekleme. Pid'i bilinen canlı oturum bayatlamaz
    /// (uzun düşünme/bekleme olabilir; ölürse canlılık yoklaması kapatır). Pid'siz: bitti/boşta 10 dk, çalışan 30 dk.
    private static func dueDate(_ s: AgentSession) -> Date? {
        if s.status == .ended {
            return s.exitedAt.map { $0.addingTimeInterval(exitedLinger) } ?? s.lastEventAt.addingTimeInterval(endedLinger)
        }
        if s.pid != nil { return nil }
        switch s.status {
        case .idle, .done: return s.lastEventAt.addingTimeInterval(restingStaleAfter)
        case .thinking, .tool, .waitingPermission: return s.lastEventAt.addingTimeInterval(staleAfter)
        case .ended: return nil
        }
    }

    /// Bayat ve süresi dolan kapalı oturumları listeden düşürür; düşen kimlikleri döndürür.
    @discardableResult
    mutating func prune(now: Date) -> [String] {
        let dropped = sessions.values.filter { s in Self.dueDate(s).map { now >= $0 } ?? false }.map(\.id)
        for id in dropped { sessions[id] = nil }
        if sessions.isEmpty { pendingSubagentModels = [:] }
        return dropped
    }

    /// Bir sonraki budama anı (olay yoksa hiçbir zamanlayıcı kurulmaz).
    func nextPruneDate() -> Date? {
        sessions.values.compactMap(Self.dueDate).min()
    }

    /// Pid'li oturumların süreçlerini yoklar; ölü ya da başka sürece geçmiş pid'in oturumunu (ve alt ajanlarını) kapatır.
    /// Süreç başlangıcı ilk görüldüğünde kaydedilir; sonradan değişirse (ya da süreç, olaylarından sonra başlamışsa) pid yeniden
    /// kullanılmıştır. Kapatılan oturum kimliklerini döndürür.
    @discardableResult
    mutating func applyLiveness(using probe: ProcessLivenessProbing, now: Date) -> [String] {
        var closed: [String] = []
        for target in livenessTargets {
            guard var s = sessions[target.sessionID] else { continue }
            var dead = false
            switch probe.probe(pid: target.pid) {
            case .dead:
                dead = true
            case .alive(let startedAt):
                if let startedAt {
                    if let known = s.pidStartedAt {
                        dead = abs(startedAt.timeIntervalSince(known)) > 1
                    } else if startedAt > s.lastEventAt.addingTimeInterval(Self.pidReuseSlack) {
                        dead = true // süreç, bu pid'li son olaydan sonra doğmuş: pid yeniden kullanılmış
                    } else {
                        s.pidStartedAt = startedAt
                    }
                }
            }
            if dead {
                s.status = .ended
                for i in s.subagents.indices { s.subagents[i].status = .ended }
                s.exitedAt = now
                closed.append(s.id)
            }
            sessions[s.id] = s
        }
        return closed
    }
}

/// Bir sürecin yoklama sonucu.
enum ProcessProbeResult: Equatable, Sendable {
    case dead
    /// Yaşıyor; başlangıç zamanı okunabildiyse (pid yeniden kullanımını yakalamak için) verilir.
    case alive(startedAt: Date?)
}

/// Süreç canlılığı; testlerde sahte süreç tablosu enjekte edilir.
protocol ProcessLivenessProbing: Sendable {
    func probe(pid: Int32) -> ProcessProbeResult
}
