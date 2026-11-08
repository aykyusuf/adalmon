import Foundation

// Ajan ofisi (oturum başına oda): saf planlama mantığı (SpriteKit/SwiftUI yok). Oturum → oda, oda boyut kademesi, odadaki
// koltuk ataması ve taşma sayacı burada; sahne yalnızca çıktıyı uygular.

/// Oda boyut kademesi (ofis v3): masa istasyonu sayısı 2, 4, 6, 8, 12, 16 (+ yönetici koltuğu). Her kademenin şablonu
/// `OfficeRoomTemplates.layout` ile programla üretilir; üst kademe alt kademenin üst kümesidir (oturanlar yerinde kalır).
enum OfficeRoomTier: Int, CaseIterable, Comparable, Sendable {
    case s2, s4, s6, s8, s12, s16

    /// Bir odada en çok gösterilen karakter (yönetici + 16 istasyon); fazlası "+N" rozetidir.
    static let maxStations = 16
    static let maxCharacters = maxStations + 1

    static func < (a: OfficeRoomTier, b: OfficeRoomTier) -> Bool { a.rawValue < b.rawValue }

    var stations: Int { [2, 4, 6, 8, 12, 16][rawValue] }
    /// Yönetici dahil koltuk sayısı.
    var capacity: Int { stations + 1 }
    /// Her odada kahve makinesi vardır.
    var hasCoffee: Bool { true }
    var key: String { "s\(stations)" }

    /// Üye sayısını (oturum + alt ajanlar) karşılayan en küçük kademe; 17'den fazlası da en büyükte kalır.
    static func tier(forCount n: Int) -> OfficeRoomTier {
        allCases.first { n <= $0.capacity } ?? .s16
    }
}

/// Bir odanın bir güncellemedeki planı.
struct OfficeRoomPlan: Equatable, Identifiable, Sendable {
    /// Oturum kimliği; boş ofis için `OfficeRoomPlanner.emptyRoomID`.
    var id: String
    var tier: OfficeRoomTier
    /// Levha başlığı (oturum adı) ve model rozeti; ajan yokken nil.
    var title: String?
    var badge: AgentModelBadge?
    var groupIndex: Int
    var placements: [String: OfficePlacement]
    /// Önceki plandan düşen (çıkışa yürüyecek) üyeler.
    var departed: [String]
    /// Kademe değişti: sahne odayı yeni şablonla baştan kurar; oturanlar karo olarak aynı koltukta kalır (yürümeden yerleştirilir).
    var reseated: Bool
    /// Kademe değiştiyse önceki kademe (büyüme animasyonu için).
    var previousTier: OfficeRoomTier? = nil
    var memberCount: Int

    var overflowCount: Int { placements.values.filter { $0 == .overflow }.count }
    var isPlaceholder: Bool { id == OfficeRoomPlanner.emptyRoomID }
}

struct OfficeRoomsPlan: Equatable, Sendable {
    /// Gösterim sırasıyla (oturum sırası = başlangıç zamanı, eskiden yeniye).
    var rooms: [OfficeRoomPlan]
    /// Önceki plandan kalkan odalar (oturum kapandı).
    var removed: [String]
}

/// Durumlu oda planlayıcı. Her oturum kendi odasını alır; oda, üye sayısına göre kademe seçer. Büyüme hemen olur, küçülme
/// yalnızca üye sayısı alt kademenin kapasitesinin bir altına inince (kademe titremesin). Koltuk ataması odanın içinde
/// `OfficeAssigner` ile yapılır: oturum ilk masaya, alt ajanlar ebeveyne en yakın boş masaya, sonra salon koltuklarına oturur.
struct OfficeRoomPlanner: Sendable {
    static let emptyRoomID = "__empty__"
    static let emptyTier = OfficeRoomTier.s6

    private struct State: Sendable {
        var tier: OfficeRoomTier
        var assigner: OfficeAssigner
    }

    private let seats: [OfficeRoomTier: [OfficeSeat]]
    private var states: [String: State] = [:]

    init(seats: [OfficeRoomTier: [OfficeSeat]]) { self.seats = seats }

    /// Ağaç sırasıyla gelen üyeleri (oturumlar eskiden yeniye, alt ajanlar kendi oturumundan sonra) odalara böler.
    mutating func update(members: [OfficeMember]) -> OfficeRoomsPlan {
        var order: [String] = []
        var groups: [String: [OfficeMember]] = [:]
        for m in members {
            let rid = m.parentID ?? m.id
            if groups[rid] == nil { order.append(rid) }
            groups[rid, default: []].append(m)
        }
        if order.isEmpty { order = [Self.emptyRoomID]; groups[Self.emptyRoomID] = [] }

        let removed = states.keys.filter { groups[$0] == nil }.sorted()
        for id in removed { states[id] = nil }

        var rooms: [OfficeRoomPlan] = []
        for rid in order {
            let ms = groups[rid] ?? []
            let n = ms.count
            let desired = rid == Self.emptyRoomID ? Self.emptyTier : OfficeRoomTier.tier(forCount: n)
            let current = states[rid]?.tier
            let tier: OfficeRoomTier
            if let current {
                if desired > current { tier = desired }
                else if desired < current, n <= desired.capacity - 1 { tier = desired }
                else { tier = current }
            } else {
                tier = desired
            }
            let reseated = current != nil && tier != current
            if current == nil {
                states[rid] = State(tier: tier, assigner: OfficeAssigner(seats: seats[tier] ?? []))
            } else if reseated, let old = states[rid], let current {
                // Oturanlar karo olarak aynı koltukta kalır (kademeler iç içe); kalmayanlar yeniden seçilir.
                var carry: [String: OfficeSeat] = [:]
                let oldSeats = seats[current] ?? []
                for (member, seatID) in old.assigner.seatOf { if let seat = oldSeats.first(where: { $0.id == seatID }) { carry[member] = seat } }
                states[rid] = State(tier: tier, assigner: OfficeAssigner(seats: seats[tier] ?? [], carrying: carry))
            }
            var state = states[rid]!
            let plan = state.assigner.update(members: ms)
            states[rid] = state
            let session = ms.first { $0.kind == .session }
            rooms.append(OfficeRoomPlan(id: rid, tier: tier, title: session?.label, badge: session?.badge, groupIndex: session?.groupIndex ?? 0,
                                        placements: plan.placements, departed: plan.departed, reseated: reseated,
                                        previousTier: reseated ? current : nil, memberCount: n))
        }
        return OfficeRoomsPlan(rooms: rooms, removed: removed)
    }
}
