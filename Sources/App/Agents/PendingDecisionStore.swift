import Foundation
import Observation

/// Ofiste bekleyen izin/soru kararları (YALNIZCA bellek). Karar içeriği buradan başka yere yazılmaz; denetim kaydı yalnızca
/// üst veri taşır (zaman, oturum, proje, araç adı, tür, karar, mod, "hep" kapsamı) ve içerik anahtarı içermez.
@MainActor @Observable
final class PendingDecisionStore {
    /// Aynı anda en çok bu kadar bekleyen karar (sunucunun tutulan bağlantı sınırıyla aynı).
    nonisolated static let maxPending = 8

    /// Denetim kaydı satırı. Alanlar sabit; tür/araç/proje adı dışında istek içeriği YOK.
    struct AuditEntry: Codable, Equatable, Sendable {
        var ts: String
        var sessionID: String
        var project: String?
        var tool: String
        var kind: String
        var verdict: String
        var mode: String?
        var always: String?

        enum CodingKeys: String, CodingKey {
            case ts, project, tool, kind, verdict, mode, always
            case sessionID = "session_id"
        }
    }

    nonisolated static let auditKeys: Set<String> = ["ts", "session_id", "project", "tool", "kind", "verdict", "mode", "always"]
    nonisolated static let auditMaxBytes = 200_000
    nonisolated static let auditKeepLines = 500

    private(set) var items: [PendingDecision] = []
    /// Karar tıklanınca tutulan bağlantıya yazan köprü (sunucu). Atanmadıysa karar yalnızca düşer.
    @ObservationIgnored var responder: ((UUID, DecisionVerdict) -> Void)?
    /// Kart düşünce tutulan bağlantıyı kapatır (betik hemen çıksın; pil).
    @ObservationIgnored var releaser: ((UUID) -> Void)?
    /// Liste değişince çağrılır (oturumu "dikkat istiyor" saymak için).
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let auditURL: URL?
    @ObservationIgnored private var closedEarly: [UUID] = []

    /// `auditURL` nil ise denetim kaydı yazılmaz (testler).
    init(auditURL: URL? = nil) {
        self.auditURL = auditURL
    }

    var sessionIDs: Set<String> { Set(items.map(\.sessionID)) }

    func decisions(forSession id: String) -> [PendingDecision] { items.filter { $0.sessionID == id } }

    /// Eklenir; üst sınır doluysa ya da bağlantı zaten kapanmışsa false.
    @discardableResult
    func add(_ decision: PendingDecision) -> Bool {
        if let i = closedEarly.firstIndex(of: decision.id) { closedEarly.remove(at: i); return false }
        guard items.count < Self.maxPending, !items.contains(where: { $0.id == decision.id }) else { return false }
        items.append(decision)
        onChange?()
        return true
    }

    /// Kullanıcı karar verdi: kart düşer, karar tutulan bağlantıya yazılır, denetim kaydı eklenir. Geç/çift tıklama zararsızdır.
    func resolve(_ id: UUID, _ verdict: DecisionVerdict) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let decision = items.remove(at: i)
        var mode: String?
        var always: String?
        if case .allow(let suggestion, let scope, let m) = verdict {
            mode = m?.rawValue
            if suggestion != nil { always = scope.rawValue }
        }
        audit(decision, verdict: verdict.auditName, mode: mode, always: always)
        responder?(id, verdict)
        onChange?()
    }

    /// Bağlantı (betik) kapandı: kart sessizce düşer (kapatılacak bağlantı kalmadı). Henüz eklenmemiş kimlik hatırlanır.
    func serverClosed(_ id: UUID) {
        if let i = items.firstIndex(where: { $0.id == id }) {
            let decision = items.remove(at: i)
            audit(decision, verdict: "closed", mode: nil, always: nil)
            onChange?()
        } else {
            closedEarly.append(id)
            if closedEarly.count > 32 { closedEarly.removeFirst(closedEarly.count - 32) }
        }
    }

    /// Aynı oturum/ajanın sonraki olayı kartı düşürür; tutulan bağlantı kapatılır. Düşen karar sayısını döndürür.
    @discardableResult
    func dismiss(matching event: AgentEvent) -> Int {
        let dropped = items.filter { Self.matches($0, event: event) }
        guard !dropped.isEmpty else { return 0 }
        items.removeAll { d in dropped.contains { $0.id == d.id } }
        for d in dropped {
            audit(d, verdict: "dropped", mode: nil, always: nil)
            releaser?(d.id)
        }
        onChange?()
        return dropped.count
    }

    /// Hepsi düşer (özellik kapandı, dinleyici durdu). Bağlantılar bırakılır.
    func dismissAll() {
        guard !items.isEmpty else { return }
        let dropped = items
        items = []
        for d in dropped {
            audit(d, verdict: "dropped", mode: nil, always: nil)
            releaser?(d.id)
        }
        onChange?()
    }

    /// Olay → kart eşleşmesi. Eşleştirme: oturum + ajan; araç sonucu olaylarında ek olarak araç adı (+ girdi özeti, istem kimliği iki
    /// tarafta da varsa). İstekten ÖNCE üretilmiş bir olay (ör. önceki aynı araç çağrısının geç gelen PostToolUse'u) kartı düşürmez.
    nonisolated static func matches(_ d: PendingDecision, event: AgentEvent) -> Bool {
        guard d.sessionID == event.sessionID, let name = event.name else { return false }
        if name == .sessionEnd { return true }
        guard d.agentID == event.agentID else { return false }
        if let ts = event.timestamp, let sent = d.request.timestamp, ts < sent.addingTimeInterval(-0.05) { return false }
        switch name {
        case .stop, .userPromptSubmit, .subagentStop:
            return true
        case .postToolUse, .postToolUseFailure, .permissionDenied:
            guard event.toolName == d.request.toolName else { return false }
            // AskUserQuestion: terminalde cevaplanınca girdiye `answers` eklenebilir; özet eşleşmez, araç adı + oturum + istem yeter.
            if d.request.toolName != "AskUserQuestion", let a = event.inputHash, let b = d.request.inputHash, a != b { return false }
            if let a = event.promptID, let b = d.request.promptID, a != b { return false }
            return true
        default:
            return false
        }
    }

    // MARK: Denetim kaydı

    private func audit(_ d: PendingDecision, verdict: String, mode: String?, always: String?) {
        guard let url = auditURL else { return }
        let entry = AuditEntry(ts: ISO8601DateFormatter().string(from: .now), sessionID: d.sessionID, project: d.request.project,
                               tool: d.request.toolName, kind: d.request.kind.rawValue, verdict: verdict, mode: mode, always: always)
        Self.append(entry, to: url)
    }

    /// Tek satır JSON ekler. Dosya `auditMaxBytes`'ı aşarsa son `auditKeepLines` satır kalır (silme yok, yeniden yazılır).
    nonisolated static func append(_ entry: AuditEntry, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        if let size = (try? manager.attributesOfItem(atPath: url.path)[.size]) as? Int, size > auditMaxBytes,
           let text = try? String(contentsOf: url, encoding: .utf8) {
            let kept = text.split(separator: "\n", omittingEmptySubsequences: true).suffix(auditKeepLines).joined(separator: "\n") + "\n"
            try? Data(kept.utf8).write(to: url, options: .atomic)
            try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }
}
