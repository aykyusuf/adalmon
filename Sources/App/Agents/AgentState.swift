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

    /// Araç adı → okunur Türkçe durum. Yalnızca araç adı kullanılır (komut/argüman/içerik asla); MCP: "<sunucu> aracı".
    static func toolLabel(_ raw: String) -> String {
        switch raw {
        case "Bash": return "Komut çalıştırıyor"
        case "Read": return "Dosya okuyor"
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return "Dosya düzenliyor"
        case "Grep", "Glob": return "Arama yapıyor"
        case "WebFetch", "WebSearch": return "Web'e bakıyor"
        case "Agent", "Task": return "Alt ajan başlatıyor"
        case "AskUserQuestion": return "Soru soruyor"
        default: break
        }
        if raw.hasPrefix("mcp__") {
            let parts = raw.components(separatedBy: "__")
            if parts.count >= 2, let server = OfficeBubbleText.sanitizedToolName(parts[1]) { return "\(server) aracı" }
        }
        return OfficeBubbleText.sanitizedToolName(raw).map { "Araç: \($0)" } ?? "Araç kullanıyor"
    }

    var label: String {
        switch self {
        case .thinking: "düşünüyor"
        case .tool(let name): Self.toolLabel(name)
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
    /// Çalışılan aracın adı (PreToolUse; araç bitince/başka olayda nil) ve isteğe bağlı kısa hedefi (dosya adı / komut adı).
    var activity: String?
    var target: String?
    /// Bu ajanın kendi son etkinlik olayı (konuşma balonu süresi için); alt ajan olayı üst oturumunkini etkilemez.
    var activityAt: Date?
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
    /// Ana ajanın çalıştığı araç adı ve isteğe bağlı kısa hedefi (bkz. `AgentSubagent`).
    var activity: String?
    var target: String?
    var activityAt: Date?
    /// Oturumun başlattığı ve hâlâ çalışan komutlar (süreç ağacından; yalnızca gözlemci varken örneklenir).
    var shells: SessionShells = .empty
    /// Süreç taramasıyla bulunmuş, henüz hiç olay göndermemiş "bekleyen" oturum (kimlik `discovered-<pid>`). İlk gerçek olayda yerini alır.
    var discovered = false
    /// Bitmiş (SubagentStop) ya da listeden düşmüş alt ajan kimlikleri: sonradan gelen olay bunları yeniden eklemez.
    var retiredAgents: [String] = []

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
    /// Alt ajan bu süre hiçbir olay göndermediyse (kapanış olayı kaçırılmış olabilir) listeden düşer. Arka plan ajanları uzun
    /// düşünebilir; bu yüzden uzun tutulur.
    static let subagentStaleAfter: TimeInterval = 45 * 60
    /// Çalışıyor görünen ama olay da transkript değişimi de bu süre gelmeyen oturum takılı sayılıp boşta işaretlenir (kapanış olayı
    /// kaçırılmış olabilir). Uzun süren tek bir araç da bu kadar sessiz kalabilir; sonraki olay durumu yine düzeltir.
    static let stuckWorkingAfter: TimeInterval = 20 * 60
    /// Oturum başına hatırlanan bitmiş alt ajan sayısı (geç gelen olay bitmiş ajanı hortlatmasın).
    static let retiredLimit = 64

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
        removeDiscoveredPlaceholder(matching: e)
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
            s.shells = .empty
            for i in s.subagents.indices { s.subagents[i].status = .ended }
        case .userPromptSubmit:
            s.subagents.removeAll { $0.status == .done || $0.status == .ended }
            s.status = .thinking
            s.activity = nil; s.target = nil; s.activityAt = now
        case .preToolUse:
            Self.adoptIfUnknown(e, in: &s, now: now)
            Self.setStatus(.tool(e.toolName ?? "araç"), activity: e.toolName, target: e.target, for: e.agentID, in: &s, now: now)
        case .postToolUse, .postToolUseFailure:
            Self.adoptIfUnknown(e, in: &s, now: now)
            Self.setStatus(.thinking, for: e.agentID, in: &s, now: now)
            if let id = e.resolvedAgentID, let model = e.resolvedModel {
                if let i = s.subagents.firstIndex(where: { $0.agentID == id }) { s.subagents[i].model = model } else {
                    pendingSubagentModels[id] = model
                }
            }
        case .permissionRequest:
            Self.adoptIfUnknown(e, in: &s, now: now)
            Self.setStatus(.waitingPermission, for: e.agentID, in: &s, now: now)
        case .notification:
            switch e.notificationType {
            case "permission_prompt": s.status = .waitingPermission; s.activity = nil; s.target = nil
            case "idle_prompt": s.status = .idle; s.activity = nil; s.target = nil
            default: break
            }
        case .stop:
            if let id = e.agentID, s.subagents.contains(where: { $0.agentID == id }) { break } // alt ajanın Stop'u oturumu bitirmez
            s.status = .done
            s.activity = nil; s.target = nil
        case .subagentStart:
            // agent_type boş olan iç/yardımcı ajanlar listelenmez.
            guard let id = e.agentID, let type = e.agentType else { break }
            if !s.subagents.contains(where: { $0.agentID == id }) {
                s.retiredAgents.removeAll { $0 == id }   // aynı kimlikle yeniden başlatıldıysa canlı
                s.subagents.append(AgentSubagent(agentID: id, agentType: type, model: pendingSubagentModels.removeValue(forKey: id) ?? e.model,
                                                 status: .thinking, activityAt: now))
            }
        case .subagentStop:
            guard let id = e.agentID, e.agentType != nil, let i = s.subagents.firstIndex(where: { $0.agentID == id }) else { break }
            s.subagents[i].status = .done
            s.subagents[i].activity = nil; s.subagents[i].target = nil
            Self.retire(id, in: &s)
        case .postModelSwitch:
            if let model = e.toModel { s.model = model }
        }
        sessions[e.sessionID] = s
        return true
    }

    /// Taramayla bulunan bekleyen oturumları uzlaştırır:
    /// - pid'i bilinen hiçbir gerçek oturumda olmayan Claude süreci için yer tutucu oluşturur (son etkinlik transkriptten);
    /// - artık bulunmayan (kapanmış ya da durdurulmuş) sürecin yer tutucusunu kaldırır;
    /// - mevcut yer tutucunun son etkinliğini ilerletir (boşta süresi doğru hesaplansın).
    /// Bir şey değiştiyse true.
    @discardableResult
    mutating func discoverSessions(_ found: [ClaudeProcessDiscovery.Found], now: Date) -> Bool {
        var changed = false
        let foundPIDs = Set(found.map(\.pid))
        for (id, s) in sessions where s.discovered {
            guard let pid = s.pid, foundPIDs.contains(pid) else { sessions[id] = nil; changed = true; continue }
        }
        // Gerçek (olay almış) oturumlar: transkript etkinliği ile uzlaştır.
        let byPID = Dictionary(found.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, original) in sessions where !original.discovered && original.status != .ended {
            guard let pid = original.pid, let la = byPID[pid]?.lastActivity.map({ min($0, now) }) else { continue }
            var s = original
            switch s.status {
            case .idle, .done:
                // Olay gelmedi ama transkript ilerledi: oturum aslında etkin; boşta sayılıp yanlışlıkla küçültülmesin.
                if la > s.lastEventAt { s.lastEventAt = la }
            case .thinking, .tool:
                let last = max(s.lastEventAt, la)
                if now.timeIntervalSince(last) >= Self.stuckWorkingAfter, s.workingCount == (s.status.isWorking ? 1 : 0) {
                    s.status = .idle
                    s.activity = nil; s.target = nil
                    s.lastEventAt = last
                }
            default: break
            }
            if s != original { sessions[id] = s; changed = true }
        }
        let known = Set(sessions.values.filter { $0.status != .ended && !$0.discovered }.compactMap(\.pid))
        for f in found where !known.contains(f.pid) {
            let id = "discovered-\(f.pid)"
            let activity = min(f.lastActivity ?? now, now)
            if var existing = sessions[id] {
                if activity > existing.lastEventAt { existing.lastEventAt = activity; sessions[id] = existing; changed = true }
                continue
            }
            var s = AgentSession(id: id, project: f.project, model: nil, status: .idle, startedAt: min(activity, now), lastEventAt: activity, pid: f.pid)
            s.discovered = true
            sessions[id] = s
            changed = true
        }
        return changed
    }

    /// Gerçek oturumun ilk olayı gelince aynı süreç için oluşturulmuş yer tutucu silinir (pid eşleşir; eski betikte pid yoksa aynı
    /// proje adındaki tek yer tutucu).
    private mutating func removeDiscoveredPlaceholder(matching e: AgentEvent) {
        guard !e.sessionID.hasPrefix("discovered-") else { return }
        let placeholders = sessions.values.filter(\.discovered)
        guard !placeholders.isEmpty else { return }
        if let pid = e.pid {
            for p in placeholders where p.pid == pid { sessions[p.id] = nil }
        } else if let project = e.project, sessions[e.sessionID] == nil {
            let same = placeholders.filter { $0.project == project }
            if same.count == 1, let only = same.first { sessions[only.id] = nil }
        }
    }

    /// Adalmon oturumdan sonra başladıysa (ya da `SubagentStart` kaçırıldıysa) alt ajan listede yoktur; ama alt ajanın kendi araç olayları
    /// `agent_id` + `agent_type` taşır. Böyle bir olay gelince ajan listeye alınır (bitmiş ajanlar hariç); böylece olay, yanlışlıkla ana
    /// ajanın durumunu değiştirmez ve ajan ofiste görünür.
    private static func adoptIfUnknown(_ e: AgentEvent, in s: inout AgentSession, now: Date) {
        guard let id = e.agentID, let type = e.agentType, !id.isEmpty, !type.isEmpty else { return }
        guard !s.subagents.contains(where: { $0.agentID == id }), !s.retiredAgents.contains(id), s.status != .ended else { return }
        s.subagents.append(AgentSubagent(agentID: id, agentType: type, model: e.model, status: .thinking, activityAt: now))
    }

    private static func retire(_ id: String, in s: inout AgentSession) {
        s.retiredAgents.removeAll { $0 == id }
        s.retiredAgents.append(id)
        if s.retiredAgents.count > retiredLimit { s.retiredAgents.removeFirst(s.retiredAgents.count - retiredLimit) }
    }

    /// Durumu ilgili ajana (agent_id'li alt ajan, yoksa oturumun ana ajanı) yazar; araç bilgisi (`activity`/`target`) yalnızca
    /// PreToolUse'ta dolar, diğer durumlarda temizlenir. Etkinlik zamanı yalnızca o ajanı etkiler.
    private static func setStatus(_ status: AgentStatus, activity: String? = nil, target: String? = nil, for agentID: String?,
                                  in s: inout AgentSession, now: Date) {
        if let id = agentID, let i = s.subagents.firstIndex(where: { $0.agentID == id }) {
            if s.subagents[i].status != .done, s.subagents[i].status != .ended {
                s.subagents[i].status = status
                s.subagents[i].activity = activity; s.subagents[i].target = target; s.subagents[i].activityAt = now
            }
        } else if s.status != .ended {
            s.status = status
            s.activity = activity; s.target = target; s.activityAt = now
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

    /// Bir alt ajanın bayatlama anı (son kendi etkinliği + `subagentStaleAfter`); biten/kapanan ajanlar için nil.
    private static func subagentDue(_ sub: AgentSubagent, in s: AgentSession) -> Date? {
        guard sub.status != .done, sub.status != .ended else { return nil }
        return (sub.activityAt ?? s.lastEventAt).addingTimeInterval(subagentStaleAfter)
    }

    /// Uzun süredir olay göndermeyen (kapanış olayı kaçırılmış) alt ajanları düşürür ve bir daha eklenmemeleri için hatırlar. Değişti mi.
    @discardableResult
    mutating func pruneSubagents(now: Date) -> Bool {
        var changed = false
        for id in sessions.keys {
            guard var s = sessions[id] else { continue }
            let stale = s.subagents.filter { Self.subagentDue($0, in: s).map { now >= $0 } ?? false }
            guard !stale.isEmpty else { continue }
            for sub in stale { Self.retire(sub.agentID, in: &s) }
            s.subagents.removeAll { sub in stale.contains { $0.agentID == sub.agentID } }
            sessions[id] = s
            changed = true
        }
        return changed
    }

    /// Bayat ve süresi dolan kapalı oturumları listeden düşürür; düşen kimlikleri döndürür.
    @discardableResult
    mutating func prune(now: Date) -> [String] {
        let dropped = sessions.values.filter { s in Self.dueDate(s).map { now >= $0 } ?? false }.map(\.id)
        for id in dropped { sessions[id] = nil }
        if sessions.isEmpty { pendingSubagentModels = [:] }
        return dropped
    }

    /// Modeli bilinmeyen (boş ya da rozeti çözülemeyen), kapanmamış oturumların kimlikleri.
    var sessionsWithUnknownModel: [String] {
        sessions.values.filter { $0.status != .ended && $0.badge == .unknown }.map(\.id)
    }

    /// Modeli bilinmeyen, SessionEnd ile kapanmış ama henüz listeden düşmemiş oturumların kimlikleri (son deneme için).
    var endedSessionsWithUnknownModel: [String] {
        sessions.values.filter { $0.status == .ended && $0.badge == .unknown }.map(\.id)
    }

    /// Konuşma dosyasından bulunan modeli yazar; yalnızca oturum hâlâ modelsizse (hook araya model getirmediyse).
    @discardableResult
    mutating func adoptTranscriptModel(_ model: String, for sessionID: String) -> Bool {
        guard var s = sessions[sessionID], s.badge == .unknown else { return false }
        s.model = model
        sessions[sessionID] = s
        return true
    }

    /// Örneklenen arka plan işlemlerini yazar (anahtar = oturum kimliği). Yalnızca değişen oturumlar yazılır; kapalı/pid'siz
    /// oturumlar ve sonuçta olmayanlar temizlenir. Değişiklik olduysa true.
    @discardableResult
    mutating func setShells(_ bySession: [String: SessionShells]) -> Bool {
        var changed = false
        for id in sessions.keys {
            guard var s = sessions[id] else { continue }
            let next = (s.status != .ended && s.pid != nil) ? (bySession[id] ?? .empty) : .empty
            if s.shells != next { s.shells = next; sessions[id] = s; changed = true }
        }
        return changed
    }

    /// Tüm ajanların hedefini siler (etkinlik/araç bilgisi kalır).
    mutating func clearTargets() {
        for id in sessions.keys {
            sessions[id]?.target = nil
            if let n = sessions[id]?.subagents.count { for i in 0..<n { sessions[id]?.subagents[i].target = nil } }
        }
    }

    /// Bir sonraki budama anı (olay yoksa hiçbir zamanlayıcı kurulmaz).
    func nextPruneDate() -> Date? {
        let sessionDates = sessions.values.compactMap(Self.dueDate)
        let subagentDates = sessions.values.flatMap { s in s.subagents.compactMap { Self.subagentDue($0, in: s) } }
        return (sessionDates + subagentDates).min()
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
                s.shells = .empty
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
