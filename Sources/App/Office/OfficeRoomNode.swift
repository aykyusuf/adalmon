import SpriteKit

/// Sahnedeki tek bir karakter (oturum ya da alt ajan). Yalnızca kendi odası tarafından değiştirilir.
@MainActor
final class OfficeActor {
    let root = SKNode()
    let body: SKSpriteNode
    var accessory: SKSpriteNode?
    var bubble: SKSpriteNode?
    /// Ad etiketi: yalnızca yakından bakılırken (ilk gerektiğinde) kurulur; düğüm sayısını düşük tutar.
    let label = SKNode()
    var labelBuilt = false
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
    /// Dinlenmeye gittiği boş salon koltuğu (kahve makinesi olmayan odalarda).
    var awaySeatID: Int?
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

/// Bir oturumun odası: kademe şablonundan kurulur (tek pişirilmiş arka plan + az sayıda dinamik mobilya), kendi karakterlerini,
/// yürüyüşlerini (BFS yalnızca bu odanın ızgarasında), kapısını, başlık levhasını ve "+N" rozetini yönetir. Planlama
/// (`OfficeRoomPlanner`) dışarıdadır. `root` yer değiştirme/solma içindir; `content` görünür değilken duraklatılır
/// (içerideki SKAction'lar çalışmaz).
@MainActor
final class OfficeRoomNode {
    static let stepDuration: TimeInterval = 0.25
    static let sitDrop: CGFloat = 3
    /// Odanın üstündeki levha bandı (dünya birimi).
    static let headerHeight: CGFloat = 26
    static let placeholderTitle = "Ajan yok"

    let id: String
    let tier: OfficeRoomTier
    let assets: OfficeAssets
    let kit: OfficeRoomKit
    let root = SKNode()
    private let content = SKNode()

    private(set) var actors: [String: OfficeActor] = [:]
    private var leavingActors: [OfficeActor] = []
    private var pcNodes: [Int: SKSpriteNode] = [:]
    private var pcOccupied: [Int: String] = [:]
    private var assignedSeats: Set<Int> = []
    private var awayLounge: Set<Int> = []
    private(set) var zoom = 1
    private(set) var labelsOn = false
    private(set) var overflow = 0
    private(set) var memberCount = 0
    var placed = false
    var onAnimationChange: (() -> Void)?

    // Levha (ekran sabit boyutlu: ölçek 1/zoom).
    private let plaque = SKNode()
    private let plaquePill = SKSpriteNode(color: SKColor(white: 0.04, alpha: 0.88), size: .zero)
    private let plaqueStripe = SKSpriteNode(color: .gray, size: .zero)
    private let plaqueName = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
    private let plaqueBadgeBG = SKSpriteNode(color: .gray, size: .zero)
    private let plaqueBadge = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
    private var overflowNode: SKNode?
    private var overflowWidth: CGFloat = 0
    private var title: String?
    private var badge: AgentModelBadge?
    private var group = 0

    var isVisible = true {
        didSet { if isVisible != oldValue { content.isPaused = !isVisible } }
    }

    init(id: String, tier: OfficeRoomTier, assets: OfficeAssets) {
        self.id = id; self.tier = tier; self.assets = assets
        kit = assets.kit(tier)
        root.addChild(content)
        buildWorld()
        buildChrome()
    }

    var frameSize: CGSize { CGSize(width: kit.worldWidth, height: kit.worldHeight + Int(Self.headerHeight)) }
    var isPlaceholder: Bool { id == OfficeRoomPlanner.emptyRoomID }
    /// Bu odada çalışan animasyon var mı (görünür olup olmadığına bakmaz).
    var isAnimating: Bool { actors.values.contains { $0.isAnimating } || !leavingActors.isEmpty }
    var isWalking: Bool { actors.values.contains { $0.away || $0.moving } }
    var actorCount: Int { actors.count }

    // MARK: Koordinatlar

    /// Karonun alt-orta noktası (odanın yerel koordinatı, y yukarı).
    func point(_ t: OfficeTile) -> CGPoint {
        let b = kit.bounds
        return CGPoint(x: CGFloat((t.col - b.minCol) * 16 + 8), y: CGFloat(kit.worldHeight - (t.row - b.minRow + 1) * 16) + 1)
    }

    private func yDown(_ t: OfficeTile) -> CGFloat { CGFloat((t.row + 1) * 16) }

    // MARK: Kurulum

    private func buildWorld() {
        let bg = SKSpriteNode(texture: kit.background)
        bg.anchorPoint = .zero
        bg.zPosition = 0
        content.addChild(bg)

        let b = kit.bounds
        for (i, f, a) in kit.dynamicFurniture {
            guard let tex = assets.furnitureTexture(a.id) else { continue }
            let node = SKSpriteNode(texture: tex)
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.size = CGSize(width: a.width, height: a.height)
            node.xScale = f.mirrored ? -1 : 1
            node.position = CGPoint(x: CGFloat((f.col - b.minCol) * 16 + a.width / 2), y: CGFloat(kit.worldHeight - ((f.row - b.minRow) * 16 + a.height)))
            // Öne-arkaya sıralama: ayak izi alt kenarı; yüzeydekiler (PC) sahibinin biraz üstünde.
            node.zPosition = CGFloat((f.row + a.footprintH) * 16) + (a.onSurface ? 0.2 : 0)
            content.addChild(node)
            if a.id.hasSuffix("_OFF") { pcNodes[i] = node }
        }

        if let door = assets.doorTexture() {
            let node = SKSpriteNode(texture: door)
            node.anchorPoint = .zero
            node.size = CGSize(width: 16, height: 32)
            let d = kit.spots.door
            node.position = CGPoint(x: CGFloat((d.col - b.minCol) * 16), y: CGFloat(kit.worldHeight - (d.row - b.minRow + 1) * 16))
            node.zPosition = yDown(d) - 8
            content.addChild(node)
        }
    }

    private func buildChrome() {
        plaque.zPosition = 30_000
        plaquePill.anchorPoint = .zero
        plaqueStripe.anchorPoint = .zero
        plaqueBadgeBG.anchorPoint = .zero
        plaquePill.zPosition = 0; plaqueStripe.zPosition = 1; plaqueBadgeBG.zPosition = 2; plaqueName.zPosition = 3; plaqueBadge.zPosition = 4
        plaqueName.fontSize = 12
        plaqueName.fontColor = .white
        plaqueName.verticalAlignmentMode = .center
        plaqueName.horizontalAlignmentMode = .left
        plaqueBadge.fontSize = 9
        plaqueBadge.verticalAlignmentMode = .center
        plaqueBadge.horizontalAlignmentMode = .center
        for n in [plaquePill, plaqueStripe, plaqueBadgeBG, plaqueName, plaqueBadge] as [SKNode] { plaque.addChild(n) }
        content.addChild(plaque)
        setTitle(title: nil, badge: nil, group: 0)
    }

    // MARK: Levha + rozet

    func setTitle(title: String?, badge: AgentModelBadge?, group: Int) {
        self.title = title; self.badge = badge; self.group = group
        layoutChrome()
    }

    func setZoom(_ z: Int) {
        zoom = z
        for a in actors.values { applyScale(a) }
        for a in leavingActors { applyScale(a) }
        layoutChrome()
    }

    private func fit(_ s: String, in label: SKLabelNode, maxWidth: CGFloat) -> String {
        label.text = s
        if label.frame.width <= maxWidth { return s }
        var chars = Array(s)
        while chars.count > 1 {
            chars.removeLast()
            let t = String(chars) + "…"
            label.text = t
            if label.frame.width <= maxWidth { return t }
        }
        return "…"
    }

    private func layoutChrome() {
        let z = CGFloat(zoom)
        plaque.setScale(1 / z)
        plaque.position = CGPoint(x: 2, y: CGFloat(kit.worldHeight) + 3)
        let height: CGFloat = 20
        let placeholder = title == nil
        let look = badge.map { OfficeAppearance.appearance(for: $0) }
        let g = OfficeAppearance.groupColors[group % OfficeAppearance.groupColors.count]
        let maxW = CGFloat(kit.worldWidth) * z - 6 - (overflowNode == nil ? 0 : overflowWidth + 6)

        plaqueBadge.text = look?.badgeText ?? ""
        let badgeW: CGFloat = look == nil ? 0 : plaqueBadge.frame.width + 10
        let badgeSpace: CGFloat = look == nil ? 0 : badgeW + 6
        let textMax = max(24, maxW - 14 - badgeSpace)
        let shown = fit(title ?? Self.placeholderTitle, in: plaqueName, maxWidth: textMax)
        plaqueName.text = shown
        let nameW = plaqueName.frame.width
        let width = 7 + nameW + 7 + badgeSpace
        plaquePill.size = CGSize(width: width, height: height)
        plaquePill.alpha = placeholder ? 0.6 : 1
        plaqueName.fontColor = placeholder ? SKColor(white: 0.75, alpha: 1) : .white
        plaqueName.position = CGPoint(x: 7, y: height / 2 + 1)
        let stripe = placeholder ? OfficeRGB(r: 0.5, g: 0.5, b: 0.55) : g
        plaqueStripe.color = SKColor(red: stripe.r, green: stripe.g, blue: stripe.b, alpha: 1)
        plaqueStripe.size = CGSize(width: width, height: 3)
        if let look {
            let tint = SKColor(red: look.tint.r, green: look.tint.g, blue: look.tint.b, alpha: 1)
            plaqueBadgeBG.isHidden = false; plaqueBadge.isHidden = false
            plaqueBadgeBG.color = tint.withAlphaComponent(0.28)
            plaqueBadgeBG.size = CGSize(width: badgeW, height: 14)
            plaqueBadgeBG.position = CGPoint(x: 7 + nameW + 6, y: 5)
            plaqueBadge.fontColor = SKColor(red: min(1, look.tint.r + 0.25), green: min(1, look.tint.g + 0.25), blue: min(1, look.tint.b + 0.25), alpha: 1)
            plaqueBadge.position = CGPoint(x: 7 + nameW + 6 + badgeW / 2, y: 12)
        } else {
            plaqueBadgeBG.isHidden = true; plaqueBadge.isHidden = true
        }
        if let o = overflowNode {
            o.setScale(1 / z)
            o.position = CGPoint(x: CGFloat(kit.worldWidth) - 2, y: CGFloat(kit.worldHeight) + 3)
        }
    }

    func setOverflow(_ n: Int) {
        guard n != overflow || (n > 0 && overflowNode == nil) else { return }
        overflow = n
        overflowNode?.removeFromParent()
        overflowNode = nil
        if n > 0 {
            let node = SKNode()
            node.zPosition = 30_001
            let text = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
            text.fontSize = 12
            text.text = "+\(n)"
            text.fontColor = .white
            text.verticalAlignmentMode = .center
            text.horizontalAlignmentMode = .right
            let w = text.frame.width + 14
            let pill = SKSpriteNode(color: SKColor(red: 0.86, green: 0.24, blue: 0.2, alpha: 0.95), size: CGSize(width: w, height: 20))
            pill.anchorPoint = CGPoint(x: 1, y: 0)
            pill.zPosition = 0
            text.position = CGPoint(x: -7, y: 11)
            text.zPosition = 1
            node.addChild(pill); node.addChild(text)
            content.addChild(node)
            overflowNode = node
            overflowWidth = w
        }
        layoutChrome()
    }

    // MARK: Etiketler

    func setLabels(_ on: Bool) {
        guard on != labelsOn else { return }
        labelsOn = on
        for a in actors.values { refreshLabel(a) }
    }

    private func refreshLabel(_ a: OfficeActor) {
        if labelsOn { ensureLabel(a) }
        if a.labelBuilt { a.label.isHidden = !labelsOn || a.leaving }
    }

    private func ensureLabel(_ a: OfficeActor) {
        guard !a.labelBuilt else { return }
        a.labelBuilt = true
        a.label.zPosition = 6_000
        a.root.addChild(a.label)
        let name = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        name.fontSize = 9
        name.text = Self.truncated(a.member.label, 11)
        let t = a.appearance.tint
        name.fontColor = SKColor(red: min(1, t.r + 0.35), green: min(1, t.g + 0.35), blue: min(1, t.b + 0.35), alpha: 1)
        name.verticalAlignmentMode = .center
        name.horizontalAlignmentMode = .center
        let width = name.frame.width + 8
        let pill = SKSpriteNode(color: SKColor(white: 0.04, alpha: 0.85), size: CGSize(width: width, height: 13))
        pill.anchorPoint = CGPoint(x: 0.5, y: 0)
        pill.position = CGPoint(x: 0, y: 2)
        let g = OfficeAppearance.groupColors[a.member.groupIndex % OfficeAppearance.groupColors.count]
        let stripe = SKSpriteNode(color: SKColor(red: g.r, green: g.g, blue: g.b, alpha: 1), size: CGSize(width: width, height: 2))
        stripe.anchorPoint = CGPoint(x: 0.5, y: 0)
        stripe.position = .zero
        name.position = CGPoint(x: 0, y: 2 + 7)
        for n in [pill, stripe, name] as [SKNode] { a.label.addChild(n) }
        a.label.setScale(1 / CGFloat(zoom))
        positionAccessoryAndBubble(a)
    }

    static func truncated(_ s: String, _ n: Int) -> String { s.count <= n ? s : String(s.prefix(n - 1)) + "…" }

    // MARK: Uygulama

    /// Plan çıktısını odaya uygular. `animated == false`: herkes doğrudan son konumunda belirir.
    func apply(plan: OfficeRoomPlan, members: [OfficeMember], animated: Bool, now: Date) {
        memberCount = plan.memberCount
        setTitle(title: plan.title, badge: plan.badge, group: plan.groupIndex)
        for id in plan.departed { depart(id, animated: animated) }
        assignedSeats = Set(plan.placements.values.compactMap { if case .seat(let s) = $0 { s } else { nil } })
        for m in members {
            guard case .seat(let seatID)? = plan.placements[m.id], let seat = kit.spots.seats.first(where: { $0.id == seatID }) else { continue }
            if let actor = actors[m.id] { update(actor, member: m, now: now, animated: animated) } else { spawn(m, seat: seat, animated: animated, now: now) }
        }
        setOverflow(plan.overflowCount)
        notify()
    }

    private func spawn(_ m: OfficeMember, seat: OfficeSeat, animated: Bool, now: Date) {
        let look = OfficeAppearance.appearance(for: m.badge)
        let actor = OfficeActor(member: m, appearance: look, seat: seat,
                                texture: assets.characterTexture(index: look.characterIndex, direction: seat.facing, frame: 1))
        actor.idleSince = now
        actors[m.id] = actor
        content.addChild(actor.root)
        buildAccessory(actor)
        applyScale(actor)
        refreshLabel(actor)
        if let pc = seat.pcIndex { pcOccupied[pc] = m.id }
        let spots = kit.spots
        if animated, let route = kit.grid.path(from: spots.entrance, to: seat.tile) {
            actor.tile = spots.entrance
            actor.root.position = point(spots.door)
            actor.root.alpha = 0
            actor.root.zPosition = yDown(spots.door) + 0.5
            actor.root.run(.fadeIn(withDuration: 0.3))
            actor.moving = true
            run(route: [spots.entrance] + route, for: actor) { [weak self] in self?.arrive(actor) }
        } else {
            place(actor, at: seat.tile)
            arrive(actor)
        }
    }

    private func applyScale(_ a: OfficeActor) {
        let s = CGFloat(OfficeAppearance.spriteScale(small: a.appearance.small, zoom: zoom))
        a.body.setScale(s)
        a.label.setScale(1 / CGFloat(zoom))
        a.accessory?.setScale(s)
        positionAccessoryAndBubble(a)
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
        notify()
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
        let off = kit.layout.furniture[pc].assetID
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
        // Yan yana oturan salon koltuklarında (kanepe) etiketler çakışmasın: tek sütundakini bir kademe yukarı al.
        let stagger: CGFloat = a.seat.kind == .lounge && a.seat.tile.col % 2 != 0 ? 14 / CGFloat(zoom) : 0
        a.label.position = CGPoint(x: 0, y: top + stagger)
    }

    private func buildAccessory(_ a: OfficeActor) {
        guard a.accessory == nil, let tex = assets.accessoryTexture(a.appearance.accessory) else { return }
        let node = SKSpriteNode(texture: tex)
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.size = tex.size()
        node.zPosition = 10
        a.root.addChild(node)
        a.accessory = node
    }

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
            actions.append(SKAction.move(to: point(to), duration: Self.stepDuration))
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
        if let s = a.awaySeatID { awayLounge.remove(s); a.awaySeatID = nil }
        applyPose(a)
        notify()
    }

    private func depart(_ id: String, animated: Bool) {
        guard let a = actors.removeValue(forKey: id) else { return }
        if let pc = a.seat.pcIndex, pcOccupied[pc] == id {
            pcOccupied[pc] = nil
            pcNodes[pc]?.removeAction(forKey: "screen")
            pcNodes[pc]?.texture = assets.furnitureTexture(kit.layout.furniture[pc].assetID)
        }
        if let s = a.awaySeatID { awayLounge.remove(s); a.awaySeatID = nil }
        a.leaving = true
        a.away = true
        a.bubble?.removeFromParent(); a.bubble = nil
        a.label.isHidden = true
        let from = a.heading ?? a.tile
        let spots = kit.spots
        guard animated, let route = kit.grid.path(from: from, to: spots.entrance) else { a.root.removeFromParent(); return }
        leavingActors.append(a)
        var steps = [from] + route
        steps.append(spots.door)
        a.root.removeAction(forKey: "move")
        place(a, at: from)
        a.body.position.y = 0
        run(route: steps, for: a) { [weak self] in
            a.root.run(.fadeOut(withDuration: 0.2)) {
                MainActor.assumeIsolated {
                    a.root.removeFromParent()
                    self?.leavingActors.removeAll { $0 === a }
                    self?.notify()
                }
            }
        }
        // Kapıda solma: son adımın başında başlat (kapı karosuna girerken).
        a.root.run(.sequence([.wait(forDuration: Self.stepDuration * Double(steps.count - 2)), .fadeAlpha(to: 0.0, duration: Self.stepDuration)]), withKey: "fade")
    }

    private func hop(_ a: OfficeActor) {
        a.hopping = true
        let up = SKAction.moveBy(x: 0, y: 5, duration: 0.1), down = SKAction.moveBy(x: 0, y: -5, duration: 0.1)
        a.body.run(.sequence([up, down, up, down, .run { [weak a, weak self] in a?.hopping = false; self?.notify() }]), withKey: "hop")
    }

    // MARK: Dinlenme (kahve / kanepe)

    /// Boştayken oda içinde gidilecek yer: büyük odada kahve makinesi, diğerlerinde boşta kalan bir salon koltuğu.
    private func restTarget() -> (tile: OfficeTile, facing: OfficeCharacterSheet.Direction, seatID: Int?)? {
        if let coffee = kit.spots.coffee { return (coffee, kit.spots.coffeeFacing, nil) }
        let busy = assignedSeats.union(awayLounge)
        if let s = kit.spots.loungeSeats.first(where: { !busy.contains($0.id) }) { return (s.tile, s.facing, s.id) }
        return nil
    }

    /// Yürüyüşe çıkabilecek boştaki üyeler (zamanlayıcı karar verir).
    func wanderCandidates() -> [OfficeWander.Candidate] {
        guard restTarget() != nil else { return [] }
        return actors.values.filter { !$0.moving && !$0.away && !$0.leaving && $0.behavior.mayWander }
            .compactMap { a in a.idleSince.map { OfficeWander.Candidate(id: a.member.id, idleSince: $0) } }
    }

    /// Üyeyi dinlenme yerine yollar; kısa bekledikten sonra masasına döner. Başlayabildiyse true.
    func wander(id: String) -> Bool {
        guard let a = actors[id], let target = restTarget(), let there = kit.grid.path(from: a.tile, to: target.tile) else { return false }
        a.away = true
        a.awaySeatID = target.seatID
        if let s = target.seatID { awayLounge.insert(s) }
        a.root.zPosition = yDown(a.tile) + 0.5
        run(route: [a.tile] + there, for: a) { [weak self, weak a] in
            guard let self, let a, a.away else { return }
            a.direction = target.facing
            a.body.texture = self.assets.characterTexture(index: a.appearance.characterIndex, direction: a.direction, frame: 1)
            a.body.xScale = (OfficeCharacterSheet.mirrorsHorizontally(a.direction) ? -1 : 1) * abs(a.body.xScale)
            if target.seatID != nil { a.body.position.y = -Self.sitDrop }
            a.root.run(.sequence([.wait(forDuration: target.seatID == nil ? 6 : 10), .run { [weak self, weak a] in
                guard let self, let a, a.away else { return }
                self.sendBack(a, animated: true)
            }]), withKey: "coffee")
            self.notify()
        }
        notify()
        return true
    }

    private func sendBack(_ a: OfficeActor, animated: Bool) {
        a.root.removeAction(forKey: "coffee")
        let from = a.heading ?? a.tile
        guard animated, let route = kit.grid.path(from: from, to: a.seat.tile) else {
            a.root.removeAllActions(); a.moving = false; place(a, at: a.seat.tile); arrive(a); return
        }
        place(a, at: from)
        run(route: [from] + route, for: a) { [weak self] in self?.arrive(a) }
    }

    private func notify() { onAnimationChange?() }
}
