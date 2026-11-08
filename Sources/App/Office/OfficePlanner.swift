import Foundation

// Ajan ofisi: saf planlama mantığı (SpriteKit/SwiftUI yok). Oturum ağacı → karakterler, masa atama, durum → davranış,
// model → görünüm. Sahne yalnızca bu planın çıktısını uygular.

// MARK: Üyeler

/// Ofisteki bir karakter: oturum ya da alt ajan.
struct OfficeMember: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable { case session, subagent }
    var id: String
    var parentID: String?
    var kind: Kind
    var label: String
    var badge: AgentModelBadge
    var status: AgentStatus
    /// Oturum rengi şeridi (üst oturum ve alt ajanları aynı şeridi paylaşır).
    var groupIndex: Int

    static let groupPaletteSize = 6

    /// Oturum listesi (en yeni üstte) → ofis üyeleri. Kapanmış oturumlar ve işi biten alt ajanlar listelenmez (çıkışa yürürler).
    /// Alt ajan modeli yoksa üst oturumunkini kullanır.
    static func members(from sessions: [AgentSession]) -> [OfficeMember] {
        var out: [OfficeMember] = []
        for (i, s) in sessions.enumerated().reversed() where s.status != .ended {  // eskiden yeniye: önce gelen önce masa seçer
            let group = Self.stableGroup(for: s.id, fallback: i)
            out.append(OfficeMember(id: s.id, parentID: nil, kind: .session, label: s.displayName, badge: s.badge, status: s.status, groupIndex: group))
            for sub in s.subagents where sub.status != .done && sub.status != .ended {
                out.append(OfficeMember(id: "\(s.id)#\(sub.agentID)", parentID: s.id, kind: .subagent, label: sub.agentType,
                                        badge: sub.model.map { AgentModelBadge(modelID: $0) } ?? s.badge, status: sub.status, groupIndex: group))
            }
        }
        return out
    }

    /// Oturum kimliğinden kararlı renk grubu (liste sırası değişince renk değişmesin).
    static func stableGroup(for id: String, fallback: Int) -> Int {
        guard !id.isEmpty else { return fallback % groupPaletteSize }
        var h: UInt32 = 2166136261
        for b in id.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return Int(h % UInt32(groupPaletteSize))
    }
}

// MARK: Masa atama

enum OfficePlacement: Equatable, Sendable {
    case seat(Int)
    /// Hiç boş koltuk kalmadı; ofiste gösterilmez (sayaç).
    case overflow
}

struct OfficePlan: Equatable, Sendable {
    var placements: [String: OfficePlacement]
    /// Önceki plandan düşen (çıkışa yürüyecek) üyeler.
    var departed: [String]
    var overflowCount: Int { placements.values.filter { $0 == .overflow }.count }
}

/// Kararlı masa atayıcı: bir üye var olduğu sürece koltuğunu korur. Yeni oturum ilk boş masaya, alt ajan üst oturumuna en yakın
/// boş masaya oturur; masa kalmazsa salon (kanepe) koltuklarına, o da dolarsa taşar.
struct OfficeAssigner: Sendable {
    let seats: [OfficeSeat]
    private(set) var seatOf: [String: Int] = [:]

    init(seats: [OfficeSeat]) { self.seats = seats }

    mutating func update(members: [OfficeMember]) -> OfficePlan {
        let ids = Set(members.map(\.id))
        let departed = seatOf.keys.filter { !ids.contains($0) }.sorted()
        for id in departed { seatOf[id] = nil }

        var placements: [String: OfficePlacement] = [:]
        var taken = Set(seatOf.values)
        // Önce kalıcı atamalar, sonra yeni gelenler; oturumlar alt ajanlardan önce.
        for m in members where seatOf[m.id] != nil { placements[m.id] = .seat(seatOf[m.id]!) }
        let newcomers = members.filter { seatOf[$0.id] == nil }.sorted { ($0.kind == .session ? 0 : 1) < ($1.kind == .session ? 0 : 1) }
        for m in newcomers {
            let anchor = m.parentID.flatMap { seatOf[$0] }.flatMap { id in seats.first { $0.id == id }?.tile }
            if let seat = pick(for: m, anchor: anchor, taken: taken) {
                seatOf[m.id] = seat.id
                taken.insert(seat.id)
                placements[m.id] = .seat(seat.id)
            } else {
                placements[m.id] = .overflow
            }
        }
        return OfficePlan(placements: placements, departed: departed)
    }

    private func pick(for m: OfficeMember, anchor: OfficeTile?, taken: Set<Int>) -> OfficeSeat? {
        for kind in [OfficeSeat.Kind.desk, .lounge] {
            let free = seats.filter { $0.kind == kind && !taken.contains($0.id) }
            if free.isEmpty { continue }
            if let anchor {
                return free.min { ($0.tile.manhattan(to: anchor), $0.id) < ($1.tile.manhattan(to: anchor), $1.id) }
            }
            return free.first
        }
        return nil
    }
}

// MARK: Durum → davranış

struct OfficeBehavior: Equatable, Sendable {
    enum Pose: Equatable, Sendable { case typing, reading, sitting }
    enum Bubble: Equatable, Sendable { case alert, thinking }

    var pose: Pose
    var bubble: Bubble?
    /// Masadaki bilgisayar ekranı açık mı.
    var pcOn: Bool
    /// Boştayken ara sıra kahveye yürüyebilir.
    var mayWander: Bool

    static func behavior(for status: AgentStatus, atDesk: Bool) -> OfficeBehavior {
        switch status {
        case .thinking: OfficeBehavior(pose: atDesk ? .typing : .reading, bubble: .thinking, pcOn: atDesk, mayWander: false)
        case .tool: OfficeBehavior(pose: atDesk ? .typing : .reading, bubble: nil, pcOn: atDesk, mayWander: false)
        case .waitingPermission: OfficeBehavior(pose: .reading, bubble: .alert, pcOn: atDesk, mayWander: false)
        case .idle: OfficeBehavior(pose: .sitting, bubble: nil, pcOn: false, mayWander: true)
        case .done: OfficeBehavior(pose: .sitting, bubble: nil, pcOn: false, mayWander: true)
        case .ended: OfficeBehavior(pose: .sitting, bubble: nil, pcOn: false, mayWander: false)
        }
    }

    /// Kısa kutlama (zıplama) yalnızca çalışırken "bitti"ye geçişte.
    static func celebrates(from old: AgentStatus?, to new: AgentStatus) -> Bool {
        new == .done && old != nil && old != .done && old != .idle
    }

    /// Bilgisayar ekranı kare kimlikleri (PC_FRONT_OFF → ON_1…3); animasyonlu durumu olmayan PC'ler (yan/arka) nil.
    static func pcOnFrames(forOffAsset id: String) -> [String]? {
        guard id.hasSuffix("_OFF") else { return nil }
        let base = String(id.dropLast(4))
        return (1...3).map { "\(base)_ON_\($0)" }
    }
}

/// Boşta duran oturan karakterleri ara sıra kahveye göndermek için saf karar (zamanlayıcı dışarıda, tek ve kaba).
enum OfficeWander {
    struct Candidate: Equatable, Sendable {
        var id: String
        var idleSince: Date
    }

    static let minIdle: TimeInterval = 20
    static let minGap: TimeInterval = 25

    /// En fazla bir üye; kimse yürümüyorsa ve son yürüyüşten `minGap` geçtiyse. `roll` 0…1 (olasılık kapısı).
    static func pick(_ candidates: [Candidate], now: Date, lastWander: Date?, someoneWalking: Bool, roll: Double, chance: Double = 0.5) -> String? {
        guard !someoneWalking, roll < chance else { return nil }
        if let last = lastWander, now.timeIntervalSince(last) < minGap { return nil }
        return candidates.filter { now.timeIntervalSince($0.idleSince) >= minIdle }.min { $0.idleSince < $1.idleSince }?.id
    }
}

// MARK: Model → görünüm

enum OfficeAccessory: Equatable, Sendable {
    case none, crown, cap, star, sprout
}

struct OfficeAppearance: Equatable, Sendable {
    /// char_N.png dizini (0…5).
    var characterIndex: Int
    /// Panel/menü rozetiyle aynı renk (AgentsPanelView.AgentModelBadge.tint: Opus mor, Sonnet mavi, Haiku yeşil, Fable turuncu).
    var tint: OfficeRGB
    var tintBlend: Double
    var accessory: OfficeAccessory
    /// true: karakter bir tam piksel küçük çizilir (`spriteScale`).
    var small: Bool
    var badgeText: String

    static func appearance(for badge: AgentModelBadge) -> OfficeAppearance {
        switch badge {
        case .opus: OfficeAppearance(characterIndex: 2, tint: OfficeRGB(r: 0.69, g: 0.32, b: 0.87), tintBlend: 0.4, accessory: .crown, small: false, badgeText: "OPUS")
        case .sonnet: OfficeAppearance(characterIndex: 0, tint: OfficeRGB(r: 0.0, g: 0.48, b: 1.0), tintBlend: 0.4, accessory: .cap, small: false, badgeText: "SONNET")
        case .haiku: OfficeAppearance(characterIndex: 4, tint: OfficeRGB(r: 0.2, g: 0.78, b: 0.35), tintBlend: 0.4, accessory: .sprout, small: true, badgeText: "HAIKU")
        case .fable: OfficeAppearance(characterIndex: 5, tint: OfficeRGB(r: 1.0, g: 0.58, b: 0.0), tintBlend: 0.4, accessory: .star, small: false, badgeText: "FABLE")
        case .unknown: OfficeAppearance(characterIndex: 3, tint: OfficeRGB(r: 0.56, g: 0.56, b: 0.58), tintBlend: 0.2, accessory: .none, small: false, badgeText: "?")
        }
    }

    /// Düğüm ölçeği: Haiku bir tam piksel küçük (zoom-1)/zoom: nearest ile bozulmaz. Zoom 1'de küçültme yok.
    static func spriteScale(small: Bool, zoom: Int) -> Double {
        guard small, zoom >= 2 else { return 1 }
        return Double(zoom - 1) / Double(zoom)
    }

    /// Ofisin pencereye sığan en büyük tam sayı yakınlaştırması (en az 1).
    static func integerZoom(viewWidth: Double, viewHeight: Double, contentWidth: Double, contentHeight: Double, maxZoom: Int = 8) -> Int {
        guard contentWidth > 0, contentHeight > 0 else { return 1 }
        let z = Int(min(viewWidth / contentWidth, viewHeight / contentHeight).rounded(.down))
        return min(maxZoom, max(1, z))
    }

    /// Oturum şeridi renkleri (üst oturum ve alt ajanları paylaşır).
    static let groupColors: [OfficeRGB] = [
        OfficeRGB(r: 0.95, g: 0.35, b: 0.40), OfficeRGB(r: 0.30, g: 0.80, b: 0.95), OfficeRGB(r: 0.98, g: 0.82, b: 0.25),
        OfficeRGB(r: 0.55, g: 0.90, b: 0.45), OfficeRGB(r: 0.95, g: 0.55, b: 0.85), OfficeRGB(r: 0.98, g: 0.62, b: 0.30),
    ]
}

// MARK: Demo

/// Ajan olayı gelmeden denemek için sahte oturum zaman çizelgesi (paylaşılan `AgentMonitorModel`'e dokunmaz; sayfa yerelde besler).
enum OfficeDemo {
    /// Her adım bir anlık oturum listesidir (en yeni üstte). Adımlar `stepInterval` aralıkla oynatılır.
    static let stepInterval: TimeInterval = 3

    static func steps(now: Date = .now) -> [[AgentSession]] {
        func session(_ id: String, _ project: String, _ model: String, _ status: AgentStatus, _ subs: [AgentSubagent] = [], age: TimeInterval) -> AgentSession {
            AgentSession(id: id, project: project, model: model, status: status, startedAt: now.addingTimeInterval(-age), lastEventAt: now,
                         subagents: subs)
        }
        func sub(_ id: String, _ type: String, _ model: String, _ status: AgentStatus) -> AgentSubagent {
            AgentSubagent(agentID: id, agentType: type, model: model, status: status)
        }
        let opus = "claude-opus-4-8", sonnet = "claude-sonnet-5-5", haiku = "claude-haiku-4-5", fable = "claude-fable-1"
        var steps: [[AgentSession]] = []
        steps.append([session("d1", "adalmon", opus, .idle, age: 40)])
        steps.append([session("d1", "adalmon", opus, .thinking, age: 40)])
        steps.append([session("d1", "adalmon", opus, .tool("Edit"), [sub("a1", "Explore", haiku, .thinking)], age: 40)])
        steps.append([session("d2", "api-sunucu", sonnet, .thinking, age: 20),
                      session("d1", "adalmon", opus, .tool("Bash"), [sub("a1", "Explore", haiku, .tool("Grep")), sub("a2", "general-purpose", sonnet, .thinking)], age: 40)])
        steps.append([session("d3", "web-site", fable, .idle, age: 5),
                      session("d2", "api-sunucu", sonnet, .waitingPermission, age: 20),
                      session("d1", "adalmon", opus, .tool("Write"), [sub("a1", "Explore", haiku, .tool("Read")), sub("a2", "general-purpose", sonnet, .tool("Bash")), sub("a3", "Plan", opus, .thinking)], age: 40)])
        steps.append([session("d3", "web-site", fable, .thinking, age: 5),
                      session("d2", "api-sunucu", sonnet, .tool("Edit"), age: 20),
                      session("d1", "adalmon", opus, .done, [sub("a1", "Explore", haiku, .done), sub("a2", "general-purpose", sonnet, .tool("Bash")), sub("a3", "Plan", opus, .done)], age: 40)])
        steps.append([session("d3", "web-site", fable, .done, age: 5),
                      session("d2", "api-sunucu", sonnet, .idle, age: 20),
                      session("d1", "adalmon", opus, .ended, age: 40)])
        return steps
    }

    /// Bir adım için tek anlık "ortalama sahne": önizleme testi ve statik demo.
    static var showcase: [AgentSession] { steps()[4] }
}
