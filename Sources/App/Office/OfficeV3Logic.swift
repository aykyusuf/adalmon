import Foundation

// Ofis v3: saf (SpriteKit'siz) mantık. Işık modu/gece kuralı, bilgisayar türü, boşta varyantları, temizlikçi zamanlayıcısı/rotası,
// taşıyıcı sekansı ve detay kartı veri modeli. Hepsi deterministik ve testlidir.

// MARK: Işık (gün/gece)

enum OfficeLightingMode: String, CaseIterable, Sendable {
    case auto, day, night

    var title: String {
        switch self {
        case .auto: "Otomatik"
        case .day: "Gün"
        case .night: "Gece"
        }
    }
}

enum OfficeLighting {
    static let defaultsKey = "officeLightingMode"
    /// Otomatik mod: gece 19:30 – 06:30 (yerel saat).
    static let nightStartMinutes = 19 * 60 + 30
    static let nightEndMinutes = 6 * 60 + 30
    /// Gece örtüsü ve geçiş.
    static let nightOverlayAlpha = 0.34
    static let crossfade: TimeInterval = 1

    static func storedMode(_ defaults: UserDefaults = .standard) -> OfficeLightingMode {
        defaults.string(forKey: defaultsKey).flatMap(OfficeLightingMode.init(rawValue:)) ?? .auto
    }

    static func store(_ mode: OfficeLightingMode, defaults: UserDefaults = .standard) { defaults.set(mode.rawValue, forKey: defaultsKey) }

    private static func calendar(_ tz: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal
    }

    /// Gece mi? `day`/`night` modu saate bakmaz; `auto`: yerel saat 19:30'dan (dahil) 06:30'a (hariç).
    static func isNight(mode: OfficeLightingMode, date: Date, timeZone: TimeZone = .current) -> Bool {
        switch mode {
        case .day: return false
        case .night: return true
        case .auto:
            let c = calendar(timeZone).dateComponents([.hour, .minute], from: date)
            let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            return m >= nightStartMinutes || m < nightEndMinutes
        }
    }

    /// Bir sonraki saat sınırı (19:30 ya da 06:30): tek bir `Timer` bununla kurulur; zamanlayıcı döngüsü yoktur.
    static func nextBoundary(after date: Date, timeZone: TimeZone = .current) -> Date? {
        let cal = calendar(timeZone)
        let candidates = [nightStartMinutes, nightEndMinutes].compactMap {
            cal.nextDate(after: date, matching: DateComponents(hour: $0 / 60, minute: $0 % 60), matchingPolicy: .nextTime)
        }
        return candidates.min()
    }
}

// MARK: Bilgisayar türü

/// Masa başına bilgisayar: iMac (renkli) ya da MacBook. Seçim oda + koltuk kimliğinden deterministiktir (oda yeniden kurulunca değişmez).
struct OfficeComputer: Equatable, Sendable {
    enum Kind: String, Sendable { case imac, macbook }
    enum Color: String, CaseIterable, Sendable { case blue, green, pink, silver, gray }

    var kind: Kind
    var color: Color

    static let imacColors: [Color] = [.blue, .green, .pink, .silver]
    static let macbookColors: [Color] = [.silver, .gray]

    /// Yönetici masası her zaman gümüş iMac.
    static let executive = OfficeComputer(kind: .imac, color: .silver)

    static func pick(roomID: String, seatID: Int) -> OfficeComputer {
        let seed = OfficeStroll.seed(for: "\(roomID)|pc|\(seatID)")
        let kind: Kind = OfficeStroll.roll(seed: seed, 0) < 0.55 ? .imac : .macbook
        let colors = kind == .imac ? imacColors : macbookColors
        let color = colors[min(colors.count - 1, Int(OfficeStroll.roll(seed: seed, 1) * Double(colors.count)))]
        return OfficeComputer(kind: kind, color: color)
    }

    /// Doku/veri adı öneki: "imac_blue", "macbook_gray".
    var artName: String { "\(kind.rawValue)_\(color.rawValue)" }
}

// MARK: Boşta varyantları

enum OfficeIdleVariant: String, CaseIterable, Sendable { case read, coffee, yawn, zzz }

enum OfficeIdle {
    /// Bir varyantın süresi (sn). Aralarında durulur; döngü zamanlayıcıyla (ucuz, sonlu SKAction) başlatılır.
    static let duration: ClosedRange<Double> = 5...9
    /// Kalkıp kahve makinesine yürüme: olasılık, iki yürüyüş arası (sn) ve bekleme (sn); odada aynı anda en çok 1-2 kişi.
    static let wanderChance = 0.3
    static let wanderGap: ClosedRange<Double> = 20...60
    static let wanderStay: ClosedRange<Double> = 5...8

    static func variant(seed: String, n: Int) -> OfficeIdleVariant {
        let r = OfficeStroll.roll(seed: OfficeStroll.seed(for: seed), n * 2)
        return OfficeIdleVariant.allCases[min(OfficeIdleVariant.allCases.count - 1, Int(r * Double(OfficeIdleVariant.allCases.count)))]
    }

    static func length(seed: String, n: Int) -> TimeInterval {
        duration.lowerBound + OfficeStroll.roll(seed: OfficeStroll.seed(for: seed), n * 2 + 1) * (duration.upperBound - duration.lowerBound)
    }

    static func stay(seed: String, n: Int) -> TimeInterval {
        wanderStay.lowerBound + OfficeStroll.roll(seed: OfficeStroll.seed(for: seed + "|stay"), n) * (wanderStay.upperBound - wanderStay.lowerBound)
    }

    static func gap(roll: Double) -> TimeInterval { wanderGap.lowerBound + roll * (wanderGap.upperBound - wanderGap.lowerBound) }

    /// Odada aynı anda kahveye/pencereye yürüyen en çok kişi: küçük odada 1, 8+ üyede 2.
    static func maxWanderers(memberCount: Int) -> Int { memberCount >= 8 ? 2 : 1 }
}

// MARK: Temizlikçi

/// Temizlikçi zamanlayıcısı (saf): her odada 90-180 sn aralıkla, yalnızca oda görünürken ve sahne duraklatılmamışken, bir kerede bir.
enum OfficeCleaner {
    static let interval: ClosedRange<Double> = 90...180
    /// Bir sonraki temizlik gecikmesi (sn): aralık içinde, oda kimliği + sayaçtan deterministik.
    static func delay(seed: String, n: Int) -> TimeInterval {
        interval.lowerBound + OfficeStroll.roll(seed: OfficeStroll.seed(for: seed + "|clean"), n) * (interval.upperBound - interval.lowerBound)
    }

    static func shouldStart(now: Date, dueAt: Date?, roomVisible: Bool, scenePaused: Bool, busy: Bool) -> Bool {
        guard roomVisible, !scenePaused, !busy, let dueAt else { return false }
        return now >= dueAt
    }

    /// S rotası: yönetici bölgesinin altından başlayıp koltuk sıraları arasındaki koridor satırlarını sırayla soldan sağa / sağdan sola
    /// dolaşır, girişe döner. Yalnızca yürünür karolar (koltuk/masa karoları yürünür değildir → oturanın yolu kesilmez).
    static func route(grid: OfficeGrid, entrance: OfficeTile, laneRows: [Int]) -> [OfficeTile] {
        var waypoints: [OfficeTile] = []
        for (i, row) in laneRows.enumerated() {
            let cols = (0..<grid.cols).filter { grid.isWalkable(OfficeTile($0, row)) }
            guard let lo = cols.first, let hi = cols.last, lo < hi else { continue }
            waypoints += i % 2 == 0 ? [OfficeTile(lo, row), OfficeTile(hi, row)] : [OfficeTile(hi, row), OfficeTile(lo, row)]
        }
        var out: [OfficeTile] = [entrance]
        for w in waypoints + [entrance] {
            guard let p = grid.path(from: out.last!, to: w) else { continue }
            out += p
        }
        return out
    }
}

// MARK: Taşıyıcı (oda büyürken masa getirir)

enum OfficeCarrierStep: String, Equatable, Sendable {
    /// Kapıdan koli/masa ile girer.
    case enter
    case walkToDesk
    /// Masa 0.4 sn yukarıdan düşer/kayar.
    case dropDesk
    /// Bilgisayar belirir.
    case showComputer
    case walkBack
    case leave
    /// Yeni ajan yürüyüp oturur.
    case seatAgent
}

enum OfficeCarrier {
    static let dropDuration: TimeInterval = 0.4
    static let growFade: TimeInterval = 0.4

    /// Yeni istasyon için tam sıra. Taşıyıcı olmadan (sahne görünmüyor/animasyonsuz) yalnızca `seatAgent`.
    static func sequence(withCarrier: Bool) -> [OfficeCarrierStep] {
        withCarrier ? [.enter, .walkToDesk, .dropDesk, .showComputer, .walkBack, .leave, .seatAgent] : [.seatAgent]
    }

    /// Büyümede yeni olan masa koltukları: yeni kademede olup eski kademede (karo olarak) bulunmayanlar.
    static func newDeskSeats(old: [OfficeSeat], new: [OfficeSeat]) -> [OfficeSeat] {
        let oldTiles = Set(old.filter { $0.kind == .desk }.map(\.tile))
        return new.filter { $0.kind == .desk && !oldTiles.contains($0.tile) }
    }
}

// MARK: Detay kartı

struct OfficeDetailCard: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        var title: String
        var value: String
    }

    struct Child: Equatable, Sendable {
        var role: String
        var status: String
    }

    var memberID: String
    var isSession: Bool
    var title: String
    var roleName: String?
    var badge: AgentModelBadge
    var status: String
    var tool: String?
    var startedAt: Date?
    var parentTitle: String?
    var subagentCount: Int
    var children: [Child]

    /// Tek tıkla açılan kart: oturum adı/rol, model, durum, araç (+hedef), süre, üst oturum adı, alt ajan sayısı/listesi.
    static func make(member: OfficeMember, members: [OfficeMember], spawnedAt: Date?) -> OfficeDetailCard {
        let isSession = member.kind == .session
        let rid = member.parentID ?? member.id
        let subs = members.filter { $0.parentID == rid }
        let parent = members.first { $0.id == rid }
        var tool: String?
        if member.status.isWorking || member.status == .waitingPermission, let a = member.activity {
            tool = [a, member.target].compactMap { $0 }.joined(separator: " · ")
        }
        return OfficeDetailCard(
            memberID: member.id, isSession: isSession, title: isSession ? member.label : OfficeRoles.style(forAgentType: member.label).name,
            roleName: isSession ? "ana ajan" : OfficeRoles.style(forAgentType: member.label).name, badge: member.badge, status: member.status.label,
            tool: tool, startedAt: member.startedAt ?? spawnedAt, parentTitle: isSession ? nil : parent?.label, subagentCount: subs.count,
            children: isSession ? subs.map { Child(role: OfficeRoles.style(forAgentType: $0.label).name, status: $0.status.label) } : [])
    }

    /// "m:ss" ya da "h:mm:ss".
    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    func rows(now: Date) -> [Row] {
        var out: [Row] = [Row(title: "Durum", value: status)]
        if let tool { out.append(Row(title: "Araç", value: tool)) }
        if let startedAt { out.append(Row(title: "Süre", value: Self.duration(now.timeIntervalSince(startedAt)))) }
        if let parentTitle { out.append(Row(title: "Üst oturum", value: parentTitle)) }
        out.append(Row(title: "Alt ajan", value: "\(subagentCount)"))
        return out
    }

    /// Fare üstü ipucu: "ad · rol · model · durum".
    var tooltip: String {
        [title, isSession ? nil : roleName, badge.label, status].compactMap { $0 }.joined(separator: " · ")
    }
}
