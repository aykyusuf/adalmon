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

    static func roleJSON(_ m: OfficeMember) -> [String: Any] {
        if m.kind == .session {
            let a = OfficeAppearance.appearance(for: m.badge)
            return ["key": "lead", "name": "ana ajan", "tint": OfficeRoles.hex(a.tint), "accessory": OfficeWebLayout.accessoryName(a.accessory)]
        }
        let r = OfficeRoles.style(forAgentType: m.label)
        return ["key": r.key, "name": r.name, "tint": r.tintHex, "accessory": r.accessory.rawValue, "small": r.small, "hoodie": r.hoodie, "known": r.known,
                "labelColor": OfficeRoles.hex(r.labelColor)]
    }

    static func appearanceJSON(_ m: OfficeMember) -> [String: Any] {
        let a = OfficeAppearance.appearance(for: m)
        var out: [String: Any] = ["character": a.characterIndex, "tint": OfficeRoles.hex(a.tint), "tintBlend": a.tintBlend, "small": a.small,
                                  "accessory": OfficeWebLayout.accessoryName(a.accessory)]
        if let dot = a.modelDot { out["modelDot"] = OfficeRoles.hex(dot) }
        return out
    }

    static func lightingJSON(now: Date, mode: OfficeLightingMode = OfficeLighting.storedMode(), timeZone: TimeZone = .current) -> [String: Any] {
        ["mode": mode.rawValue, "nightStartHour": OfficeLighting.nightStartMinutes / 60, "nightStartMinute": OfficeLighting.nightStartMinutes % 60,
         "nightEndHour": OfficeLighting.nightEndMinutes / 60, "nightEndMinute": OfficeLighting.nightEndMinutes % 60,
         "resolvedNight": OfficeLighting.isNight(mode: mode, date: now, timeZone: timeZone), "timeZone": timeZone.identifier]
    }

    /// Oturumun arka plan işlemleri: yalnızca işlem adı (basename), süre, CPU %, RSS MB (komut satırı yok).
    static func shellsJSON(_ shells: SessionShells, known: Bool) -> [String: Any] {
        ["count": shells.total, "known": known, "hidden": shells.hidden,
         "items": shells.items.map { ["name": $0.name, "ageSec": $0.ageSeconds, "cpu": $0.cpuPercent, "rssMB": Int($0.rssBytes / 1_048_576)] as [String: Any] }]
    }

    static func rackJSON(_ state: OfficeRackState) -> [String: Any] {
        ["leds": state.leds.map(\.rawValue), "lit": state.litCount, "count": state.count, "known": state.known, "tooltip": state.tooltip]
    }

    /// Sıkıştırılmış tek satır JSON (SSE `data:` satırı olarak güvenli).
    /// Küçük (sekme) oturumlar: yalnızca kimlik, ad, model, durum ve son etkinlik zamanı (oda/koltuk yok).
    static func minimizedJSON(_ sessions: [AgentSession]) -> [[String: Any]] {
        sessions.map { s in
            var item: [String: Any] = ["id": s.id, "label": s.displayName, "badge": s.badge.rawValue, "badgeLabel": s.badge.label,
                                       "status": statusKey(s.status), "statusLabel": s.status.label, "lastEventAt": ms(s.lastEventAt),
                                       "group": OfficeMember.stableGroup(for: s.id, fallback: 0)]
            if let project = s.secondaryName { item["project"] = project }
            return item
        }
    }

    func snapshot(sessions: [AgentSession], minimized: [AgentSession] = [], now: Date = .now) -> Data {
        let members = OfficeMember.members(from: sessions)
        let plan = planner.update(members: members)
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        var rooms: [[String: Any]] = []
        var agentCount = 0
        for room in plan.rooms where !room.isPlaceholder {
            let roomMembers = members.filter { ($0.parentID ?? $0.id) == room.id }
            var seatKinds: [Int: OfficeSeat.Kind] = [:]
            var seatByID: [Int: OfficeSeat] = [:]
            for s in seats[room.tier] ?? [] { seatKinds[s.id] = s.kind; seatByID[s.id] = s }
            // Boş masalar dahil tüm bilgisayarlar (oda kimliğine bağlı tohum): tarayıcı tohum hesaplamaz. Anahtar = mobilya yerleşim indeksi (`pc`).
            var computers: [String: String] = [:]
            for s in seats[room.tier] ?? [] {
                guard let pc = s.pcIndex else { continue }
                let c = s.kind == .executive ? OfficeComputer.executive : OfficeComputer.pick(roomID: room.id, seatID: OfficeRoomNode.seatKey(s))
                computers[String(pc)] = c.artName
            }
            var list: [[String: Any]] = []
            for m in roomMembers {
                var item: [String: Any] = [
                    "id": m.id, "kind": m.kind == .session ? "session" : "subagent", "label": m.label,
                    "badge": m.badge.rawValue, "status": Self.statusKey(m.status), "statusLabel": m.status.label,
                    "working": m.status.isWorking,
                ]
                item["role"] = Self.roleJSON(m)
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
                    if let s = seatByID[id] {
                        item["seatInfo"] = ["id": s.id, "col": s.tile.col, "row": s.tile.row, "kind": OfficeWebLayout.seatKindName(s.kind),
                                            "facing": OfficeWebLayout.directionName(s.facing), "key": OfficeRoomNode.seatKey(s)] as [String: Any]
                        let pc = s.kind == .executive ? OfficeComputer.executive : OfficeComputer.pick(roomID: room.id, seatID: OfficeRoomNode.seatKey(s))
                        var look = Self.appearanceJSON(m)
                        look["computer"] = ["kind": pc.kind.rawValue, "color": pc.color.rawValue, "name": pc.artName]
                        item["appearance"] = look
                    }
                    let idleSeed = "\(room.id)|\(m.id)"
                    item["idleVariant"] = ["seed": idleSeed, "sequence": (0..<8).map { n in
                        ["variant": OfficeIdle.variant(seed: idleSeed, n: n).rawValue, "seconds": OfficeIdle.length(seed: idleSeed, n: n)] as [String: Any]
                    }] as [String: Any]
                } else {
                    item["overflow"] = true
                    item["appearance"] = Self.appearanceJSON(m)
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
                "id": room.id, "tier": OfficeWebLayout.tierKeys[room.tier] ?? room.tier.key, "stations": room.tier.stations, "capacity": room.tier.capacity,
                "cleaner": ["intervalMin": OfficeCleaner.interval.lowerBound, "intervalMax": OfficeCleaner.interval.upperBound, "route": "S",
                            "laneRows": OfficeRoomTemplates.laneRows(stations: room.tier.stations), "seed": room.id] as [String: Any], "title": room.title ?? "", "badge": room.badge?.rawValue ?? "unknown",
                "badgeLabel": room.badge?.label ?? "", "group": room.groupIndex, "reseated": room.reseated, "memberCount": room.memberCount,
                "overflow": room.overflowCount, "members": list, "computers": computers,
                "shells": Self.shellsJSON(byID[room.id]?.shells ?? .empty, known: byID[room.id]?.pid != nil),
                "rack": Self.rackJSON(.make(total: byID[room.id]?.shells.total ?? 0, known: byID[room.id]?.pid != nil)),
            ])
        }
        let root: [String: Any] = [
            "v": 3, "now": Self.ms(now), "lighting": Self.lightingJSON(now: now), "sessions": rooms.count, "agents": agentCount, "rooms": rooms,
            "working": sessions.reduce(0) { $0 + $1.workingCount },
            "minimized": Self.minimizedJSON(minimized),
        ]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])) ?? Data(#"{"v":1,"rooms":[]}"#.utf8)
    }
}
