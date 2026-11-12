import Foundation
import SpriteKit

/// Ofis kedisinin sahne tarafı: planı (`OfficeCatBrain`) SpriteKit eylemlerine çevirir. Kedi düğümü bulunduğu odanın `content` altındadır;
/// oda görünmezken eylemleri kendiliğinden durur.
///
/// PİL: ayrı zamanlayıcı/`repeatForever` YOK.
///  - Yürüme/zıplama/tımar: SONLU `SKAction`; biter bitmez sıradaki adım (durum değişiminde güncelleme, kare başı değil).
///  - Sabit pozlar (oturma, somun, klavyede yatma, UYKU): hiçbir eylem çalışmaz; `isAnimating == false` olduğundan görünüm duraklayabilir.
///    Çıkış, ofisin mevcut düşük frekanslı tek zamanlayıcısından (`OfficeScene.wanderTick`, ~12 sn) gelen `tick(now:)` ile olur.
///  - Bir poz değişimi sabit kareyi değiştirdiğinde `onChange` çağrılır (duraklatılmış görünüm son kareyi bir kez çizer).
@MainActor
final class OfficeCatController {
    let root = SKNode()
    private let sprite = SKSpriteNode()
    private let textures: OfficeCatTextures
    private(set) weak var room: OfficeRoomNode?
    private(set) var roomID: String?
    private(set) var spot = OfficeCatSpot.floor(OfficeTile(0, 0))
    private(set) var pose = OfficeCatPose.sit
    private(set) var frame = 0
    private(set) var plan: OfficeCatPlan?
    private(set) var holdUntil: Date?
    private(set) var busy = false
    private(set) var facingLeft = false
    private(set) var night = false
    private(set) var lastActivity: OfficeCatActivity?
    private var steps: [OfficeCatStep] = []
    private var completion: (() -> Void)?
    private var token = 0
    private var awakeSince: Date
    private var lastZoomies: Date?
    private var reaction: SKNode?

    var rng: OfficeCatRandom
    var clock: () -> Date = { .now }
    /// Görsel/animasyon durumu değişti (ev sahibi görünümü uyandırır / duraklatma kararını yeniden verir).
    var onChange: (() -> Void)?
    /// Geçilebilecek diğer görünür odalar ve bir odayı kimliğiyle bulma (sahne verir).
    var otherRooms: () -> [String] = { [] }
    var roomLookup: (String) -> OfficeRoomNode? = { _ in nil }

    /// Şu an çalışan (sonlu) eylem var mı; sabit poz ve uyku `false`.
    var isAnimating: Bool { busy || reaction != nil }
    var isAsleep: Bool { pose == .sleep && !busy }
    var hasActions: Bool { root.hasActions() || sprite.hasActions() || (reaction != nil) }

    init(theme: OfficeTheme, rng: OfficeCatRandom = .system, now: Date = .now) {
        textures = OfficeCatTextures(theme: theme)
        self.rng = rng
        awakeSince = now
        sprite.size = CGSize(width: OfficeCatArt.canvasW, height: OfficeCatArt.canvasH)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 1 - OfficeCatArt.groundY / CGFloat(OfficeCatArt.canvasH))
        root.addChild(sprite)
        root.name = "officeCat"
    }

    // MARK: Yerleşim

    /// Kediyi odaya koyar (var olan planı/eylemleri sıfırlar). `spot` zemin karosu ya da masa olabilir.
    func host(in room: OfficeRoomNode, at newSpot: OfficeCatSpot, now: Date? = nil) {
        let now = now ?? clock()
        cancel()
        self.room = room
        roomID = room.id
        room.attachCat(root)
        spot = newSpot
        placeAtSpot()
        plan = nil; steps = []
        setPose(.sit)
        holdUntil = now.addingTimeInterval(rng.range(2...6))
        onChange?()
    }

    /// Kedi odasından ayrıldı / oda yok edildi: düğüm kaldırılır, plan sıfırlanır (bir sonraki vuruşta yeni odaya konur).
    func detach() {
        cancel()
        root.removeFromParent()
        room = nil; roomID = nil
        plan = nil; steps = []; holdUntil = nil
    }

    private func placeAtSpot() {
        guard let room else { return }
        switch spot {
        case .floor(let t):
            root.position = room.point(t)
            root.zPosition = room.tileZ(t)
        case .perch(let id):
            if let p = room.catWorld.perch(id) {
                let pp = room.perchPoint(p)
                root.position = pp.point
                root.zPosition = pp.z
            }
        }
    }

    func setNight(_ on: Bool) {
        guard on != night else { return }
        night = on
        applyFrame()
    }

    // MARK: Poz

    private func setPose(_ p: OfficeCatPose, frame f: Int = 0) {
        pose = p; frame = f
        applyFrame()
    }

    private func applyFrame() {
        sprite.texture = textures.texture(pose, frame: frame, night: night)
    }

    private func face(towards x: CGFloat) {
        guard abs(x - root.position.x) > 0.5 else { return }
        facingLeft = x < root.position.x
        sprite.xScale = facingLeft ? -1 : 1
    }

    // MARK: Vuruş

    /// Düşük frekanslı zamanlayıcı vuruşu: bekleme bitti mi, süpürge geldi mi, sırada adım var mı. Görsel bir değişiklik olduysa true.
    @discardableResult
    func tick(now: Date) -> Bool {
        guard let room else { return false }
        if busy { return false }
        // Robot süpürge/temizlikçi başladı: kaç (yalnızca sabit beklerken; hareket halinde adım bitince yakalanır).
        if room.isCleaning, plan?.activity != .flee {
            startPlan(OfficeCatBrain.build(.flee, context(now), rng: rng) ?? OfficeCatBrain.fallback(context(now), rng: rng), now: now)
            return true
        }
        if let h = holdUntil, now < h { return false }
        holdUntil = nil
        if steps.isEmpty { startPlan(OfficeCatBrain.plan(context(now), rng: rng), now: now) } else { advance(now: now) }
        return true
    }

    func context(_ now: Date) -> OfficeCatContext {
        let world = room?.catWorld ?? OfficeCatWorld(grid: OfficeGrid(cols: 1, rows: 1, walkable: [false]), entrance: OfficeTile(0, 0), floor: [], perches: [])
        return OfficeCatContext(world: world, spot: spot, workingSeats: room?.workingSeatTiles() ?? [], cleaning: room?.isCleaning ?? false, isNight: night,
                                otherRooms: otherRooms(), awakeFor: now.timeIntervalSince(awakeSince), sinceZoomies: lastZoomies.map { now.timeIntervalSince($0) } ?? .infinity)
    }

    func startPlan(_ p: OfficeCatPlan, now: Date) {
        plan = p
        lastActivity = p.activity
        steps = p.steps
        if p.activity == .zoomies { lastZoomies = now }
        advance(now: now)
    }

    // MARK: Adımlar

    private func advance(now: Date) {
        guard room != nil else { return }
        guard !steps.isEmpty else {
            // Plan bitti; bir sonraki vuruşta yenisi.
            plan = plan.map { var q = $0; q.steps = []; return q }
            if busy { busy = false; onChange?() }
            return
        }
        let step = steps.removeFirst()
        switch step.kind {
        case .pose(let p, let d, let animated):
            if p == .sleep { awakeSince = now }
            if animated { animatePose(p, duration: d) } else { holdPose(p, duration: d, now: now) }
        case .walk(let target, let fast):
            walk(to: target, fast: fast, now: now)
        case .jumpUp(let id):
            jumpUp(perch: id, now: now)
        case .jumpDown(let tile):
            jumpDown(to: tile, now: now)
        case .travel(let id):
            travel(to: id, now: now)
        }
    }

    /// Sabit poz: eylem yok, yalnızca doku. Çıkış `tick`.
    private func holdPose(_ p: OfficeCatPose, duration: TimeInterval, now: Date) {
        busy = false
        setPose(p)
        holdUntil = now.addingTimeInterval(duration)
        onChange?()
    }

    /// Sonlu animasyonlu poz (tımar, esneme, çömelme...). Biter bitmez sıradaki adım.
    private func animatePose(_ p: OfficeCatPose, duration: TimeInterval) {
        setPose(p)
        var seq: [SKAction] = []
        if p.frameCount > 1 {
            let per: TimeInterval = p == .sitTail ? 0.5 : 0.45
            let n = max(1, Int((duration / (per * Double(p.frameCount))).rounded()))
            let tex = (0..<p.frameCount).map { textures.texture(p, frame: $0, night: night) }
            let cycle = SKAction.animate(with: tex, timePerFrame: per, resize: false, restore: false)
            seq.append(.repeat(cycle, count: n))
        } else {
            seq.append(.wait(forDuration: duration))
        }
        run(.sequence(seq), on: sprite, key: "pose") { [weak self] in
            self?.frame = 0
            self?.applyFrame()
        }
    }

    private func walk(to target: OfficeTile, fast: Bool, now: Date) {
        guard let room, case .floor(let here) = spot, let route = room.catWorld.grid.path(from: here, to: target), !route.isEmpty else {
            advance(now: now); return
        }
        let stepTime: TimeInterval = fast ? 0.14 : 0.32
        let p: OfficeCatPose = fast ? .run : .walk
        var actions: [SKAction] = []
        var prev = here
        for t in route {
            let from = prev
            let to = t
            let dest = room.point(to)
            let frames = (0..<p.frameCount).map { textures.texture(p, frame: $0, night: night) }
            let animate = SKAction.animate(with: frames, timePerFrame: stepTime / Double(p.frameCount), resize: false, restore: false)
            actions.append(.run { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.face(towards: dest.x)
                    self.root.zPosition = max(room.tileZ(from), room.tileZ(to))
                    self.pose = p
                    self.sprite.run(animate, withKey: "walk")
                }
            })
            actions.append(.move(to: dest, duration: stepTime))
            actions.append(.run { [weak self] in MainActor.assumeIsolated { self?.spot = .floor(to) } })
            prev = t
        }
        let final = route.last ?? here
        run(.sequence(actions), on: root, key: "move") { [weak self] in
            guard let self else { return }
            self.sprite.removeAction(forKey: "walk")
            self.spot = .floor(final)
            self.placeAtSpot()
            self.setPose(.stand)
        }
    }

    private static func arc(from a: CGPoint, to b: CGPoint, height: CGFloat, duration: TimeInterval) -> SKAction {
        SKAction.customAction(withDuration: duration) { node, t in
            let k = duration > 0 ? CGFloat(t) / CGFloat(duration) : 1
            node.position = CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k + 4 * height * k * (1 - k))
        }
    }

    private func jumpUp(perch id: Int, now: Date) {
        guard let room, let perch = room.catWorld.perch(id) else { advance(now: now); return }
        let pp = room.perchPoint(perch)
        let from = root.position
        face(towards: pp.point.x)
        let leap = textures.texture(.leapUp, frame: 0, night: night)
        setPose(.crouch)
        let seq = SKAction.sequence([
            .wait(forDuration: 0.22),
            .run { [weak self] in MainActor.assumeIsolated { self?.sprite.texture = leap; self?.root.zPosition = pp.z; self?.pose = .leapUp } },
            Self.arc(from: from, to: pp.point, height: 12, duration: 0.5),
        ])
        run(seq, on: root, key: "move") { [weak self] in
            guard let self else { return }
            self.spot = .perch(id)
            self.placeAtSpot()
            self.setPose(.sit)
        }
    }

    private func jumpDown(to tile: OfficeTile, now: Date) {
        guard let room else { advance(now: now); return }
        let dest = room.point(tile)
        let from = root.position
        face(towards: dest.x)
        let down = textures.texture(.leapDown, frame: 0, night: night)
        setPose(.leapDown)
        sprite.texture = down
        let seq = SKAction.sequence([.wait(forDuration: 0.12), Self.arc(from: from, to: dest, height: 8, duration: 0.42)])
        run(seq, on: root, key: "move") { [weak self] in
            guard let self else { return }
            self.spot = .floor(tile)
            self.placeAtSpot()
            self.setPose(.stand)
        }
    }

    /// Odalar arası geçiş: kapıya çık, solarak çık; hedef odanın kapısında belir, girişe yürü.
    private func travel(to id: String, now: Date) {
        guard let room, let target = roomLookup(id), target !== room else { advance(now: now); return }
        let door = room.point(room.kit.spots.door)
        face(towards: door.x)
        setPose(.walk)
        let out = SKAction.group([.move(to: door, duration: 0.32), .sequence([.wait(forDuration: 0.1), .fadeOut(withDuration: 0.22)])])
        run(.sequence([out]), on: root, key: "move") { [weak self] in
            guard let self else { return }
            self.arrive(in: target, from: room)
        }
    }

    private func arrive(in target: OfficeRoomNode, from old: OfficeRoomNode) {
        self.room = target
        roomID = target.id
        target.attachCat(root)
        let door = target.point(target.kit.spots.door)
        let entrance = target.kit.spots.entrance
        root.position = door
        root.zPosition = target.tileZ(entrance)
        root.alpha = 0
        facingLeft = true; sprite.xScale = -1
        setPose(.walk)
        spot = .floor(entrance)
        let dest = target.point(entrance)
        let walkIn = SKAction.group([.move(to: dest, duration: 0.32), .fadeIn(withDuration: 0.22)])
        run(walkIn, on: root, key: "move") { [weak self] in
            guard let self else { return }
            self.root.alpha = 1
            self.placeAtSpot()
            self.setPose(.stand)
        }
    }

    // MARK: Eylem çalıştırma (sonlu; biten adım sıradakini başlatır)

    private func run(_ action: SKAction, on node: SKNode, key: String, then end: @escaping () -> Void) {
        token += 1
        let mine = token
        busy = true
        let finish: () -> Void = { [weak self] in
            guard let self, self.token == mine else { return }
            self.completion = nil
            end()
            self.busy = false
            self.advance(now: self.clock())
            self.onChange?()
        }
        completion = finish
        node.run(.sequence([action, .run { MainActor.assumeIsolated { finish() } }]), withKey: key)
        onChange?()
    }

    private func cancel() {
        token += 1
        completion = nil
        root.removeAllActions()
        sprite.removeAllActions()
        reaction?.removeFromParent(); reaction = nil
        busy = false
        root.alpha = 1
        sprite.xScale = facingLeft ? -1 : 1
    }

    /// Testler (SKView'siz): çalışan eylemi anında bitirir ve sıradaki adıma geçer. Gerçek akışta eylemler `SKAction` ile biter.
    func fastForward() {
        guard let finish = completion else { return }
        root.removeAllActions(); sprite.removeAllActions()
        finish()
    }

    /// Önizleme/test: yürüme adımının ortasında dondurulmuş kare (eylem çalışırken durum görüntüsü). Gerçek akışta kullanılmaz.
    func fastForwardFirstStepForPreview() { setPose(.walk, frame: 1) }

    // MARK: Tıklama

    func hit(local p: CGPoint) -> Bool {
        guard room != nil, root.alpha > 0.5 else { return false }
        let r = CGRect(x: root.position.x - 12, y: root.position.y - 1, width: 24, height: 17)
        return r.contains(p)
    }

    /// Dokunma: durur, mutlu poz + kalp + "miyav" (misak `greet`). Havada (zıplarken) görmezden gelinir.
    @discardableResult
    func greet(now: Date, zoom: CGFloat) -> Bool {
        guard room != nil else { return false }
        if busy, pose == .leapUp || pose == .leapDown { return false }
        cancel()
        steps = []; plan = OfficeCatPlan(activity: .moleSit, steps: [], end: spot)
        setPose(.happy)
        holdUntil = now.addingTimeInterval(OfficeCatBrain.greetHold)
        showReaction(zoom: zoom)
        onChange?()
        return true
    }

    private func showReaction(zoom: CGFloat) {
        let node = SKNode()
        node.zPosition = 50
        let heart = SKSpriteNode(texture: textures.heart(), size: CGSize(width: 7, height: 7))
        heart.position = CGPoint(x: 3, y: 26)
        node.addChild(heart)
        let bg = SKSpriteNode(color: SKColor(white: 0.04, alpha: 0.9), size: CGSize(width: 34, height: 13))
        let label = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        label.fontSize = 9; label.fontColor = .white; label.text = "miyav"
        label.verticalAlignmentMode = .center; label.horizontalAlignmentMode = .center
        let tip = SKNode()
        tip.addChild(bg); tip.addChild(label)
        tip.setScale(1 / max(zoom, 0.25))
        tip.position = CGPoint(x: 0, y: 38)
        node.addChild(tip)
        root.addChild(node)
        reaction = node
        node.run(.sequence([.group([.moveBy(x: 0, y: 6, duration: 1.6), .sequence([.wait(forDuration: 1.0), .fadeOut(withDuration: 0.6)])]), .removeFromParent()])) { [weak self] in
            MainActor.assumeIsolated { self?.reaction = nil; self?.onChange?() }
        }
    }
}
