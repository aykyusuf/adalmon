import SpriteKit

/// Sahnedeki tek bir karakter (oturum ya da alt ajan). Yalnızca sahne tarafından değiştirilir.
@MainActor
final class OfficeActor {
    let root = SKNode()
    let body: SKSpriteNode
    var accessory: SKSpriteNode?
    var bubble: SKSpriteNode?
    let label = SKNode()
    var member: OfficeMember
    var appearance: OfficeAppearance
    var seat: OfficeSeat
    var tile: OfficeTile
    /// Yürüyüşte hedeflenen karo (yeniden planlama buradan).
    var heading: OfficeTile?
    var direction: OfficeCharacterSheet.Direction = .down
    var behavior: OfficeBehavior
    var moving = false
    var hopping = false
    var away = false
    var idleSince: Date?
    var leaving = false

    init(member: OfficeMember, appearance: OfficeAppearance, seat: OfficeSeat, texture: SKTexture) {
        self.member = member; self.appearance = appearance; self.seat = seat; self.tile = seat.tile
        behavior = OfficeBehavior.behavior(for: member.status, atDesk: seat.kind == .desk)
        body = SKSpriteNode(texture: texture)
        body.anchorPoint = CGPoint(x: 0.5, y: 0)
        body.size = CGSize(width: 16, height: 32)
        body.color = SKColor(red: appearance.tint.r, green: appearance.tint.g, blue: appearance.tint.b, alpha: 1)
        body.colorBlendFactor = appearance.tintBlend
        root.addChild(body)
    }

    var isAnimating: Bool {
        moving || hopping || leaving || (!away && (behavior.pose == .typing || behavior.bubble == .alert || behavior.pcOn))
    }
}

/// Ofis sahnesi: ince bir uygulayıcı. Atama/davranış/yol bulma `OfficePlanner`/`OfficeGrid` içindedir. SwiftUI'ya bağımlı değildir
/// (duvar kâğıdı penceresinde de kullanılabilir). Boşta hiçbir `SKAction` çalışmaz; `onAnimationStateChange` ile ev sahibi
/// görünümü duraklatabilir.
@MainActor
final class OfficeScene: SKScene {
    static let stepDuration: TimeInterval = 0.25
    static let sitDrop: CGFloat = 3

    let assets: OfficeAssets
    private let world = SKNode()
    private let cameraNode = SKCameraNode()
    private var assigner: OfficeAssigner
    private var actors: [String: OfficeActor] = [:]
    private var leavingActors: [OfficeActor] = []
    private var pcNodes: [Int: SKSpriteNode] = [:]
    private var pcOccupied: [Int: String] = [:]
    private let overflowLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private(set) var zoom = 1
    private var lastAnimating = false
    private var lastWander: Date?

    /// true/false: sahnede çalışan animasyon var mı (ev sahibi bunu duraklatma kararında kullanır).
    var onAnimationStateChange: ((Bool) -> Void)?

    var isAnimating: Bool { actors.values.contains { $0.isAnimating } || !leavingActors.isEmpty }
    var actorCount: Int { actors.count }
    var memberIDs: Set<String> { Set(actors.keys) }

    init(assets: OfficeAssets, size: CGSize = CGSize(width: 960, height: 600)) {
        self.assets = assets
        assigner = OfficeAssigner(seats: assets.spots.seats)
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = SKColor(red: 0.075, green: 0.075, blue: 0.095, alpha: 1)
        buildWorld()
        addChild(world)
        addChild(cameraNode)
        camera = cameraNode
        relayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) yok") }

    override func didChangeSize(_ oldSize: CGSize) { relayout() }

    // MARK: Düzen

    private func relayout() {
        let w = Double(assets.worldWidth), h = Double(assets.worldHeight)
        let z = OfficeAppearance.integerZoom(viewWidth: size.width, viewHeight: size.height, contentWidth: w + 4, contentHeight: h + 4)
        cameraNode.position = CGPoint(x: w / 2, y: h / 2)
        cameraNode.setScale(1 / CGFloat(z))
        guard z != zoom || actors.isEmpty else { return }
        zoom = z
        for a in actors.values { applyScale(a) }
        layoutOverflowLabel()
    }

    private func applyScale(_ a: OfficeActor) {
        let s = CGFloat(OfficeAppearance.spriteScale(small: a.appearance.small, zoom: zoom))
        a.body.setScale(s)
        a.label.setScale(1 / CGFloat(zoom))
        a.accessory?.setScale(s)
        positionAccessoryAndBubble(a)
    }

    // MARK: Koordinatlar

    /// Karonun alt-orta noktası (dünya koordinatı, y yukarı).
    func point(_ t: OfficeTile) -> CGPoint {
        let b = assets.bounds
        return CGPoint(x: CGFloat((t.col - b.minCol) * 16 + 8), y: CGFloat(assets.worldHeight - (t.row - b.minRow + 1) * 16) + 1)
    }

    private func yDown(_ t: OfficeTile) -> CGFloat { CGFloat((t.row + 1) * 16) }

    // MARK: Dünya (zemin, mobilya, kapı)

    private func buildWorld() {
        let bg = SKSpriteNode(texture: assets.background)
        bg.anchorPoint = .zero
        bg.zPosition = 0
        world.addChild(bg)

        let b = assets.bounds
        for (i, f) in assets.layout.furniture.enumerated() {
            guard let a = assets.catalog[f.assetID], let tex = assets.furnitureTexture(a.id) else { continue }
            let node = SKSpriteNode(texture: tex)
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.size = CGSize(width: a.width, height: a.height)
            node.xScale = f.mirrored ? -1 : 1
            node.position = CGPoint(x: CGFloat((f.col - b.minCol) * 16 + a.width / 2), y: CGFloat(assets.worldHeight - ((f.row - b.minRow) * 16 + a.height)))
            // Öne-arkaya sıralama: ayak izi alt kenarı; yüzeydekiler (PC) ev sahibinin biraz üstünde.
            node.zPosition = CGFloat((f.row + a.footprintH) * 16) + (a.onSurface ? 0.2 : 0) + (a.onWall ? -50 : 0)
            world.addChild(node)
            if a.id.hasSuffix("_OFF") { pcNodes[i] = node }
        }

        if let door = assets.doorTexture() {
            let node = SKSpriteNode(texture: door)
            node.anchorPoint = .zero
            node.size = CGSize(width: 16, height: 32)
            let d = assets.spots.door
            node.position = CGPoint(x: CGFloat((d.col - b.minCol) * 16), y: CGFloat(assets.worldHeight - (d.row - b.minRow + 1) * 16))
            node.zPosition = yDown(d) - 8
            world.addChild(node)
        }

        overflowLabel.fontSize = 10
        overflowLabel.fontColor = SKColor(white: 1, alpha: 0.9)
        overflowLabel.horizontalAlignmentMode = .right
        overflowLabel.verticalAlignmentMode = .top
        overflowLabel.zPosition = 20_000
        overflowLabel.isHidden = true
        world.addChild(overflowLabel)
        layoutOverflowLabel()
    }

    private func layoutOverflowLabel() {
        overflowLabel.setScale(1 / CGFloat(zoom))
        overflowLabel.position = CGPoint(x: CGFloat(assets.worldWidth) - 2, y: CGFloat(assets.worldHeight) - 2)
    }

    // MARK: Uygulama

    /// Üyeleri sahneye uygular. `animated == false`: herkes doğrudan son konumunda belirir (önizleme, ilk statik kare).
    func apply(members: [OfficeMember], animated: Bool, now: Date = .now) {
        let plan = assigner.update(members: members)
        for id in plan.departed { depart(id, animated: animated) }
        for m in members {
            guard case .seat(let seatID)? = plan.placements[m.id], let seat = assets.spots.seats.first(where: { $0.id == seatID }) else { continue }
            if let actor = actors[m.id] { update(actor, member: m, now: now, animated: animated) } else { spawn(m, seat: seat, animated: animated, now: now) }
        }
        let overflow = plan.overflowCount
        overflowLabel.isHidden = overflow == 0
        if overflow > 0 { overflowLabel.text = "+\(overflow)" }
        notifyAnimationState()
    }

    private func spawn(_ m: OfficeMember, seat: OfficeSeat, animated: Bool, now: Date) {
        let look = OfficeAppearance.appearance(for: m.badge)
        let actor = OfficeActor(member: m, appearance: look, seat: seat,
                                texture: assets.characterTexture(index: look.characterIndex, direction: seat.facing, frame: 1))
        actor.idleSince = now
        buildDecor(actor)
        actors[m.id] = actor
        world.addChild(actor.root)
        applyScale(actor)
        if let pc = seat.pcIndex { pcOccupied[pc] = m.id }
        if animated, let route = assets.grid.path(from: assets.spots.entrance, to: seat.tile) {
            actor.tile = assets.spots.entrance
            actor.root.position = point(assets.spots.door)
            actor.root.alpha = 0
            actor.root.zPosition = yDown(assets.spots.door) + 0.5
            actor.root.run(.fadeIn(withDuration: 0.3))
            actor.moving = true
            run(route: [assets.spots.entrance] + route, for: actor) { [weak self] in self?.arrive(actor) }
        } else {
            place(actor, at: seat.tile)
            arrive(actor)
        }
    }

    private func place(_ actor: OfficeActor, at t: OfficeTile) {
        actor.tile = t
        actor.root.position = point(t)
        actor.root.zPosition = yDown(t) + 0.5
    }

    private func update(_ actor: OfficeActor, member m: OfficeMember, now: Date, animated: Bool) {
        let old = actor.member.status
        actor.member = m
        let behavior = OfficeBehavior.behavior(for: m.status, atDesk: actor.seat.kind == .desk)
        if m.status.isWorking { actor.idleSince = nil } else if actor.idleSince == nil || old.isWorking { actor.idleSince = now }
        guard behavior != actor.behavior || old != m.status else { return }
        let celebrate = OfficeBehavior.celebrates(from: old, to: m.status)
        actor.behavior = behavior
        if actor.away && m.status.isWorking { sendBack(actor, animated: animated) }
        if !actor.moving && !actor.away {
            applyPose(actor)
            if celebrate && animated { hop(actor) }
        }
    }

    // MARK: Poz

    /// Oturma/ayakta pozunu ve ek öğeleri (balon, PC ekranı) mevcut davranışa göre kurar.
    private func applyPose(_ a: OfficeActor) {
        a.body.removeAction(forKey: "pose")
        let frames: [Int]
        switch a.behavior.pose {
        case .typing: frames = [OfficeCharacterSheet.frameIndex(.typing(0)), OfficeCharacterSheet.frameIndex(.typing(1))]
        case .reading: frames = [OfficeCharacterSheet.frameIndex(.reading(0)), OfficeCharacterSheet.frameIndex(.reading(1))]
        case .sitting: frames = [OfficeCharacterSheet.frameIndex(.stand)]
        }
        let tex = frames.map { assets.characterTexture(index: a.appearance.characterIndex, direction: a.direction, frame: $0) }
        a.body.xScale = (OfficeCharacterSheet.mirrorsHorizontally(a.direction) ? -1 : 1) * abs(a.body.xScale)
        a.body.texture = tex[0]
        a.body.position.y = -Self.sitDrop
        if a.behavior.pose != .sitting {
            // Okuma (izin bekleme) yavaş, yazma hızlı.
            let t = a.behavior.pose == .typing ? 0.28 : 0.6
            a.body.run(.repeatForever(.animate(with: tex, timePerFrame: t, resize: false, restore: false)), withKey: "pose")
        }
        setBubble(a)
        setPC(a)
        positionAccessoryAndBubble(a)
        notifyAnimationState()
    }

    private func setBubble(_ a: OfficeActor) {
        a.bubble?.removeFromParent()
        a.bubble = nil
        guard let kind = a.behavior.bubble, let tex = assets.bubbleTexture(kind) else { return }
        let node = SKSpriteNode(texture: tex)
        node.anchorPoint = CGPoint(x: 0, y: 0)
        node.zPosition = 5_000
        a.root.addChild(node)
        a.bubble = node
        if kind == .alert {
            node.run(.repeatForever(.sequence([.moveBy(x: 0, y: 2, duration: 0.3), .moveBy(x: 0, y: -2, duration: 0.3)])), withKey: "bob")
        }
    }

    private func setPC(_ a: OfficeActor) {
        guard let pc = a.seat.pcIndex, let node = pcNodes[pc], pcOccupied[pc] == a.member.id else { return }
        node.removeAction(forKey: "screen")
        let off = assets.layout.furniture[pc].assetID
        if a.behavior.pcOn, let on = OfficeBehavior.pcOnFrames(forOffAsset: off) {
            let tex = on.compactMap { assets.furnitureTexture($0) }
            if !tex.isEmpty { node.run(.repeatForever(.animate(with: tex, timePerFrame: 0.45, resize: false, restore: false)), withKey: "screen") }
        } else {
            node.texture = assets.furnitureTexture(off)
        }
    }

    /// Aksesuar baş üstünde, balon sağ üstte; oturma pozunda baş birkaç piksel aşağıdadır.
    private func positionAccessoryAndBubble(_ a: OfficeActor) {
        let s = a.body.yScale
        let seated = !a.moving && !a.hopping && !a.away
        let headTop: CGFloat = (seated ? 28 : 30) * s + a.body.position.y
        if let acc = a.accessory {
            acc.position = CGPoint(x: 0, y: headTop - 1)
            acc.xScale = s; acc.yScale = s
        }
        a.bubble?.position = CGPoint(x: 7 * s, y: headTop - 8 * s)
        let top = headTop + (a.accessory?.size.height ?? 0) * s + 3
        a.label.position = CGPoint(x: 0, y: top + (a.bubble != nil ? 0 : 0))
    }

    private func buildDecor(_ a: OfficeActor) {
        if let tex = assets.accessoryTexture(a.appearance.accessory) {
            let node = SKSpriteNode(texture: tex)
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.size = tex.size()
            node.zPosition = 10
            a.root.addChild(node)
            a.accessory = node
        }
        a.label.zPosition = 6_000
        a.root.addChild(a.label)
        let name = SKLabelNode(fontNamed: "HelveticaNeue-Medium")
        name.fontSize = 10
        name.text = Self.truncated(a.member.label, 16)
        name.fontColor = .white
        name.verticalAlignmentMode = .center
        name.horizontalAlignmentMode = .left
        let badge = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        badge.fontSize = 8
        badge.text = a.appearance.badgeText
        badge.fontColor = SKColor(red: a.appearance.tint.r, green: a.appearance.tint.g, blue: a.appearance.tint.b, alpha: 1)
        badge.verticalAlignmentMode = .center
        badge.horizontalAlignmentMode = .left
        // Tek satır: "ad  MODEL" (dikey taşmayı azaltır; komşu karakterlerin üstüne binmez).
        let nameW = name.frame.width, gap: CGFloat = 5
        let width = nameW + gap + badge.frame.width + 8
        let pill = SKSpriteNode(color: SKColor(white: 0.04, alpha: 0.8), size: CGSize(width: width, height: 14))
        pill.anchorPoint = CGPoint(x: 0.5, y: 0)
        pill.position = CGPoint(x: 0, y: 2)
        let g = OfficeAppearance.groupColors[a.member.groupIndex % OfficeAppearance.groupColors.count]
        let stripe = SKSpriteNode(color: SKColor(red: g.r, green: g.g, blue: g.b, alpha: 1), size: CGSize(width: width, height: 2))
        stripe.anchorPoint = CGPoint(x: 0.5, y: 0)
        stripe.position = .zero
        name.position = CGPoint(x: -width / 2 + 4, y: 2 + 7)
        badge.position = CGPoint(x: -width / 2 + 4 + nameW + gap, y: 2 + 7)
        for n in [pill, stripe, name, badge] { a.label.addChild(n) }
    }

    static func truncated(_ s: String, _ n: Int) -> String { s.count <= n ? s : String(s.prefix(n - 1)) + "…" }

    // MARK: Yürüyüş

    private func direction(from a: OfficeTile, to b: OfficeTile) -> OfficeCharacterSheet.Direction {
        if b.col > a.col { return .right }
        if b.col < a.col { return .left }
        return b.row < a.row ? .up : .down
    }

    /// `route[0]` karakterin bulunduğu karo; sonrakiler adım adım. Her adım: yön/dokular, z, kayma.
    private func run(route: [OfficeTile], for a: OfficeActor, completion: @escaping @MainActor () -> Void) {
        a.root.removeAction(forKey: "move")
        a.body.removeAction(forKey: "pose")
        a.bubble?.removeFromParent(); a.bubble = nil
        a.body.position.y = 0
        var actions: [SKAction] = []
        for (from, to) in zip(route, route.dropFirst()) {
            let dir = direction(from: from, to: to)
            let walk = (0..<4).map { assets.characterTexture(index: a.appearance.characterIndex, direction: dir, frame: OfficeCharacterSheet.frameIndex(.walk($0))) }
            let z = max(yDown(from), yDown(to)) + 0.5
            actions.append(.run { [weak a] in
                guard let a else { return }
                a.direction = dir
                a.heading = to
                a.body.xScale = (OfficeCharacterSheet.mirrorsHorizontally(dir) ? -1 : 1) * abs(a.body.xScale)
                a.body.removeAction(forKey: "pose")
                a.body.run(.repeatForever(.animate(with: walk, timePerFrame: Self.stepDuration / 4, resize: false, restore: false)), withKey: "pose")
                a.root.zPosition = z
            })
            let move = SKAction.move(to: point(to), duration: Self.stepDuration)
            actions.append(move)
            actions.append(.run { [weak a] in a?.tile = to })
        }
        actions.append(.run { [weak a] in
            guard let a else { return }
            a.body.removeAction(forKey: "pose")
            a.heading = nil
            a.moving = false
        })
        actions.append(.run(completion))
        a.moving = true
        a.root.run(.sequence(actions), withKey: "move")
    }

    private func arrive(_ a: OfficeActor) {
        guard !a.leaving, actors[a.member.id] === a else { return }
        a.moving = false
        a.direction = a.seat.facing
        a.tile = a.seat.tile
        a.root.zPosition = yDown(a.seat.tile) + 0.5
        a.behavior = OfficeBehavior.behavior(for: a.member.status, atDesk: a.seat.kind == .desk)
        a.away = false
        applyPose(a)
        notifyAnimationState()
    }

    private func depart(_ id: String, animated: Bool) {
        guard let a = actors.removeValue(forKey: id) else { return }
        if let pc = a.seat.pcIndex, pcOccupied[pc] == id {
            pcOccupied[pc] = nil
            pcNodes[pc]?.removeAction(forKey: "screen")
            pcNodes[pc]?.texture = assets.furnitureTexture(assets.layout.furniture[pc].assetID)
        }
        a.leaving = true
        a.away = true
        a.bubble?.removeFromParent(); a.bubble = nil
        let from = a.heading ?? a.tile
        guard animated, let route = assets.grid.path(from: from, to: assets.spots.entrance) else { a.root.removeFromParent(); return }
        leavingActors.append(a)
        var steps = [from] + route
        steps.append(assets.spots.door)
        a.root.removeAction(forKey: "move")
        place(a, at: from)
        a.body.position.y = 0
        run(route: steps, for: a) { [weak self] in
            a.root.run(.fadeOut(withDuration: 0.2)) {
                MainActor.assumeIsolated {
                    a.root.removeFromParent()
                    self?.leavingActors.removeAll { $0 === a }
                    self?.notifyAnimationState()
                }
            }
        }
        // Kapıda solma: son adımın başında başlat (kapı karosuna girerken).
        a.root.run(.sequence([.wait(forDuration: Self.stepDuration * Double(steps.count - 2)), .fadeAlpha(to: 0.0, duration: Self.stepDuration)]), withKey: "fade")
    }

    private func hop(_ a: OfficeActor) {
        a.hopping = true
        let up = SKAction.moveBy(x: 0, y: 5, duration: 0.1), down = SKAction.moveBy(x: 0, y: -5, duration: 0.1)
        a.body.run(.sequence([up, down, up, down, .run { [weak a, weak self] in a?.hopping = false; self?.notifyAnimationState() }]), withKey: "hop")
    }

    // MARK: Kahve

    /// Boşta oturan karakteri kahve makinesine yollar; kısa bekledikten sonra masasına döner. Zamanlayıcı ev sahibindedir.
    @discardableResult
    func wanderTick(now: Date = .now, roll: Double = .random(in: 0..<1)) -> Bool {
        guard let coffee = assets.spots.coffee else { return false }
        let candidates = actors.values.filter { !$0.moving && !$0.away && !$0.leaving && $0.behavior.mayWander }
            .compactMap { a in a.idleSince.map { OfficeWander.Candidate(id: a.member.id, idleSince: $0) } }
        let walking = actors.values.contains { $0.away || $0.moving }
        guard let id = OfficeWander.pick(candidates, now: now, lastWander: lastWander, someoneWalking: walking, roll: roll),
              let a = actors[id], let there = assets.grid.path(from: a.tile, to: coffee) else { return false }
        lastWander = now
        a.away = true
        a.root.zPosition = yDown(a.tile) + 0.5
        run(route: [a.tile] + there, for: a) { [weak self, weak a] in
            guard let self, let a, a.away else { return }
            a.direction = self.assets.spots.coffeeFacing
            a.body.texture = self.assets.characterTexture(index: a.appearance.characterIndex, direction: a.direction, frame: 1)
            a.body.xScale = (OfficeCharacterSheet.mirrorsHorizontally(a.direction) ? -1 : 1) * abs(a.body.xScale)
            a.root.run(.sequence([.wait(forDuration: 6), .run { [weak self, weak a] in
                guard let self, let a, a.away else { return }
                self.sendBack(a, animated: true)
            }]), withKey: "coffee")
            self.notifyAnimationState()
        }
        notifyAnimationState()
        return true
    }

    private func sendBack(_ a: OfficeActor, animated: Bool) {
        a.root.removeAction(forKey: "coffee")
        let from = a.heading ?? a.tile
        guard animated, let route = assets.grid.path(from: from, to: a.seat.tile) else {
            a.root.removeAllActions(); a.moving = false; place(a, at: a.seat.tile); arrive(a); return
        }
        place(a, at: from)
        run(route: [from] + route, for: a) { [weak self] in self?.arrive(a) }
    }

    // MARK: Animasyon durumu

    private func notifyAnimationState() {
        let now = isAnimating
        guard now != lastAnimating else { return }
        lastAnimating = now
        onAnimationStateChange?(now)
    }
}
