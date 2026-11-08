import SpriteKit

/// Ofis sahnesi: oturum başına bir oda (`OfficeRoomNode`), odalar ızgarada. İnce bir uygulayıcıdır: atama/oda kademesi/ızgara/kamera
/// hesabı saf mantıkta (`OfficeRoomPlanner`, `OfficeRoomArranger`, `OfficeCamera`). SwiftUI'ya bağımlı değildir.
/// Performans: görünmeyen odalar duraklatılır (SKAction'ları çalışmaz, `isAnimating`'e katılmaz); boşta hiçbir SKAction yoktur;
/// `onAnimationStateChange` ile ev sahibi görünümü duraklatabilir.
@MainActor
final class OfficeScene: SKScene {
    /// Oda ekleme/çıkarma, yeniden dizilim ve kamera geçişi süresi.
    static let transitionDuration: TimeInterval = 0.3

    let assets: OfficeAssets
    private let world = SKNode()
    private let cameraNode = SKCameraNode()
    private let selectionFrame = SKNode()
    private var edges: [SKSpriteNode] = []
    private var planner: OfficeRoomPlanner
    private var rooms: [String: OfficeRoomNode] = [:]
    private var order: [String] = []
    private var dying: [OfficeRoomNode] = []
    private(set) var arrangement = OfficeRoomArranger.arrange([], columns: 1)
    private(set) var zoom = 1
    /// Kamera merkezi (içerik koordinatı, y aşağı).
    private(set) var cameraCenter = CGPoint.zero
    private var panCenter = CGPoint.zero
    private var cameraPlaced = false
    private(set) var selectedRoomID: String?
    private var pending: [String: Int] = [:]
    private var generation = 0
    private var lastAnimating = false
    private var nextWander: [String: Date] = [:]
    private var lastWander: [String: Date] = [:]
    /// Ofis v3: ışık modu (varsayılan gündüz; ev sahibi kayıtlı modu verir), gece mi, tek saat-sınırı zamanlayıcısı.
    private(set) var lightingMode = OfficeLightingMode.day
    private(set) var isNight = false
    var timeZone = TimeZone.current
    private var boundaryTimer: Timer?
    /// Büyüyen odanın eski düğümü kararırken ve yeni oda belirirken.
    private var grown: Set<String> = []
    /// Detay kartı: seçili üye, son üye listesi, ilk görülme anları, son yayılan kart.
    private(set) var selectedMemberID: String?
    private var lastMembers: [OfficeMember] = []
    private var firstSeen: [String: Date] = [:]
    private var lastCard: OfficeDetailCard?
    private var tooltipNode: SKNode?
    private var tooltipLabel: SKLabelNode?
    private var tooltipBG: SKSpriteNode?
    private var hoverID: String?
    private var downCount = 1
    var onCardChange: ((OfficeDetailCard?) -> Void)?
    private var dragStart: CGPoint?
    private var dragLast: CGPoint?
    private var dragging = false

    /// true/false: sahnede çalışan animasyon var mı (ev sahibi bunu duraklatma kararında kullanır).
    var onAnimationStateChange: ((Bool) -> Void)?
    /// Kullanıcı kaydırdı: ev sahibi görünümü kısa süre canlandırıp yeniden duraklatır.
    var onActivity: (() -> Void)?
    var onSelectionChange: ((String?) -> Void)?
    /// Fare bir karakterin/tahtanın üstünde mi (imleç el işareti).
    var onHoverChange: ((Bool) -> Void)?

    // MARK: Ölçüm / test erişimi

    var isAnimating: Bool { !pending.isEmpty || rooms.values.contains { $0.isVisible && $0.isAnimating } }
    var actorCount: Int { rooms.values.reduce(0) { $0 + $1.actorCount } }
    var memberIDs: Set<String> { Set(rooms.values.flatMap { $0.actors.keys }) }
    var roomIDs: [String] { order }
    var roomCount: Int { order.count }
    var visibleRoomCount: Int { rooms.values.filter(\.isVisible).count }
    func room(_ id: String) -> OfficeRoomNode? { rooms[id] }
    /// Sahnedeki toplam düğüm sayısı (dünya altı).
    var nodeCount: Int { Self.count(world) }

    private static func count(_ n: SKNode) -> Int { n.children.reduce(1) { $0 + count($1) } }

    init(assets: OfficeAssets, size: CGSize = CGSize(width: 960, height: 600)) {
        self.assets = assets
        planner = OfficeRoomPlanner(seats: assets.kits.mapValues { $0.spots.seats })
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = SKColor(red: 0.075, green: 0.075, blue: 0.095, alpha: 1)
        addChild(world)
        buildSelectionFrame()
        addChild(cameraNode)
        camera = cameraNode
        apply(members: [], animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) yok") }

    override func didChangeSize(_ oldSize: CGSize) {
        relayout(animated: false)
        onActivity?()
    }

    // MARK: Üyeleri uygulama

    /// Üyeleri sahneye uygular. `animated == false`: herkes doğrudan son konumunda belirir (önizleme, ilk statik kare).
    func apply(members: [OfficeMember], animated: Bool, now: Date = .now) {
        lastMembers = members
        for m in members where firstSeen[m.id] == nil { firstSeen[m.id] = now }
        let liveIDs = Set(members.map(\.id))
        firstSeen = firstSeen.filter { liveIDs.contains($0.key) }
        let plan = planner.update(members: members)
        var known: [String: Set<String>] = [:]
        var byRoom: [String: [OfficeMember]] = [:]
        for m in members { byRoom[m.parentID ?? m.id, default: []].append(m) }

        var changed = false
        for id in plan.removed { removeRoom(id, animated: animated); changed = true }
        var fade: Set<String> = []
        for rp in plan.rooms {
            if let old = rooms[rp.id], old.tier == rp.tier { continue }
            let replaced = rooms[rp.id] != nil
            if let old = rooms[rp.id] {
                known[rp.id] = Set(old.actors.keys)
                if animated && old.isVisible {
                    // Büyüme/küçülme: eski zemin/duvar dokusu yumuşakça kararır, yenisi belirir (crossfade).
                    rooms[rp.id] = nil
                    track(old.root, key: "grow.\(old.id)", .fadeOut(withDuration: OfficeCarrier.growFade)) { [weak old] in old?.root.removeFromParent() }
                } else {
                    destroy(old)
                }
            }
            let node = OfficeRoomNode(id: rp.id, tier: rp.tier, assets: assets)
            node.setNight(isNight, animated: false)
            node.onAnimationChange = { [weak self] in self?.notifyAnimationState() }
            node.setZoom(zoom)
            world.addChild(node.root)
            rooms[rp.id] = node
            if animated && (!replaced || known[rp.id] != nil) { fade.insert(rp.id); node.root.alpha = 0; if replaced { grown.insert(rp.id) } }
            changed = true
        }
        let newOrder = plan.rooms.map(\.id)
        if newOrder != order { changed = true }
        order = newOrder
        if selectedRoomID.map({ rooms[$0] == nil }) == true { setSelection(nil, animated: false) }
        if changed { relayout(animated: animated, fadeIn: fade) }

        for rp in plan.rooms {
            guard let room = rooms[rp.id] else { continue }
            let ms = byRoom[rp.id] ?? []
            let newcomers: Set<String> = rp.reseated && animated && room.isVisible ? Set(ms.map(\.id)).subtracting(known[rp.id] ?? []) : []
            room.apply(plan: rp, members: ms, animated: animated && room.isVisible && !rp.reseated, now: now, newcomers: newcomers)
        }
        if let id = selectedMemberID { if liveIDs.contains(id) { emitCard() } else { setSelectedMember(nil) } }
        refreshLabels()
        notifyAnimationState()
    }

    private func destroy(_ room: OfficeRoomNode) {
        room.root.removeAllActions()
        room.root.removeFromParent()
        clearPending(prefix: room.id)
    }

    private func removeRoom(_ id: String, animated: Bool) {
        guard let room = rooms.removeValue(forKey: id) else { return }
        if selectedRoomID == id { setSelection(nil, animated: false) }
        guard animated, room.isVisible else { destroy(room); return }
        // Kısa kararma, sonra kaldır ve ızgarayı yeniden diz.
        dying.append(room)
        track(room.root, key: "\(id).fade", .sequence([.fadeAlpha(to: 0.35, duration: Self.transitionDuration * 0.4), .fadeOut(withDuration: Self.transitionDuration * 0.6)])) { [weak self, weak room] in
            guard let self, let room else { return }
            self.destroy(room)
            self.dying.removeAll { $0 === room }
            if self.dying.isEmpty { self.relayout(animated: true) }
        }
    }

    // MARK: Düzen + kamera

    /// Odaları ızgaraya dizer (pencereye göre sütun sayısı), kamerayı sığdırır/odaklar. Ölü (kararan) odalar bitene kadar yerinde kalır.
    private func relayout(animated: Bool, fadeIn: Set<String> = []) {
        guard size.width > 0, size.height > 0 else { return }
        let ordered = order.compactMap { rooms[$0] }
        guard dying.isEmpty || !animated else {
            // Kararma sürerken yeni gelenler görünmez bekler; bitince yerleşir.
            return
        }
        let sizes = ordered.map { OfficeRoomSize(id: $0.id, width: $0.frameSize.width, height: $0.frameSize.height) }
        arrangement = OfficeRoomArranger.best(sizes, viewWidth: size.width, viewHeight: size.height)
        let contentH = arrangement.contentHeight
        for cell in arrangement.cells {
            guard let room = rooms[cell.id] else { continue }
            let target = CGPoint(x: cell.x, y: contentH - cell.y - cell.height)
            if room.placed && animated && room.root.position != target {
                track(room.root, key: "\(room.id).move", .move(to: target, duration: Self.transitionDuration))
            } else {
                room.root.removeAction(forKey: "\(room.id).move")
                room.root.position = target
            }
            if !room.placed {
                room.placed = true
                if fadeIn.contains(room.id) { track(room.root, key: "\(room.id).fade", .fadeIn(withDuration: grown.remove(room.id) != nil ? OfficeCarrier.growFade : Self.transitionDuration)) } else { room.root.alpha = 1 }
            }
        }
        updateCamera(animated: animated)
    }

    private func updateCamera(animated: Bool, recenter: Bool = false) {
        let content = arrangement.contentSize
        var z: Int
        var center: CGPoint
        if let id = selectedRoomID, let cell = arrangement.cell(id: id) {
            let f = OfficeCamera.focus(on: cell.rect, content: content, view: size)
            z = f.zoom; center = f.center
            if !recenter && cameraPlaced && zoom == z { center = OfficeCamera.clamp(center: cameraCenter, content: content, view: size, zoom: z) }
        } else {
            z = OfficeCamera.fitZoom(view: size, content: content)
            center = OfficeCamera.clamp(center: panCenter, content: content, view: size, zoom: z)
            panCenter = center
        }
        applyCamera(zoom: z, center: center, animated: animated && cameraPlaced)
    }

    private func applyCamera(zoom z: Int, center: CGPoint, animated: Bool) {
        cameraCenter = center
        let pos = CGPoint(x: center.x, y: arrangement.contentHeight - center.y)
        let scale = 1 / CGFloat(z)
        if animated {
            track(cameraNode, key: "camera", .group([.move(to: pos, duration: Self.transitionDuration), .scale(to: scale, duration: Self.transitionDuration)]))
        } else {
            cameraNode.removeAction(forKey: "camera")
            clearPending(prefix: "camera")
            cameraNode.position = pos
            cameraNode.setScale(scale)
        }
        cameraPlaced = true
        if z != zoom {
            zoom = z
            for r in rooms.values { r.setZoom(z) }
        }
        refreshLabels()
        updateVisibility()
        updateSelectionFrame()
    }

    /// Görünür olmayan odaları duraklatır.
    private func updateVisibility() {
        let viewport = OfficeCamera.viewport(center: cameraCenter, view: size, zoom: zoom)
        for cell in arrangement.cells {
            guard let room = rooms[cell.id] else { continue }
            room.isVisible = cell.rect.intersects(viewport)
        }
        notifyAnimationState()
    }

    /// Ad etiketleri yalnızca yakından bakılırken: odak odası ya da (odaksızken) az kalabalık odalar, zoom ≥ 2.
    private func refreshLabels() {
        for room in rooms.values {
            let on = zoom >= 2 && (selectedRoomID == room.id || (selectedRoomID == nil && room.memberCount <= 4))
            room.setLabels(on)
            // Metin balonları: zoom ≥ 2; odak varsa yalnızca odak odasında, yoksa görünür her odada.
            room.setBubbles(zoom >= 2 && (selectedRoomID == nil || selectedRoomID == room.id))
        }
    }

    // MARK: Seçim

    private func buildSelectionFrame() {
        selectionFrame.zPosition = 40_000
        selectionFrame.isHidden = true
        for _ in 0..<4 {
            let e = SKSpriteNode(color: SKColor(red: 0.35, green: 0.75, blue: 1, alpha: 0.95), size: .zero)
            e.anchorPoint = .zero
            edges.append(e)
            selectionFrame.addChild(e)
        }
        world.addChild(selectionFrame)
    }

    private func updateSelectionFrame() {
        guard let id = selectedRoomID, let cell = arrangement.cell(id: id) else { selectionFrame.isHidden = true; return }
        selectionFrame.isHidden = false
        let t = 2 / CGFloat(zoom), pad: CGFloat = 4
        let x = CGFloat(cell.x) - pad, w = CGFloat(cell.width) + pad * 2
        let y = CGFloat(arrangement.contentHeight - cell.y - cell.height) - pad, h = CGFloat(cell.height) + pad * 2
        let rects = [CGRect(x: x, y: y, width: w, height: t), CGRect(x: x, y: y + h - t, width: w, height: t),
                     CGRect(x: x, y: y, width: t, height: h), CGRect(x: x + w - t, y: y, width: t, height: h)]
        for (e, r) in zip(edges, rects) { e.position = r.origin; e.size = r.size }
    }

    /// Odayı seçer (kamera yakınlaşır) ya da seçimi kaldırır (kamera geri çıkar).
    func select(_ id: String?, animated: Bool = true) {
        if let id, rooms[id] == nil || rooms[id]?.isPlaceholder == true { return }
        guard id != selectedRoomID else { return }
        setSelection(id, animated: animated)
    }

    private func setSelection(_ id: String?, animated: Bool) {
        selectedRoomID = id
        onSelectionChange?(id)
        updateCamera(animated: animated, recenter: true)
        notifyAnimationState()
    }

    // MARK: Girdi (görünüm koordinatı: sol-alt başlangıçlı, y yukarı)

    func pointerDown(at p: CGPoint, clickCount: Int = 1) { dragStart = p; dragLast = p; dragging = false; downCount = clickCount }

    func pointerDragged(to p: CGPoint) {
        guard let start = dragStart, let last = dragLast else { return }
        if !dragging, hypot(p.x - start.x, p.y - start.y) > 4 { dragging = true }
        if dragging { pan(dx: -(p.x - last.x), dy: p.y - last.y) }
        dragLast = p
    }

    func pointerUp(at p: CGPoint) {
        defer { dragStart = nil; dragLast = nil; dragging = false }
        guard dragStart != nil, !dragging else { return }
        click(at: p, count: downCount)
    }

    /// Fare tekerleği/iki parmak kaydırma: içerik parmakla birlikte hareket eder.
    func scroll(deltaX: CGFloat, deltaY: CGFloat) { pan(dx: -deltaX, dy: -deltaY) }

    /// Esc: seçimi kaldırır.
    func escape() { if selectedMemberID != nil { setSelectedMember(nil) } else { select(nil) } }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { escape() } else { super.keyDown(with: event) }
    }

    /// Kamera merkezini (görünüm piksel farkı / zoom) kaydırır; içerik pencereye sığıyorsa etkisizdir.
    private func pan(dx: CGFloat, dy: CGFloat) {
        let z = CGFloat(zoom)
        let moved = CGPoint(x: cameraCenter.x + dx / z, y: cameraCenter.y + dy / z)
        let c = OfficeCamera.clamp(center: moved, content: arrangement.contentSize, view: size, zoom: zoom)
        guard c != cameraCenter else { return }
        cameraNode.removeAction(forKey: "camera")
        clearPending(prefix: "camera")
        cameraCenter = c
        if selectedRoomID == nil { panCenter = c }
        cameraNode.position = CGPoint(x: c.x, y: arrangement.contentHeight - c.y)
        updateVisibility()
        onActivity?()
    }

    private func click(at p: CGPoint, count: Int) {
        if let h = hit(atView: p) {
            // Çift tık: odaya yakınlaş (kart açık kalır). Tek tık: karakter/tahta → detay kartı.
            if count >= 2 { select(h.room.id) } else { setSelectedMember(h.memberID) }
            return
        }
        if selectedMemberID != nil { setSelectedMember(nil); return }   // boşluğa tıklama kartı kapatır
        let pt = OfficeCamera.contentPoint(fromView: p, view: size, center: cameraCenter, zoom: zoom)
        if let cell = arrangement.cell(at: pt), rooms[cell.id]?.isPlaceholder == false {
            select(cell.id == selectedRoomID ? nil : cell.id)
        } else if selectedRoomID != nil {
            select(nil)
        }
    }

    // MARK: Kahve / dinlenme

    /// Düşük frekanslı tek zamanlayıcı (ev sahibi): görünür odalarda kahve yürüyüşü (oda başına 1-2 kişi), masada boşta varyantları ve
    /// temizlikçi. Yalnızca görünür odalar; hepsi sonlu SKAction. Bir şey başladıysa true.
    @discardableResult
    func wanderTick(now: Date = .now, roll: Double = .random(in: 0..<1)) -> Bool {
        var started = false
        for r in order.compactMap({ rooms[$0] }) where r.isVisible && !r.isPlaceholder {
            let limit = OfficeIdle.maxWanderers(memberCount: r.memberCount)
            if nextWander[r.id].map({ now >= $0 }) ?? true,
               let id = OfficeWander.pick(r.wanderCandidates(), now: now, lastWander: lastWander[r.id], someoneWalking: r.walkerCount >= limit, roll: roll, chance: OfficeIdle.wanderChance),
               r.wander(id: id) {
                lastWander[r.id] = now
                nextWander[r.id] = now.addingTimeInterval(OfficeIdle.gap(roll: .random(in: 0..<1)))
                started = true
            }
            if r.variantCount < 2, Double.random(in: 0..<1) < 0.6, let c = r.idleCandidates().randomElement(), r.startIdleVariant(id: c.member.id) != nil { started = true }
            if r.cleanerTick(now: now) { started = true }
        }
        if started { notifyAnimationState() }
        return started
    }

    // MARK: Işık (gün / gece)

    /// Mod değişince (menü) ya da ev sahibi ilk kurulumda çağırır. Otomatikte bir sonraki saat sınırı için TEK Timer kurulur.
    func setLightingMode(_ mode: OfficeLightingMode, now: Date = .now, animated: Bool = true) {
        lightingMode = mode
        refreshLighting(now: now, animated: animated)
    }

    private func refreshLighting(now: Date, animated: Bool) {
        boundaryTimer?.invalidate()
        boundaryTimer = nil
        if lightingMode == .auto, let next = OfficeLighting.nextBoundary(after: now, timeZone: timeZone) {
            let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshLighting(now: .now, animated: true) }
            }
            timer.tolerance = 30
            RunLoop.main.add(timer, forMode: .common)
            boundaryTimer = timer
        }
        let night = OfficeLighting.isNight(mode: lightingMode, date: now, timeZone: timeZone)
        guard night != isNight else { return }
        isNight = night
        for r in rooms.values { r.setNight(night, animated: animated) }
        if animated { track(world, key: "lighting", .wait(forDuration: OfficeLighting.crossfade + 0.1)) }
    }

    /// Ev sahibi kapanırken zamanlayıcıyı bırakır.
    func shutdown() { boundaryTimer?.invalidate(); boundaryTimer = nil }

    // MARK: Üzerine gelme + detay kartı

    /// Görünüm noktasındaki karakter (ya da tahta → yönetici) ve odası.
    func hit(atView p: CGPoint) -> (room: OfficeRoomNode, memberID: String)? {
        let pt = OfficeCamera.contentPoint(fromView: p, view: size, center: cameraCenter, zoom: zoom)
        guard let cell = arrangement.cell(at: pt), let room = rooms[cell.id], !room.isPlaceholder, room.isVisible else { return nil }
        let local = CGPoint(x: pt.x - cell.x, y: cell.y + cell.height - pt.y)
        if let a = room.actor(atLocal: local) { return (room, a.member.id) }
        if room.boardContains(local), let id = room.executiveMemberID { return (room, id) }
        return nil
    }

    func card(for id: String) -> OfficeDetailCard? {
        guard let m = lastMembers.first(where: { $0.id == id }) else { return nil }
        return OfficeDetailCard.make(member: m, members: lastMembers, spawnedAt: firstSeen[id])
    }

    func setSelectedMember(_ id: String?) {
        selectedMemberID = id
        emitCard()
    }

    private func emitCard() {
        let card = selectedMemberID.flatMap { card(for: $0) }
        guard card != lastCard else { return }
        lastCard = card
        onCardChange?(card)
    }

    /// Fare hareketi (görünüm koordinatı). Karakterin üstünde ad · rol · model · durum satırı; imleç değişimi için `onHoverChange`.
    func hover(at p: CGPoint?) {
        guard dragStart == nil, let p, let h = hit(atView: p), let card = card(for: h.memberID), let top = h.room.actorTop(id: h.memberID) ?? h.room.actorTop(id: h.memberID) else {
            hideTooltip()
            return
        }
        if hoverID != h.memberID { hoverID = h.memberID; onHoverChange?(true) }
        let node = tooltipNode ?? makeTooltip()
        tooltipLabel?.text = card.tooltip
        let w = (tooltipLabel?.frame.width ?? 40) + 10
        tooltipBG?.size = CGSize(width: w, height: 14)
        node.setScale(1 / CGFloat(zoom))
        node.position = CGPoint(x: h.room.root.position.x + top.x, y: h.room.root.position.y + top.y + 10 / CGFloat(zoom))
        node.isHidden = false
        onActivity?()
    }

    private func hideTooltip() {
        if tooltipNode?.isHidden == false { tooltipNode?.isHidden = true; onActivity?() }
        if hoverID != nil { hoverID = nil; onHoverChange?(false) }
    }

    private func makeTooltip() -> SKNode {
        let node = SKNode()
        node.zPosition = 45_000
        let bg = SKSpriteNode(color: SKColor(white: 0.04, alpha: 0.92), size: CGSize(width: 60, height: 14))
        bg.anchorPoint = CGPoint(x: 0.5, y: 0)
        let label = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        label.fontSize = 9
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: 7)
        label.zPosition = 1
        node.addChild(bg); node.addChild(label)
        world.addChild(node)
        tooltipNode = node; tooltipLabel = label; tooltipBG = bg
        return node
    }

    // MARK: Geçiş takibi

    /// Bir düğümde, bitince `pending`'den düşen eylem çalıştırır; ev sahibi bitene kadar görünümü duraklatmaz.
    private func track(_ node: SKNode, key: String, _ action: SKAction, completion: (@MainActor () -> Void)? = nil) {
        generation += 1
        let gen = generation
        pending[key] = gen
        node.run(.sequence([action, .run { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pending[key] == gen else { return }
                self.pending[key] = nil
                completion?()
                self.notifyAnimationState()
            }
        }]), withKey: key)
        notifyAnimationState()
    }

    private func clearPending(prefix: String) {
        for k in pending.keys where k.hasPrefix(prefix) { pending[k] = nil }
    }

    // MARK: Animasyon durumu

    private func notifyAnimationState() {
        let now = isAnimating
        guard now != lastAnimating else { return }
        lastAnimating = now
        onAnimationStateChange?(now)
    }
}
