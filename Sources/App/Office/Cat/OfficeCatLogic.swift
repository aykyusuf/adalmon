import Foundation

// Ofis kedisi: SAF mantık (SpriteKit'siz, saat/RNG enjekte edilebilir). Çizim `OfficeCatArt`, sahne bağlantısı `OfficeCatController`.
//
// Davranış tasarımı misak-app'teki kediden (Flutter; yalnızca OKUNDU, kod kopyalanmadı) uyarlanmıştır:
//   /Users/yusufayik/Development/projects/misak-app/lib/features/quran/presentation/widgets/nur_cat/cat_brain.dart
//     - mola: oturup etrafa bak (~3,2 sn) + ara sıra tımar parçası; 6'da 1 kuyruk kovalama
//     - uyku: uzun uyku (1-2 kat), uyanış = gerinme 2,3 sn → esneme 0,9 sn → oturma → sabit sırayla tımar seansı
//     - zoomies: çömel 0,9 sn → uçtan uca hızlı koşu → oturup yalanma; iki koşu arası en az 4 dk
//     - dokunma: durur, bize döner, yavaş göz kırpar (sevgi), mutlu ifade
//   .../nur_cat/cat_pose.dart: tımar süreleri (yüz yıkama 5,7 / yalanma 1 / göğüs 4 / silkinme 1 sn)
// Ofise özgü olanlar (masaya tırmanma, çalışan ajanın yanına gitme, robot süpürgeden kaçma, odalar arası geçiş) bu projeye aittir.

enum OfficeCat {
    static let defaultsKey = "officeCatEnabled"

    /// Varsayılan AÇIK; kayıt yoksa true.
    static func storedEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? true
    }

    static func store(_ on: Bool, defaults: UserDefaults = .standard) { defaults.set(on, forKey: defaultsKey) }
}

/// Enjekte edilebilir rastgelelik: 0..<1 döndüren kapanış.
struct OfficeCatRandom {
    var next: () -> Double

    static var system: OfficeCatRandom { OfficeCatRandom { .random(in: 0..<1) } }

    /// Deterministik (SplitMix64) — testler ve önizleme için.
    static func seeded(_ seed: UInt64) -> OfficeCatRandom {
        var n = 0
        return OfficeCatRandom {
            n += 1
            return OfficeStroll.roll(seed: seed, n)
        }
    }

    /// Sabit değerler dizisi (döngüsel) — testlerde tam kontrol için.
    static func sequence(_ values: [Double]) -> OfficeCatRandom {
        var i = 0
        return OfficeCatRandom {
            defer { i += 1 }
            return values[i % values.count]
        }
    }

    func range(_ r: ClosedRange<Double>) -> Double { r.lowerBound + next() * (r.upperBound - r.lowerBound) }
    func int(_ n: Int) -> Int { min(n - 1, Int(next() * Double(n))) }
    func pick<T>(_ items: [T]) -> T? { items.isEmpty ? nil : items[int(items.count)] }
}

enum OfficeCatPose: String, CaseIterable, Sendable {
    case stand, walk, run, sit, sitTail, groomFace, groomChest, lick, yawn, stretch, crouch, leapUp, leapDown, loaf, lieKeys, sleep, alert, happy

    /// Bu pozun kare sayısı (yürüme 4, koşu/tımar/kuyruk 2, diğerleri 1).
    var frameCount: Int {
        switch self {
        case .walk: 4
        case .run, .groomFace, .groomChest, .lick, .sitTail: 2
        default: 1
        }
    }
}

/// Kedinin durduğu yer: zemin karosu ya da bir masa/yüzey.
enum OfficeCatSpot: Equatable, Sendable {
    case floor(OfficeTile)
    case perch(Int)
}

/// Kedinin çıkabildiği yüzey (masa üstü). `id` dünya içindeki sıra numarasıdır.
struct OfficePerch: Equatable, Sendable {
    var id: Int
    var assetID: String
    /// Yüzeyin ortasındaki karo sütunu ve mobilyanın sol-üst satırı / yüksekliği (karo).
    var col: Int
    var row: Int
    var heightTiles: Int
    /// Mobilya tabanından yüzeye dünya birimi yükseklik (kedinin ayakları).
    var surfaceLift: CGFloat
    /// Zıplanabilen, odanın girişinden ulaşılabilir komşu karolar.
    var approaches: [OfficeTile]
}

/// Bir odanın kedi açısından dünyası: ulaşılabilir zemin + tırmanılabilir yüzeyler. Yalnızca kapıdan ulaşılabilen karolar/masalar vardır.
struct OfficeCatWorld: Equatable, Sendable {
    var grid: OfficeGrid
    var entrance: OfficeTile
    var floor: [OfficeTile]
    var perches: [OfficePerch]

    /// Tırmanılabilir yüzeyler: (mobilya kimliği, yüzey yüksekliği). Masa üstünde PC olmayan orta karo (3 geniş masa) ya da kahve masasının boş yarısı.
    static let perchAssets: [String: (lift: CGFloat, centerOffset: Int)] = [
        "DESK_FRONT": (12, 1),
        "COFFEE_TABLE": (12, 1),
    ]

    static func make(grid: OfficeGrid, entrance: OfficeTile, furniture: [OfficeFurniturePlacement], catalog: [String: OfficeAsset]) -> OfficeCatWorld {
        let reachable = grid.reachable(from: entrance)
        let floor = reachable.filter { grid.isWalkable($0) }.sorted { ($0.row, $0.col) < ($1.row, $1.col) }
        var perches: [OfficePerch] = []
        for f in furniture {
            guard let spec = perchAssets[f.assetID], let a = catalog[f.assetID] else { continue }
            // Ayak izinin çevresindeki (arka plan satırı dahil) ulaşılabilir yürünür karolar; yüzeyin alt-orta karosuna ≤ 3 uzaklıkta.
            let anchor = OfficeTile(f.col + spec.centerOffset, f.row + a.footprintH - 1)
            var approaches: [OfficeTile] = []
            for c in (f.col - 1)...(f.col + a.footprintW) { for r in (f.row - 1)...(f.row + a.footprintH) {
                let t = OfficeTile(c, r)
                if grid.isWalkable(t), reachable.contains(t), t.manhattan(to: anchor) <= 3 { approaches.append(t) }
            } }
            approaches.sort { ($0.row, $0.col) < ($1.row, $1.col) }
            guard !approaches.isEmpty else { continue }
            perches.append(OfficePerch(id: perches.count, assetID: f.assetID, col: f.col + spec.centerOffset, row: f.row, heightTiles: a.footprintH,
                                       surfaceLift: spec.lift, approaches: approaches))
        }
        return OfficeCatWorld(grid: grid, entrance: entrance, floor: floor, perches: perches)
    }

    func perch(_ id: Int) -> OfficePerch? { perches.indices.contains(id) ? perches[id] : nil }

    /// `from` karosundan perch'e en yakın ulaşılabilir yaklaşma karosu ve oraya yol.
    func approach(to perch: OfficePerch, from tile: OfficeTile) -> (tile: OfficeTile, route: [OfficeTile])? {
        var best: (tile: OfficeTile, route: [OfficeTile])?
        for t in perch.approaches {
            guard let r = grid.path(from: tile, to: t) else { continue }
            if best == nil || r.count < best!.route.count { best = (t, r) }
        }
        return best
    }

    /// `tile`e yakın (manhattan ≤ radius), ulaşılabilir, boş zemin karoları: çalışan ajanın yanına gitmek için.
    func tiles(near tile: OfficeTile, radius: Int) -> [OfficeTile] {
        floor.filter { $0.manhattan(to: tile) <= radius && $0 != tile }
    }
}

// MARK: Plan

struct OfficeCatStep: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case walk(to: OfficeTile, fast: Bool)
        case jumpUp(perch: Int)
        case jumpDown(to: OfficeTile)
        /// `animated == false`: sabit poz (hiçbir SKAction yok; çıkış bir sonraki zamanlayıcı vuruşunda).
        case pose(OfficeCatPose, duration: TimeInterval, animated: Bool)
        case travel(roomID: String)
    }
    var kind: Kind

    static func walk(_ t: OfficeTile, fast: Bool = false) -> OfficeCatStep { .init(kind: .walk(to: t, fast: fast)) }
    static func up(_ p: Int) -> OfficeCatStep { .init(kind: .jumpUp(perch: p)) }
    static func down(_ t: OfficeTile) -> OfficeCatStep { .init(kind: .jumpDown(to: t)) }
    static func pose(_ p: OfficeCatPose, _ d: TimeInterval, animated: Bool = false) -> OfficeCatStep { .init(kind: .pose(p, duration: d, animated: animated)) }
    static func travel(_ id: String) -> OfficeCatStep { .init(kind: .travel(roomID: id)) }
}

enum OfficeCatActivity: String, CaseIterable, Sendable {
    case wander, moleSit, groom, tailChase, visitAgent, climb, perchRest, descend, nap, zoomies, flee, travel
}

struct OfficeCatPlan: Equatable, Sendable {
    var activity: OfficeCatActivity
    var steps: [OfficeCatStep]
    /// Plan bittiğinde kedinin bulunacağı yer (travel hariç: orada oda değişir ve zemin karosu girişte olur).
    var end: OfficeCatSpot
}

struct OfficeCatContext: Sendable {
    var world: OfficeCatWorld
    var spot: OfficeCatSpot
    /// Çalışan (yazan/okuyan) ajanların koltuk karoları.
    var workingSeats: [OfficeTile] = []
    /// Bu odada robot süpürge / temizlikçi çalışıyor.
    var cleaning = false
    var isNight = false
    /// Geçilebilecek diğer görünür odalar.
    var otherRooms: [String] = []
    /// Son uykudan beri uyanık geçen ve son zoomies'ten beri geçen süre (sn).
    var awakeFor: TimeInterval = 0
    var sinceZoomies: TimeInterval = .infinity
}

// MARK: Beyin

enum OfficeCatBrain {
    // Süreler: misak-app cat_brain.dart / cat_pose.dart değerleri (sn).
    static let wakeStretch: TimeInterval = 2.3
    static let wakeYawn: TimeInterval = 0.9
    static let lookAround: TimeInterval = 3.2
    static let faceWash: TimeInterval = 5.7
    static let chestWash: TimeInterval = 4
    static let lipLick: TimeInterval = 1
    static let crouch: TimeInterval = 0.9
    static let zoomiesGap: TimeInterval = 240
    static let greetHold: TimeInterval = 4
    static let sleepDuration: ClosedRange<Double> = 90...240
    static let perchHold: ClosedRange<Double> = 25...90
    static let watchHold: ClosedRange<Double> = 20...50
    static let sitHold: ClosedRange<Double> = 12...30

    /// Ağırlıklı seçim: `roll` 0..<1.
    static func weightedPick<T>(_ items: [(T, Double)], roll: Double) -> T? {
        let valid = items.filter { $0.1 > 0 }
        let total = valid.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var x = min(max(roll, 0), 0.999_999) * total
        for (item, w) in valid {
            if x < w { return item }
            x -= w
        }
        return valid.last?.0
    }

    /// Kullanılabilir etkinlikler ve ağırlıkları (saf; testlerde incelenir).
    static func weights(_ c: OfficeCatContext) -> [(OfficeCatActivity, Double)] {
        if c.cleaning { return [(.flee, 1)] }
        let sleepy = c.isNight ? 3.5 : 1.2
        let nap = sleepy + (c.awakeFor > 300 ? 2 : 0)
        switch c.spot {
        case .floor:
            return [
                (.wander, 3), (.moleSit, 2.2), (.groom, 1.4), (.tailChase, 0.5),
                (.visitAgent, c.workingSeats.isEmpty ? 0 : 2),
                (.climb, c.world.perches.isEmpty ? 0 : 2.6),
                (.nap, nap),
                (.zoomies, !c.isNight && c.sinceZoomies >= zoomiesGap && c.world.floor.count >= 6 ? 0.6 : 0),
                (.travel, c.otherRooms.isEmpty ? 0 : 0.7),
            ]
        case .perch:
            return [(.perchRest, 3), (.groom, 1.5), (.descend, 2), (.nap, nap * 0.8)]
        }
    }

    static func plan(_ c: OfficeCatContext, rng: OfficeCatRandom) -> OfficeCatPlan {
        let choice = weightedPick(weights(c), roll: rng.next()) ?? .moleSit
        return build(choice, c, rng: rng) ?? fallback(c, rng: rng)
    }

    /// Seçilen etkinlik kurulamazsa (hedef yok) güvenli bir oturma.
    static func fallback(_ c: OfficeCatContext, rng: OfficeCatRandom) -> OfficeCatPlan {
        OfficeCatPlan(activity: .moleSit, steps: [.pose(.sit, rng.range(sitHold))], end: c.spot)
    }

    static func groomSession(rng: OfficeCatRandom, full: Bool = false) -> [OfficeCatStep] {
        // Sıra sabit: dudak → yüz → (göğüs) → silkinme; ortadakiler rastgele (misak `_session`).
        var steps: [OfficeCatStep] = [.pose(.lick, lipLick, animated: true), .pose(.groomFace, faceWash, animated: true)]
        if full || rng.next() < 0.6 { steps.append(.pose(.groomChest, chestWash, animated: true)) }
        steps.append(.pose(.sitTail, 1.0, animated: true))   // silkinme / kuyruk
        return steps
    }

    static func build(_ a: OfficeCatActivity, _ c: OfficeCatContext, rng: OfficeCatRandom) -> OfficeCatPlan? {
        let world = c.world
        switch (a, c.spot) {
        case (.wander, .floor(let here)):
            let far = world.floor.filter { $0.manhattan(to: here) >= 3 }
            guard let target = rng.pick(far) else { return nil }
            return OfficeCatPlan(activity: a, steps: [.walk(target), .pose(.sit, rng.range(sitHold))], end: .floor(target))

        case (.moleSit, _):
            // Oturup etrafa bak; ara sıra bir tımar parçası.
            var steps: [OfficeCatStep] = [.pose(.sit, lookAround, animated: true)]
            if rng.next() < 0.5 { steps.append(.pose(.groomChest, chestWash, animated: true)) }
            steps.append(.pose(.sit, rng.range(sitHold)))
            return OfficeCatPlan(activity: a, steps: steps, end: c.spot)

        case (.groom, _):
            return OfficeCatPlan(activity: a, steps: groomSession(rng: rng) + [.pose(.sit, rng.range(sitHold))], end: c.spot)

        case (.tailChase, _):
            return OfficeCatPlan(activity: a, steps: [.pose(.sitTail, 3, animated: true), .pose(.stand, 0.6, animated: true), .pose(.sit, rng.range(sitHold))], end: c.spot)

        case (.visitAgent, .floor(let here)):
            guard let seat = rng.pick(c.workingSeats) else { return nil }
            let near = world.tiles(near: seat, radius: 2)
            guard let target = rng.pick(near) else { return nil }
            return OfficeCatPlan(activity: a, steps: [.walk(target), .pose(.sit, rng.range(watchHold))], end: .floor(target))
                .nonEmpty(here != target)

        case (.climb, .floor(let here)):
            guard let perch = rng.pick(world.perches), let ap = world.approach(to: perch, from: here) else { return nil }
            let rest = restOnPerch(rng: rng)
            return OfficeCatPlan(activity: a, steps: (ap.route.isEmpty ? [] : [.walk(ap.tile)]) + [.up(perch.id)] + rest, end: .perch(perch.id))

        case (.perchRest, .perch):
            return OfficeCatPlan(activity: a, steps: restOnPerch(rng: rng), end: c.spot)

        case (.descend, .perch(let id)):
            guard let perch = world.perch(id), let landing = rng.pick(perch.approaches) else { return nil }
            return OfficeCatPlan(activity: a, steps: [.pose(.stretch, 1.4, animated: true), .down(landing), .pose(.sit, rng.range(1...4))], end: .floor(landing))

        case (.nap, _):
            // Önce esneme, kıvrılıp uzun uyku; uyanış: gerinme → esneme → oturma → tımar (misak `_wakeUp`).
            var steps: [OfficeCatStep] = [.pose(.yawn, wakeYawn, animated: true), .pose(.sleep, rng.range(sleepDuration * (c.isNight ? 1.5 : 1)))]
            steps += [.pose(.stretch, wakeStretch, animated: true), .pose(.yawn, wakeYawn, animated: true), .pose(.sit, 1.0, animated: true)]
            steps += groomSession(rng: rng)
            return OfficeCatPlan(activity: a, steps: steps, end: c.spot)

        case (.zoomies, .floor(let here)):
            let row = world.floor.filter { $0.row == here.row }
            guard let lo = row.min(by: { $0.col < $1.col }), let hi = row.max(by: { $0.col < $1.col }), hi.col - lo.col >= 3 else { return nil }
            let first = here.col - lo.col > hi.col - here.col ? lo : hi
            let second = first == lo ? hi : lo
            return OfficeCatPlan(activity: a, steps: [.pose(.crouch, crouch, animated: true), .walk(first, fast: true), .walk(second, fast: true), .walk(here, fast: true),
                                                    .pose(.sit, 1.0, animated: true), .pose(.lick, lipLick, animated: true), .pose(.sit, rng.range(sitHold))], end: .floor(here))

        case (.flee, .floor(let here)):
            // Robot süpürgeden kaç: en yakın masaya çık ve tedirgin bekle; masa yoksa girişe en uzak köşeye.
            let ranked = world.perches.compactMap { p in world.approach(to: p, from: here).map { (p, $0) } }.sorted { $0.1.route.count < $1.1.route.count }
            if let (perch, ap) = ranked.first {
                return OfficeCatPlan(activity: a, steps: [.walk(ap.tile, fast: true), .up(perch.id), .pose(.alert, 8)], end: .perch(perch.id))
            }
            let far = world.floor.max { $0.manhattan(to: here) < $1.manhattan(to: here) }
            guard let corner = far else { return nil }
            return OfficeCatPlan(activity: a, steps: [.walk(corner, fast: true), .pose(.alert, 8)], end: .floor(corner))

        case (.flee, .perch):
            return OfficeCatPlan(activity: a, steps: [.pose(.alert, 8)], end: c.spot)

        case (.travel, .floor):
            guard let room = rng.pick(c.otherRooms) else { return nil }
            return OfficeCatPlan(activity: a, steps: [.walk(world.entrance, fast: false), .travel(room), .pose(.sit, rng.range(1...4))], end: .floor(world.entrance))

        default:
            return nil
        }
    }

    /// Masada ne yapar: oturur, somun gibi yatar, klavyeye uzanır ya da uyur.
    static func restOnPerch(rng: OfficeCatRandom) -> [OfficeCatStep] {
        let hold = rng.range(perchHold)
        switch weightedPick([(0, 3.0), (1, 2.5), (2, 2.5), (3, 1.5)], roll: rng.next()) ?? 0 {
        case 0: return [.pose(.sit, hold)]
        case 1: return [.pose(.loaf, hold)]
        case 2: return [.pose(.lieKeys, hold)]
        default: return [.pose(.sleep, hold * 2)]
        }
    }

    /// Tıklama tepkisi: durur, bize döner, mutlu poz (misak `greet`).
    static func greet() -> [OfficeCatStep] { [.pose(.happy, greetHold, animated: true)] }

    /// Adımların yer değiştirme simülasyonu: planın başlangıç yerinden bittiği yere tutarlı olup olmadığı (testler).
    static func endSpot(of steps: [OfficeCatStep], from start: OfficeCatSpot, world: OfficeCatWorld) -> OfficeCatSpot? {
        var spot = start
        for s in steps {
            switch (s.kind, spot) {
            case (.walk(let t, _), .floor): spot = .floor(t)
            case (.jumpUp(let p), .floor): spot = .perch(p)
            case (.jumpDown(let t), .perch): spot = .floor(t)
            case (.pose, _): break
            case (.travel, .floor): spot = .floor(world.entrance)
            default: return nil
            }
        }
        return spot
    }
}

private extension OfficeCatPlan {
    func nonEmpty(_ ok: Bool) -> OfficeCatPlan? { ok ? self : nil }
}

private func * (r: ClosedRange<Double>, k: Double) -> ClosedRange<Double> { (r.lowerBound * k)...(r.upperBound * k) }
