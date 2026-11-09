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
    /// Konuşma balonu girdisi: çalışılan araç adı, isteğe bağlı kısa hedef ve ajanın son kendi olayı (nil: balon sönmez).
    var activity: String? = nil
    var target: String? = nil
    var activityAt: Date? = nil
    /// Oturumun başlangıç zamanı (alt ajanlarda nil: ofis ilk gördüğü anı kullanır).
    var startedAt: Date? = nil
    /// Oturumun arka plan işlemleri ve pid'inin bilinip bilinmediği (ofis rafı + kart; alt ajanlarda hep boş).
    var shells: SessionShells = .empty
    var shellsKnown = false

    static let groupPaletteSize = 6

    /// Oturum listesi (en yeni üstte) → ofis üyeleri. Kapanmış oturumlar ve işi biten alt ajanlar listelenmez (çıkışa yürürler).
    /// Alt ajan modeli yoksa üst oturumunkini kullanır.
    static func members(from sessions: [AgentSession]) -> [OfficeMember] {
        var out: [OfficeMember] = []
        for (i, s) in sessions.enumerated().reversed() where s.status != .ended {  // eskiden yeniye: önce gelen önce masa seçer
            let group = Self.stableGroup(for: s.id, fallback: i)
            out.append(OfficeMember(id: s.id, parentID: nil, kind: .session, label: s.displayName, badge: s.badge, status: s.status, groupIndex: group,
                                 activity: s.activity, target: s.target, activityAt: s.activityAt, startedAt: s.startedAt,
                                 shells: s.shells, shellsKnown: s.pid != nil))
            for sub in s.subagents where sub.status != .done && sub.status != .ended {
                out.append(OfficeMember(id: "\(s.id)#\(sub.agentID)", parentID: s.id, kind: .subagent, label: sub.agentType,
                                        badge: sub.model.map { AgentModelBadge(modelID: $0) } ?? s.badge, status: sub.status, groupIndex: group,
                                        activity: sub.activity, target: sub.target, activityAt: sub.activityAt))
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

/// Kararlı masa atayıcı: bir üye var olduğu sürece koltuğunu korur. Oturum (ana ajan) odanın yönetici koltuğuna, alt ajan üst
/// oturumuna (yönetici koltuğuna) en yakın boş masaya oturur; masa kalmazsa taşar (salon koltukları ajan koltuğu değildir). Yönetici
/// koltuğu olmayan düzenlerde (eski/sentetik) oturum ilk masaya oturur.
struct OfficeAssigner: Sendable {
    let seats: [OfficeSeat]
    private(set) var seatOf: [String: Int] = [:]

    init(seats: [OfficeSeat]) { self.seats = seats }

    /// Kademe değişiminde: önceki koltukları karo + tür olarak yeni koltuklara taşır (oturanlar yerinde kalır).
    init(seats: [OfficeSeat], carrying old: [String: OfficeSeat]) {
        self.seats = seats
        for (id, o) in old.sorted(by: { $0.key < $1.key }) {
            if let s = seats.first(where: { $0.tile == o.tile && $0.kind == o.kind }) { seatOf[id] = s.id }
        }
    }

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
        // Salon koltukları ajan koltuğu değildir (yalnızca dekor); oturum yönetici koltuğu yoksa ilk masaya oturur.
        let kinds: [OfficeSeat.Kind] = m.kind == .session ? [.executive, .desk] : [.desk]
        for kind in kinds {
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
    /// Yönetici: beyaz tahtanın önünde ayakta (yazıyor ya da izin bekliyor); false: masasında oturuyor.
    var standing = false

    /// `executive`: ana ajanın yönetici köşesi. Çalışırken tahta önünde ayakta, boştayken masasında oturur (kahveye gitmez).
    static func behavior(for status: AgentStatus, atDesk: Bool, executive: Bool = false) -> OfficeBehavior {
        if executive {
            switch status {
            case .thinking: return OfficeBehavior(pose: .typing, bubble: .thinking, pcOn: false, mayWander: false, standing: true)
            case .tool: return OfficeBehavior(pose: .typing, bubble: nil, pcOn: false, mayWander: false, standing: true)
            case .waitingPermission: return OfficeBehavior(pose: .reading, bubble: .alert, pcOn: false, mayWander: false, standing: true)
            case .idle, .done, .ended: return OfficeBehavior(pose: .sitting, bubble: nil, pcOn: false, mayWander: false)
            }
        }
        return switch status {
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

// MARK: Yönetici (ana ajan) davranışı

/// Yöneticinin bulunduğu yer/davranış: tahta önünde ayakta yazar (+ ara sıra alt ajanlara bakar), yönetici bölgesinde volta atar,
/// ya da masasında oturur.
enum OfficeExecutiveMode: Equatable, Sendable { case board, stroll, seated }

enum OfficeExecutive {
    /// Oturum boşa/bitişe geçince bu süre volta atar, sonra masasına oturur ve durur (CPU).
    static let idleStrollDuration: TimeInterval = 60

    /// Duruma göre mod. `strollUntil`: boşa geçişte kurulan volta bitiş anı (nil: volta yok, doğrudan masada).
    /// Çalışırken tahtada; izin beklerken (iş sürüyor ama ajan durdu) süresiz volta; boştayken `strollUntil`'e kadar volta.
    static func mode(status: AgentStatus, strollUntil: Date?, now: Date) -> OfficeExecutiveMode {
        switch status {
        case .thinking, .tool: return .board
        case .waitingPermission: return .stroll
        case .idle, .done: if let strollUntil, now < strollUntil { return .stroll }; return .seated
        case .ended: return .seated
        }
    }

    /// Durum değişince volta bitiş anı: çalışırken/izin beklerken yok; çalışmadan boşa geçişte (animasyonluysa) şimdi + süre.
    static func strollDeadline(previous: Date?, old: AgentStatus, new: AgentStatus, animated: Bool, now: Date) -> Date? {
        if new.isWorking { return nil }
        if old.isWorking { return animated ? now.addingTimeInterval(idleStrollDuration) : nil }
        return previous
    }
}

/// Yönetici volta rotası ve tahta başı bakış zamanlaması: saf, deterministik "rastgele" (üye kimliğinden tohumlanır).
enum OfficeStroll {
    /// Volta yürüyüşünün yatay uzunluğu (karo).
    static let lengths = 4...6

    static func seed(for id: String) -> UInt64 {
        var h: UInt64 = 14695981039346656037
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }

    /// SplitMix64 → 0..<1.
    static func roll(seed: UInt64, _ n: Int) -> Double {
        var z = seed &+ UInt64(truncatingIfNeeded: n) &* 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    /// `from`'dan, bölge karoları (`zone`) içinde, aynı/komşu satırda 4-6 (olmazsa mümkün olan en uzun, en az 2) karo yatay yürüyüş hedefi.
    /// Hedef her zaman `zone` içindedir; `from` dışında en az bir karo yoksa nil.
    static func target(from: OfficeTile, zone: [OfficeTile], seed: UInt64, step: Int) -> OfficeTile? {
        let others = zone.filter { $0 != from && abs($0.row - from.row) <= 1 }
        var pool = others.filter { lengths.contains(abs($0.col - from.col)) }
        if pool.isEmpty {
            let far = others.map { abs($0.col - from.col) }.max() ?? 0
            if far >= 2 { pool = others.filter { abs($0.col - from.col) == far } }
        }
        if pool.isEmpty { pool = others }
        guard !pool.isEmpty else { return nil }
        return pool[min(pool.count - 1, Int(roll(seed: seed, step * 3) * Double(pool.count)))]
    }

    /// Volta duraklaması (sn): 1.5…4.
    static func pause(seed: UInt64, step: Int) -> TimeInterval { 1.5 + roll(seed: seed, step * 3 + 1) * 2.5 }
    /// Tahtaya dönük yazma süresi (sn): 3…5 — sonra alt ajanlara bakar.
    static func writeInterval(seed: UInt64, _ n: Int) -> TimeInterval { 3 + roll(seed: seed, n * 3 + 2) * 2 }
    /// Alt ajanlara bakma süresi (sn): 1…1.8.
    static func lookAwayDuration(seed: UInt64, _ n: Int) -> TimeInterval { 1 + roll(seed: seed, n * 3 + 2) * 0.8 }
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
    /// Alt ajan rolü (ofis v3): ton/aksesuar/boy buradan gelir; `modelDot` model rengini etikette minik nokta olarak taşır.
    var role: OfficeRoleStyle? = nil
    var modelDot: OfficeRGB? = nil
    /// Yardımcı karakter (temizlikçi/taşıyıcı): vektör temada önlük/baret çizilir.
    var prop: OfficeVectorCharacter.Prop = .none

    /// Üye görünümü: ana ajan model aksesuarını korur; alt ajanlarda ROL stili baskındır, model rengi nokta olarak kalır.
    static func appearance(for member: OfficeMember) -> OfficeAppearance {
        var look = appearance(for: member.badge)
        guard member.kind == .subagent else { return look }
        let role = OfficeRoles.style(forAgentType: member.label)
        look.modelDot = look.tint
        look.tint = role.tint
        look.tintBlend = role.tintBlend
        look.accessory = .none
        look.small = role.small
        look.role = role
        return look
    }

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
    static func spriteScale(small: Bool, zoom: Double) -> Double {
        guard small, zoom >= 2 else { return 1 }
        return (zoom - 1) / zoom
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

    /// Kalabalık demo: 10 oturum × (1 ana + 10 alt ajan), model ve durum karışımı. En yeni üstte.
    static func crowd(now: Date = .now) -> [AgentSession] {
        let models = ["claude-opus-4-8", "claude-sonnet-5-5", "claude-haiku-4-5", "claude-fable-1"]
        let statuses: [AgentStatus] = [.thinking, .tool("Edit"), .tool("Bash"), .waitingPermission, .idle, .tool("Read"), .idle, .thinking]
        let names = ["adalmon", "api-sunucu", "web-site", "mobil-app", "veri-boru", "docs", "ml-egitim", "altyapi", "test-otomasyon", "tasarim-sistemi"]
        let types = ["Explore", "Plan", "general-purpose", "code-reviewer", "Bash", "test-runner", "researcher", "refactor", "docs-writer", "linter"]
        return (0..<10).map { i in
            let subs = (0..<10).map { j in
                AgentSubagent(agentID: "c\(i)-\(j)", agentType: types[(i + j) % types.count], model: models[(i * 3 + j) % models.count], status: statuses[(i + j * 3) % statuses.count])
            }
            return AgentSession(id: "crowd\(i)", project: names[i], model: models[i % models.count], status: statuses[i % statuses.count],
                                startedAt: now.addingTimeInterval(-Double((10 - i) * 60)), lastEventAt: now, subagents: subs)
        }.reversed()
    }

    /// Tek oturum demo: yönetici tahtada yazıyor ("main.swift düzenliyor"), üç alt ajan farklı balonlarla (balonlar sönmez).
    static func single(now: Date = .now) -> [AgentSession] {
        [AgentSession(id: "single", project: "adalmon", model: "claude-opus-4-8", status: .tool("Edit"), startedAt: now.addingTimeInterval(-300), lastEventAt: now,
                      subagents: [AgentSubagent(agentID: "s1", agentType: "Explore", model: "claude-haiku-4-5", status: .tool("Grep"), activity: "Grep"),
                                  AgentSubagent(agentID: "s2", agentType: "general-purpose", model: "claude-sonnet-5-5", status: .tool("Edit"), activity: "Edit", target: "OfficeRoomNode.swift"),
                                  AgentSubagent(agentID: "s3", agentType: "Plan", model: "claude-opus-4-8", status: .tool("Bash"), activity: "Bash", target: "swift")],
                      activity: "Edit", target: "main.swift")]
    }

    /// Bir adım için tek anlık "ortalama sahne": önizleme testi ve statik demo.
    static var showcase: [AgentSession] { steps()[4] }
}
