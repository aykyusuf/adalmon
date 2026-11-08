import Foundation

/// `GET /v1/state` ve SSE olaylarının gövdesi: oturum ağacı → odalar → üyeler (ofis planlayıcısının koltuk ataması, davranış ve
/// hazır balon metniyle). Yalnızca izinli alanlar çıkar: ad/proje, model rozeti, durum, araç adı, (ayar açıksa) hedef, süreler.
/// İstem/komut/dosya içeriği zaten Adalmon'da yoktur. Planlayıcı durumludur (koltuklar kararlı kalır); ana aktörde kullanılır.
@MainActor
final class AgentWebSnapshotBuilder {
    private var planner: OfficeRoomPlanner
    private let seats: [OfficeRoomTier: [OfficeSeat]]

    init(seats: [OfficeRoomTier: [OfficeSeat]]) {
        self.seats = seats
        planner = OfficeRoomPlanner(seats: seats)
    }

    static func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    static func statusKey(_ status: AgentStatus) -> String {
        switch status {
        case .thinking: "thinking"
        case .tool: "tool"
        case .waitingPermission: "permission"
        case .idle: "idle"
        case .done: "done"
        case .ended: "ended"
        }
    }

    /// Sıkıştırılmış tek satır JSON (SSE `data:` satırı olarak güvenli).
    func snapshot(sessions: [AgentSession], now: Date = .now) -> Data {
        let members = OfficeMember.members(from: sessions)
        let plan = planner.update(members: members)
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        var rooms: [[String: Any]] = []
        var agentCount = 0
        for room in plan.rooms where !room.isPlaceholder {
            let roomMembers = members.filter { ($0.parentID ?? $0.id) == room.id }
            var seatKinds: [Int: OfficeSeat.Kind] = [:]
            for s in seats[room.tier] ?? [] { seatKinds[s.id] = s.kind }
            var list: [[String: Any]] = []
            for m in roomMembers {
                var item: [String: Any] = [
                    "id": m.id, "kind": m.kind == .session ? "session" : "subagent", "label": m.label,
                    "badge": m.badge.rawValue, "status": Self.statusKey(m.status), "statusLabel": m.status.label,
                    "working": m.status.isWorking,
                ]
                if let a = m.activity { item["activity"] = a }
                if let t = m.target { item["target"] = t }
                if let at = m.activityAt { item["activityAt"] = Self.ms(at) }
                if let text = OfficeBubbleText.text(status: m.status, activity: m.activity, target: m.target) { item["bubble"] = text }
                if case .seat(let id)? = room.placements[m.id] {
                    item["seat"] = id
                    let kind = seatKinds[id]
                    item["seatKind"] = kind.map(OfficeWebLayout.seatKindName) ?? "desk"
                    let b = OfficeBehavior.behavior(for: m.status, atDesk: kind == .desk, executive: kind == .executive)
                    item["pose"] = b.pose == .typing ? "typing" : b.pose == .reading ? "reading" : "sitting"
                    item["alert"] = b.bubble == .alert
                    item["pcOn"] = b.pcOn
                    item["standing"] = b.standing
                } else {
                    item["overflow"] = true
                }
                if m.kind == .session, let s = byID[m.id] {
                    item["startedAt"] = Self.ms(s.startedAt)
                    if let project = s.secondaryName { item["project"] = project }
                } else if m.kind == .subagent {
                    agentCount += 1
                }
                if m.kind == .session { agentCount += 1 }
                list.append(item)
            }
            rooms.append([
                "id": room.id, "tier": OfficeWebLayout.tierKeys[room.tier] ?? "small", "title": room.title ?? "", "badge": room.badge?.rawValue ?? "unknown",
                "badgeLabel": room.badge?.label ?? "", "group": room.groupIndex, "reseated": room.reseated, "memberCount": room.memberCount,
                "overflow": room.overflowCount, "members": list,
            ])
        }
        let root: [String: Any] = [
            "v": 1, "now": Self.ms(now), "sessions": rooms.count, "agents": agentCount, "rooms": rooms,
            "working": sessions.reduce(0) { $0 + $1.workingCount },
        ]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])) ?? Data(#"{"v":1,"rooms":[]}"#.utf8)
    }
}
