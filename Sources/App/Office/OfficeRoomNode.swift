import SpriteKit

/// Karakter başına tek metin balonu: 9-dilimli arka plan sprite'ı + tek SKLabelNode (yeniden kullanılır; metin değişmedikçe dokunulmaz).
/// Ekran sabit boyutludur (`node` ölçeği 1/zoom); kuyruk ucu `node` orijinindedir. `flipped`: gövde sola uzanır (odanın sağ yarısı).
/// Vektör tema: yuvarlak beyaz balon + yumuşak gölge, sistem yazısı; `height`/`tailX` temaya göre.
@MainActor
final class OfficeTextBubble {
    /// Ekran pikseli (piksel tema): 12 gövde + 2 kuyruk.
    static let height: CGFloat = 14
    let node = SKNode()
    let background: SKSpriteNode
    let label: SKLabelNode
    let theme: OfficeTheme
    private(set) var text = ""
    private(set) var width: CGFloat = 0
    private(set) var flipped = false

    /// Kuyruk ucundan balon üstüne yükseklik ve kuyruk ucunun gövde sol kenarına uzaklığı (ekran pt).
    var height: CGFloat { theme == .vector ? OfficeVectorUI.bubbleHeight : Self.height }
    var tailX: CGFloat { theme == .vector ? OfficeVectorUI.bubbleTipX : OfficePixelArt.speechBubbleTailX }

    init(theme: OfficeTheme = .pixel) {
        self.theme = theme
        let vec = theme == .vector
        label = vec ? SKLabelNode() : SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        background = SKSpriteNode(color: .clear, size: CGSize(width: 22, height: vec ? CGFloat(OfficeVectorUI.bubbleTexH) : Self.height))
        background.anchorPoint = .zero
        label.fontSize = 9
        label.fontColor = SKColor(white: 0.13, alpha: 1)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        background.zPosition = 0
        label.zPosition = 1
        node.addChild(background)
        node.addChild(label)
        node.isHidden = true
    }

    func setText(_ value: String, assets: OfficeAssets) {
        text = value
        if theme == .vector {
            label.attributedText = OfficeVectorUI.text(value, size: 9.5, color: NSColor(srgbRed: 0.17, green: 0.18, blue: 0.22, alpha: 1))
            width = max(OfficeVectorUI.bubbleMinBody, (label.frame.width + 14).rounded(.up))
            width = width.rounded(.up)
            if let texture = assets.bubbleBodyTexture(bodyWidth: Int(width)) {
                background.texture = texture
                background.color = .white
                background.colorBlendFactor = 0
            }
            background.size = CGSize(width: width + 2 * OfficeVectorUI.bubblePad, height: CGFloat(OfficeVectorUI.bubbleTexH))
            layout()
            return
        }
        label.text = value
        width = max(18, (label.frame.width + 10).rounded(.up))
        if let texture = assets.speechBubbleTexture(width: Int(width)) {
            background.texture = texture
            background.color = .white
            background.colorBlendFactor = 0
        }
        background.size = CGSize(width: width, height: Self.height)
        layout()
    }

    func setFlipped(_ value: Bool) {
        guard value != flipped else { return }
        flipped = value
        layout()
    }

    private func layout() {
        background.xScale = flipped ? -1 : 1
        if theme == .vector {
            let tip = OfficeVectorUI.bubblePad + OfficeVectorUI.bubbleTipX
            background.position = CGPoint(x: flipped ? tip : -tip, y: -OfficeVectorUI.bubblePad)
            label.position = CGPoint(x: flipped ? OfficeVectorUI.bubbleTipX - width / 2 : width / 2 - OfficeVectorUI.bubbleTipX, y: 11)
            return
        }
        let tail = OfficePixelArt.speechBubbleTailX
        background.position = CGPoint(x: flipped ? tail : -tail, y: 0)
        label.position = CGPoint(x: flipped ? tail - width / 2 : width / 2 - tail, y: 8)
    }
}

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
    /// Yönetici: beyaz tahtaya gidiyor/orada (`toBoard`) ve tahtanın önünde ayakta (`atBoard`).
    var toBoard = false
    var atBoard = false
    /// Yönetici volta döngüsü açık (yürüyüş + duraklamalar); boşta 60 sn sonra kapanır.
    var strolling = false
    /// Boşa geçişte kurulan volta bitiş anı (nil: volta yok); mod hesabı `OfficeExecutive.mode`.
    var strollUntil: Date?
    var strollCount = 0
    var lookCount = 0
    /// Konuşma balonu: istenen metin (nil: yok), süresi doldu mu, süre sayacının dayandığı etkinlik anı, sayaç çalışıyor mu.
    var textBubble: OfficeTextBubble?
    var bubbleText: String?
    var bubbleExpired = false
    var bubbleActivityAt: Date?
    var bubbleTimer = false
    /// Rol aksesuarı (alt ajan), boşta varyantı (oturan döngü) ve varyant yan düğümü.
    var roleAccessory: SKSpriteNode?
    var idleVariant: OfficeIdleVariant?
    var idleOverlay: SKNode?
    var idleCount = 0
    /// Vektör: ad etiketi parçaları (gece/gündüz stili değişince yeniden boyanır).
    var labelPill: SKSpriteNode?
    var labelName: SKLabelNode?
    var labelTitle = ""
    var labelBodyW = 0
    var labelDot: SKSpriteNode?
    /// Çakışma çözümü: metin biçimleri, ekran genişlikleri, seçili biçim ve dikey kademe (yalnızca vektör).
    var labelVariants: [String] = []
    var labelWidths: [CGFloat] = []
    var labelVariant = 0
    var labelLevel = 0
    /// Taşıyıcı: koli vektör temada gövdeye pişirilmiş "taşıma" karelerini kullanır.
    var carryingBox = false

    var isExecutive: Bool { seat.kind == .executive }
    /// Ayakta (tahta önünde ya da voltada): oturma çökmesi yok.
    var upright: Bool { atBoard || strolling }

    init(member: OfficeMember, appearance: OfficeAppearance, seat: OfficeSeat, texture: SKTexture, theme: OfficeTheme = .pixel) {
        self.member = member; self.appearance = appearance; self.seat = seat; self.tile = seat.tile
        behavior = OfficeBehavior.behavior(for: member.status, atDesk: seat.kind == .desk, executive: seat.kind == .executive)
        body = SKSpriteNode(texture: texture)
        body.anchorPoint = CGPoint(x: 0.5, y: 0)
        if theme == .vector {
            // Vektör: kıyafet rengi ve aksesuar dokuya pişirilmiş (16 genişlik figür + 4'er kenar boşluğu); çalışma zamanı tonu yok.
            body.size = CGSize(width: CGFloat(OfficeVectorCharacter.canvasW), height: CGFloat(OfficeVectorCharacter.canvasH))
            body.colorBlendFactor = 0
        } else {
            body.size = CGSize(width: 16, height: 32)
            body.color = SKColor(red: appearance.tint.r, green: appearance.tint.g, blue: appearance.tint.b, alpha: 1)
            body.colorBlendFactor = appearance.tintBlend
        }
        root.addChild(body)
    }

    var isAnimating: Bool {
        moving || hopping || leaving || bubbleTimer || strolling || idleVariant != nil || (!away && (behavior.pose == .typing || behavior.bubble == .alert || behavior.pcOn))
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
    let theme: OfficeTheme
    let kit: OfficeRoomKit
    /// Yalnızca yönetici bölgesinin karolarının yürünür olduğu ızgara: volta rotaları bölgeden çıkmaz.
    private let zoneGrid: OfficeGrid?
    let root = SKNode()
    private let content = SKNode()

    private(set) var actors: [String: OfficeActor] = [:]
    private var leavingActors: [OfficeActor] = []
    private var pcNodes: [Int: SKSpriteNode] = [:]
    private var pcOccupied: [Int: String] = [:]
    private var pcComputer: [Int: OfficeComputer] = [:]
    private var furnitureNodes: [Int: SKNode] = [:]
    /// Gece ışığı katmanı (yalnızca gece + görünür odada kurulur) ve ekran parıltıları.
    private(set) var nightWanted = false
    private var nightRoot: SKNode?
    /// Vektör tema: gece pencereleri (ışık örtüsünün altında kalan, karakterlerin arkasındaki katman).
    private var nightWindows: SKNode?
    private var screenGlows: [Int: SKSpriteNode] = [:]
    /// Temizlikçi / taşıyıcı durumu (oda başına bir kerede bir).
    private(set) var cleanerDueAt: Date?
    private var cleaning = false
    private var carrying = false
    private var cleanerRuns = 0
    private var pendingSpawns: [String: (member: OfficeMember, seat: OfficeSeat)] = [:]
    private var assignedSeats: Set<Int> = []
    private var awayLounge: Set<Int> = []
    /// Yönetici beyaz tahtasının üstündeki "yazıyor" katmanı (yalnızca yönetici yazarken kurulur/oynar).
    private var boardOverlay: SKSpriteNode?
    private(set) var zoom: CGFloat = 1
    private(set) var labelsOn = false
    private var lastLabelItems: [OfficeLabelItem] = []
    private var lastLabelZoom: CGFloat = 0
    /// Metin balonları yalnızca yakından bakılırken (zoom ≥ 2) ve görünür/odaklı odalarda kurulur (düğüm tasarrufu); "…" balonu uzakta kalır.
    private(set) var bubblesOn = false
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
        didSet {
            guard isVisible != oldValue else { return }
            content.isPaused = !isVisible
            if isVisible && bubblesOn { for a in actors.values { renderBubble(a) } }
            if isVisible && nightWanted && nightRoot == nil { setNight(true, animated: false) }
            nightRoot?.isHidden = !(isVisible && nightWanted)
            nightWindows?.isHidden = !(isVisible && nightWanted)
        }
    }

    init(id: String, tier: OfficeRoomTier, assets: OfficeAssets, theme: OfficeTheme = .pixel) {
        self.id = id; self.tier = tier; self.assets = assets; self.theme = theme
        let kit = assets.kit(tier)
        self.kit = kit
        zoneGrid = kit.spots.zone.map { kit.grid.restricted(to: $0) }
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
    /// Yönetici tahtada yazıyor mu (yazma katmanı görünür ve oynuyor).
    var isBoardWriting: Bool { boardOverlay.map { !$0.isHidden && $0.action(forKey: "write") != nil } ?? false }

    // MARK: Koordinatlar

    /// Karonun alt-orta noktası (odanın yerel koordinatı, y yukarı).
    func point(_ t: OfficeTile) -> CGPoint {
        let b = kit.bounds
        return CGPoint(x: CGFloat((t.col - b.minCol) * 16 + 8), y: CGFloat(kit.worldHeight - (t.row - b.minRow + 1) * 16) + 1)
    }

    private func yDown(_ t: OfficeTile) -> CGFloat { CGFloat((t.row + 1) * 16) }

    /// Tema'ya göre karakter karesi (piksel: sheet dilimi; vektör: tembel üretilen parametrik kare).
    private func tex(_ a: OfficeActor, _ d: OfficeCharacterSheet.Direction, _ frame: Int) -> SKTexture {
        assets.characterTexture(for: a.appearance, direction: d, frame: frame, theme: theme, night: nightWanted)
    }

    /// Vektör gece: çarpan örtüsü karakteri de karartır; hafif sıcak ton karışımı ile okunur kalır.
    private func nightLift(_ a: OfficeActor) {
        guard theme == .vector else { return }
        // Gece rengi dokuya pişirilir (`OfficeVectorCharacter.nightGrade`); duran karakterin dokusu yenilenir.
        a.body.colorBlendFactor = 0
        if !a.moving, !a.away, !a.leaving, a.idleVariant == nil, actors[a.member.id] === a, !a.hopping { applyPose(a) }
    }

    // MARK: Kurulum

    private func buildWorld() {
        let bg = SKSpriteNode(texture: assets.background(tier, theme: theme))
        bg.size = CGSize(width: kit.worldWidth, height: kit.worldHeight)
        bg.anchorPoint = .zero
        bg.zPosition = 0
        content.addChild(bg)

        let b = kit.bounds
        for (i, f, a) in kit.dynamicFurniture {
            guard let tex = assets.furnitureTexture(a.id, theme: theme) else { continue }
            let node = SKSpriteNode(texture: tex)
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.size = CGSize(width: a.width, height: a.height)
            node.xScale = f.mirrored ? -1 : 1
            node.position = CGPoint(x: CGFloat((f.col - b.minCol) * 16 + a.width / 2), y: CGFloat(kit.worldHeight - ((f.row - b.minRow) * 16 + a.height)))
            // Öne-arkaya sıralama: ayak izi alt kenarı; yüzeydekiler (PC) sahibinin biraz üstünde.
            node.zPosition = CGFloat((f.row + a.footprintH) * 16) + (a.onSurface ? 0.2 : 0) + (OfficeAssets.isFrontChair(a) ? 0.8 : 0)
            content.addChild(node)
            furnitureNodes[i] = node
            if a.id == "PC_FRONT_OFF" { configureComputer(node, pc: i) } else if a.id.hasSuffix("_OFF") { pcNodes[i] = node }
        }

        if let door = assets.doorTexture(theme: theme) {
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

    func setZoom(_ z: CGFloat) {
        zoom = z
        for a in actors.values { applyScale(a) }
        for a in leavingActors { applyScale(a) }
        resolveOverlays()
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

    private static func ns(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    /// Vektör başlık kartı: yuvarlak köşeli açık/koyu kart, kalın ad, renkli model rozeti, oturum renginde ince alt çizgi.
    private func layoutPlaqueVector() {
        let z = zoom
        plaque.setScale(1 / z)
        plaque.position = CGPoint(x: 2, y: CGFloat(kit.worldHeight) + 3)
        let night = nightWanted
        let panel = OfficeVectorUI.cardPanel(night: night)
        let pad = panel.pad
        let height = CGFloat(panel.h) - 2 * pad
        let placeholder = title == nil
        let look = badge.map { OfficeAppearance.appearance(for: $0) }
        let g = OfficeAppearance.groupColors[group % OfficeAppearance.groupColors.count]
        let maxW = CGFloat(kit.worldWidth) * z - 6 - (overflowNode == nil ? 0 : overflowWidth + 6)
        let ink = Self.ns(night ? 0xEEF1F8 : 0x1E222B)

        var badgeW: CGFloat = 0
        if let look {
            plaqueBadge.attributedText = OfficeVectorUI.text(look.badgeText, size: 8.5, weight: .bold, color: .white)
            badgeW = plaqueBadge.frame.width + 11
        }
        let badgeSpace: CGFloat = look == nil ? 0 : badgeW + 6
        let textMax = max(24, maxW - 18 - badgeSpace)
        var shown = title ?? Self.placeholderTitle
        plaqueName.attributedText = OfficeVectorUI.text(shown, size: 12, weight: .bold, color: ink)
        if plaqueName.frame.width > textMax {
            var chars = Array(shown)
            while chars.count > 1 {
                chars.removeLast()
                let t = String(chars) + "…"
                plaqueName.attributedText = OfficeVectorUI.text(t, size: 12, weight: .bold, color: ink)
                shown = t
                if plaqueName.frame.width <= textMax { break }
            }
        }
        plaqueName.attributedText = OfficeVectorUI.text(shown, size: 12, weight: .bold, color: placeholder ? Self.ns(night ? 0xA7AEBF : 0x7A8190) : ink)
        let nameW = plaqueName.frame.width
        let width = 9 + nameW + 9 + badgeSpace
        let bodyW = Int(width.rounded(.up))
        if let tex = assets.panelTexture(panel, bodyWidth: bodyW) {
            plaquePill.texture = tex
            plaquePill.color = .white; plaquePill.colorBlendFactor = 0
        }
        plaquePill.size = CGSize(width: CGFloat(bodyW) + 2 * pad, height: CGFloat(panel.h))
        plaquePill.position = CGPoint(x: -pad, y: -pad)
        plaquePill.alpha = placeholder ? 0.7 : 1
        plaqueName.horizontalAlignmentMode = .left
        plaqueName.position = CGPoint(x: 9, y: height / 2 + 1.6)
        let stripe = placeholder ? OfficeRGB(r: 0.5, g: 0.5, b: 0.55) : g
        let stripeW = Int(max(8, width - 18).rounded(.up))
        plaqueStripe.texture = assets.solidTexture(width: stripeW, height: 2)
        plaqueStripe.colorBlendFactor = 1
        plaqueStripe.color = SKColor(red: stripe.r, green: stripe.g, blue: stripe.b, alpha: 1)
        plaqueStripe.size = CGSize(width: CGFloat(stripeW), height: 2)
        plaqueStripe.position = CGPoint(x: 9, y: 1.4)
        if let look {
            plaqueBadgeBG.isHidden = false; plaqueBadge.isHidden = false
            plaqueBadgeBG.texture = assets.solidTexture(width: Int(badgeW.rounded(.up)), height: 13)
            plaqueBadgeBG.colorBlendFactor = 1
            plaqueBadgeBG.color = SKColor(red: look.tint.r * 0.82, green: look.tint.g * 0.82, blue: look.tint.b * 0.82, alpha: 1)
            plaqueBadgeBG.size = CGSize(width: badgeW.rounded(.up), height: 13)
            plaqueBadgeBG.position = CGPoint(x: 9 + nameW + 6, y: (height - 13) / 2 + 1.4)
            plaqueBadge.horizontalAlignmentMode = .center
            plaqueBadge.position = CGPoint(x: 9 + nameW + 6 + badgeW / 2, y: height / 2 + 1.4)
        } else {
            plaqueBadgeBG.isHidden = true; plaqueBadge.isHidden = true
        }
        if let o = overflowNode {
            o.setScale(1 / z)
            o.position = CGPoint(x: CGFloat(kit.worldWidth) - 2, y: CGFloat(kit.worldHeight) + 3)
        }
    }

    private func layoutChrome() {
        if theme == .vector { layoutPlaqueVector(); return }
        let z = zoom
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
            if theme == .vector { text.attributedText = OfficeVectorUI.text("+\(n)", size: 12, weight: .bold, color: .white) }
            text.verticalAlignmentMode = .center
            text.horizontalAlignmentMode = .right
            let w = text.frame.width + 14
            let pill = SKSpriteNode(color: SKColor(red: 0.86, green: 0.24, blue: 0.2, alpha: 0.95), size: CGSize(width: w, height: 20))
            if theme == .vector, let solid = assets.solidTexture(width: Int(w.rounded(.up)), height: 21) {
                pill.texture = solid
                pill.colorBlendFactor = 1; pill.color = SKColor(red: 0.89, green: 0.30, blue: 0.27, alpha: 1)
                pill.size = CGSize(width: w.rounded(.up), height: 21)
            }
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
        resolveOverlays()
    }

    /// Metin balonlarını açar/kapatır (kapanınca düğümler gizlenir, yeniden kullanılır; "…" balonu geri gelir).
    func setBubbles(_ on: Bool) {
        guard on != bubblesOn else { return }
        bubblesOn = on
        for a in actors.values {
            renderBubble(a)
            if !a.moving && !a.away && !a.leaving { setBubble(a) }
        }
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
        if theme == .vector { buildVectorLabel(a); return }
        let name = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        name.fontSize = 9
        // Yönetici (ana ajan) etiketi ayrı görünür: "★ ad".
        // Alt ajan: rol adı kısaltmasız (en çok 22 karakter), rol renginde; model rengi solda minik nokta.
        name.text = a.isExecutive ? "★ " + Self.truncated(a.member.label, 9) : (a.appearance.role.map { Self.truncated($0.name, 22) } ?? Self.truncated(a.member.label, 11))
        let t = a.appearance.role?.labelColor ?? OfficeRGB(r: min(1, a.appearance.tint.r + 0.35), g: min(1, a.appearance.tint.g + 0.35), b: min(1, a.appearance.tint.b + 0.35))
        name.fontColor = SKColor(red: t.r, green: t.g, blue: t.b, alpha: 1)
        name.verticalAlignmentMode = .center
        name.horizontalAlignmentMode = .center
        let dotSpace: CGFloat = a.appearance.modelDot == nil ? 0 : 7
        let width = name.frame.width + 8 + dotSpace
        let pill = SKSpriteNode(color: SKColor(white: 0.04, alpha: 0.85), size: CGSize(width: width, height: 13))
        pill.anchorPoint = CGPoint(x: 0.5, y: 0)
        pill.position = CGPoint(x: 0, y: 2)
        let g = OfficeAppearance.groupColors[a.member.groupIndex % OfficeAppearance.groupColors.count]
        let stripe = SKSpriteNode(color: SKColor(red: g.r, green: g.g, blue: g.b, alpha: 1), size: CGSize(width: width, height: 2))
        stripe.anchorPoint = CGPoint(x: 0.5, y: 0)
        stripe.position = .zero
        name.position = CGPoint(x: dotSpace / 2, y: 2 + 7)
        for n in [pill, stripe, name] as [SKNode] { a.label.addChild(n) }
        if let dot = a.appearance.modelDot {
            let d = SKSpriteNode(color: SKColor(red: dot.r, green: dot.g, blue: dot.b, alpha: 1), size: CGSize(width: 4, height: 4))
            d.position = CGPoint(x: -width / 2 + 5, y: 2 + 6.5)
            d.zPosition = 1
            a.label.addChild(d)
        }
        a.label.setScale(1 / zoom)
        positionAccessoryAndBubble(a)
    }

    /// Vektör etiket: tek yuvarlak "hap" (9-dilim doku, gölgeli), solda rol/model renk noktası, sistem yazısı (yarı kalın).
    private func buildVectorLabel(_ a: OfficeActor) {
        let full = a.isExecutive ? "★ " + Self.truncated(a.member.label, 9) : (a.appearance.role.map { Self.truncated($0.name, 22) } ?? Self.truncated(a.member.label, 11))
        a.labelVariants = OfficeLabelLayout.variants(of: full)
        a.labelTitle = full
        let pill = SKSpriteNode(color: .white, size: CGSize(width: 30, height: 21))
        pill.anchorPoint = CGPoint(x: 0.5, y: 0)
        pill.zPosition = 0
        let name = SKLabelNode()
        name.verticalAlignmentMode = .center
        name.horizontalAlignmentMode = .left
        name.zPosition = 2
        a.labelPill = pill; a.labelName = name
        a.labelWidths = a.labelVariants.map { v in
            name.attributedText = OfficeVectorUI.text(v, size: 10, weight: .semibold, color: Self.ns(0x1F2330))
            return (name.frame.width + 25).rounded(.up)
        }
        let c = a.appearance.role?.tint ?? a.appearance.tint
        let dot = SKSpriteNode(color: SKColor(red: c.r, green: c.g, blue: c.b, alpha: 1), size: CGSize(width: 5.5, height: 5.5))
        if let solid = assets.solidTexture(width: 6, height: 6) { dot.texture = solid }
        dot.colorBlendFactor = 1
        dot.zPosition = 1
        a.labelDot = dot
        applyLabelVariant(a, 0)
        for n in [pill, dot, name] as [SKNode] { a.label.addChild(n) }
        a.label.setScale(1 / zoom)
        positionAccessoryAndBubble(a)
    }

    /// Etiketi seçili metin biçimine göre boyutlandırır (hap genişliği, yazı ve nokta konumu).
    private func applyLabelVariant(_ a: OfficeActor, _ v: Int) {
        guard let pill = a.labelPill, let name = a.labelName, let dot = a.labelDot, v < a.labelVariants.count else { return }
        a.labelVariant = v
        a.labelTitle = a.labelVariants[v]
        let w = a.labelWidths[v]
        a.labelBodyW = Int(w)
        styleLabel(a)
        let pad = OfficeVectorUI.labelPanel(night: false).pad
        pill.size = CGSize(width: w + 2 * pad, height: 21)
        pill.position = CGPoint(x: 0, y: -pad + 1.5)
        name.position = CGPoint(x: -w / 2 + 17, y: 9.3)
        dot.position = CGPoint(x: -w / 2 + 10.5, y: 9.3)
    }

    /// Etiket stili (gündüz açık yüzey / gece koyu cam).
    private func styleLabel(_ a: OfficeActor) {
        guard let pill = a.labelPill, let name = a.labelName else { return }
        let night = nightWanted
        let panel = OfficeVectorUI.labelPanel(night: night)
        if a.labelBodyW > 0, let t = assets.panelTexture(panel, bodyWidth: a.labelBodyW) { pill.texture = t }
        name.attributedText = OfficeVectorUI.text(a.labelTitle, size: 10, weight: .semibold, color: Self.ns(night ? 0xEEF1F8 : 0x1F2330))
    }

    private func restyleChrome() {
        guard theme == .vector else { return }
        for a in actors.values where a.labelBuilt { styleLabel(a) }
        layoutPlaqueVector()
    }

    static func truncated(_ s: String, _ n: Int) -> String { s.count <= n ? s : String(s.prefix(n - 1)) + "…" }

    // MARK: Uygulama

    /// Plan çıktısını odaya uygular. `animated == false`: herkes doğrudan son konumunda belirir.
    func apply(plan: OfficeRoomPlan, members: [OfficeMember], animated: Bool, now: Date, newcomers: Set<String> = []) {
        memberCount = plan.memberCount
        setTitle(title: plan.title, badge: plan.badge, group: plan.groupIndex)
        for id in plan.departed { depart(id, animated: animated) }
        assignedSeats = Set(plan.placements.values.compactMap { if case .seat(let s) = $0 { s } else { nil } })
        let live = Set(members.map(\.id))
        pendingSpawns = pendingSpawns.filter { live.contains($0.key) }
        // Büyümede yeni masaya oturacak yeni gelen varsa önce taşıyıcı masayı getirir; ajan sonra yürüyüp oturur.
        var carrierBlock: (seat: OfficeSeat, ids: [String])?
        if animated || !newcomers.isEmpty, isVisible, !carrying, let prev = plan.previousTier, !newcomers.isEmpty {
            let fresh = OfficeCarrier.newDeskSeats(old: assets.kit(prev).spots.seats, new: kit.spots.seats)
            for m in members where newcomers.contains(m.id) {
                if case .seat(let sid)? = plan.placements[m.id], let seat = fresh.first(where: { $0.id == sid }) { carrierBlock = (seat, [m.id]); break }
            }
        }
        for m in members {
            guard case .seat(let seatID)? = plan.placements[m.id], let seat = kit.spots.seats.first(where: { $0.id == seatID }) else { continue }
            if let actor = actors[m.id] { update(actor, member: m, now: now, animated: animated) }
            else if pendingSpawns[m.id] != nil || carrierBlock?.ids.contains(m.id) == true { pendingSpawns[m.id] = (m, seat) }
            else { spawn(m, seat: seat, animated: animated || newcomers.contains(m.id), now: now) }
        }
        if let block = carrierBlock { startCarrier(for: block.seat) }
        setOverflow(plan.overflowCount)
        notify()
    }

    private func spawn(_ m: OfficeMember, seat: OfficeSeat, animated: Bool, now: Date) {
        let look = OfficeAppearance.appearance(for: m)
        let actor = OfficeActor(member: m, appearance: look, seat: seat,
                                texture: assets.characterTexture(for: look, direction: seat.facing, frame: 1, theme: theme, night: nightWanted), theme: theme)
        nightLift(actor)
        actor.idleSince = now
        actors[m.id] = actor
        evaluateBubble(actor, now: now)
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
            arrive(actor, animated: false)
        }
    }

    private func applyScale(_ a: OfficeActor) {
        let s = CGFloat(OfficeAppearance.spriteScale(small: a.appearance.small, zoom: Double(zoom)))
        a.body.setScale(s)
        a.label.setScale(1 / zoom)
        a.accessory?.setScale(s)
        positionAccessoryAndBubble(a)
    }

    private func place(_ actor: OfficeActor, at t: OfficeTile) {
        actor.tile = t
        actor.root.position = point(t)
        actor.root.zPosition = yDown(t) + 0.5
    }

    private func update(_ actor: OfficeActor, member m: OfficeMember, now: Date, animated: Bool) {
        let previous = actor.member
        if previous == m { return }   // değişmeyen karaktere dokunulmaz
        let old = previous.status
        actor.member = m
        let behavior = OfficeBehavior.behavior(for: m.status, atDesk: actor.seat.kind == .desk, executive: actor.isExecutive)
        if m.status.isWorking { actor.idleSince = nil } else if actor.idleSince == nil || old.isWorking { actor.idleSince = now }
        let bubbleChanged = evaluateBubble(actor, now: now)
        guard behavior != actor.behavior || old != m.status else {
            if bubbleChanged && !actor.moving { renderBubble(actor); if actor.behavior.bubble == .thinking { setBubble(actor) } }
            return
        }
        let celebrate = OfficeBehavior.celebrates(from: old, to: m.status)
        actor.behavior = behavior
        if actor.away && m.status.isWorking { sendBack(actor, animated: animated) }
        if actor.isExecutive {
            actor.strollUntil = OfficeExecutive.strollDeadline(previous: actor.strollUntil, old: old, new: m.status, animated: animated, now: now)
            moveExecutive(actor, animated: animated, now: now)
        } else if !actor.moving && !actor.away {
            applyPose(actor)
            if celebrate && animated { hop(actor) }
        }
    }

    // MARK: Yönetici alanı

    private func executiveMode(_ a: OfficeActor, now: Date = .now) -> OfficeExecutiveMode {
        let mode = OfficeExecutive.mode(status: a.member.status, strollUntil: a.strollUntil, now: now)
        // Bölge/tahta olmayan (eski/sentetik) düzenlerde yönetici hep masasında.
        switch mode {
        case .board where kit.spots.board == nil: return .seated
        case .stroll where zoneGrid == nil || kit.spots.zoneTiles.count < 2: return kit.spots.board == nil ? .seated : .board
        default: return mode
        }
    }

    /// Yönetici: çalışırken tahtanın önünde ayakta yazar (arada alt ajanlara bakar); izin beklerken ve boşa geçtikten sonra 60 sn
    /// yönetici bölgesinde volta atar; sonra masasına oturur. Yürüyüş sürerken karar yürüyüşün sonunda (`arrive`/`arriveAtBoard`/
    /// volta adımı) güncel duruma göre verilir.
    private func moveExecutive(_ a: OfficeActor, animated: Bool, now: Date) {
        guard !a.moving else { return }
        switch executiveMode(a, now: now) {
        case .board:
            endStroll(a)
            if a.atBoard { applyPose(a); startLooking(a) } else { goToBoard(a, animated: animated) }
        case .stroll:
            if a.strolling { applyPose(a) } else { beginStroll(a, animated: animated) }
        case .seated:
            let wasUp = a.upright
            endStroll(a)
            if wasUp { sendBack(a, animated: animated) } else { applyPose(a) }
        }
    }

    /// Ayakta durumlarını (tahta, volta, bakış sayacı) kapatır.
    private func leaveStanding(_ a: OfficeActor) {
        a.atBoard = false; a.toBoard = false
        a.root.removeAction(forKey: "look")
        endStroll(a)
        if a.isExecutive { updateBoardOverlay(writing: false) }
    }

    private func endStroll(_ a: OfficeActor) {
        a.strolling = false
        a.root.removeAction(forKey: "stroll")
    }

    private func goToBoard(_ a: OfficeActor, animated: Bool) {
        guard let board = kit.spots.board else { applyPose(a); return }
        endStroll(a)
        a.root.removeAction(forKey: "look")
        a.toBoard = true
        let from = a.heading ?? a.tile
        guard animated, let route = kit.grid.path(from: from, to: board) else {
            a.root.removeAction(forKey: "move"); a.moving = false
            place(a, at: board)
            arriveAtBoard(a)
            return
        }
        place(a, at: from)
        run(route: [from] + route, for: a) { [weak self] in self?.arriveAtBoard(a) }
    }

    private func arriveAtBoard(_ a: OfficeActor) {
        guard !a.leaving, actors[a.member.id] === a else { return }
        a.moving = false
        if let board = kit.spots.board { a.tile = board }
        a.direction = .up
        a.root.zPosition = yDown(a.tile) + 0.5
        a.behavior = OfficeBehavior.behavior(for: a.member.status, atDesk: false, executive: true)
        switch executiveMode(a) {
        case .board:
            a.atBoard = true
            applyPose(a)
            startLooking(a)
            notify()
        case .stroll: a.toBoard = false; beginStroll(a, animated: true)   // tahtaya varırken izin istendi / iş bitti
        case .seated: sendBack(a, animated: true)
        }
    }

    /// Tahtada yazarken ara sıra (3-5 sn) başını alt ajanlara çevirir (aşağı bakış kareleri), kısa süre sonra tahtaya döner.
    private func startLooking(_ a: OfficeActor) {
        a.root.removeAction(forKey: "look")
        guard a.atBoard, !a.leaving else { return }
        let seed = OfficeStroll.seed(for: a.member.id)
        let n = a.lookCount
        a.lookCount += 1
        let wait = a.direction == .down ? OfficeStroll.lookAwayDuration(seed: seed, n) : OfficeStroll.writeInterval(seed: seed, n)
        a.root.run(.sequence([.wait(forDuration: wait), .run { [weak self, weak a] in
            guard let self, let a, a.atBoard, !a.moving, !a.leaving else { return }
            a.direction = a.direction == .down ? .up : .down
            self.applyPose(a)
            self.startLooking(a)
        }]), withKey: "look")
    }

    // MARK: Volta

    /// Voltaya başlar: yönetici bölgesinde (üst orta şerit) sağa-sola 4-6 karelik yürüyüş + kısa duraklamalar. Animasyonsuz
    /// uygulamada doğrudan bir volta karesinde belirir (döngü yine başlar).
    private func beginStroll(_ a: OfficeActor, animated: Bool) {
        guard zoneGrid != nil else { applyPose(a); return }
        a.root.removeAction(forKey: "look")
        a.atBoard = false; a.toBoard = false
        updateBoardOverlay(writing: false)
        a.strolling = true
        a.behavior = OfficeBehavior.behavior(for: a.member.status, atDesk: false, executive: true)
        if animated {
            strollStep(a)
        } else {
            a.root.removeAction(forKey: "move"); a.moving = false
            let seed = OfficeStroll.seed(for: a.member.id)
            place(a, at: OfficeStroll.target(from: a.tile, zone: kit.spots.zoneTiles, seed: seed, step: a.strollCount) ?? a.tile)
            strollPause(a)
        }
        notify()
    }

    /// Bir volta adımı: modu yeniden değerlendirir (boşta 60 sn dolduysa masaya, çalışmaya başladıysa tahtaya), yoksa yeni hedefe yürür.
    private func strollStep(_ a: OfficeActor) {
        guard a.strolling, !a.leaving, actors[a.member.id] === a else { return }
        guard executiveMode(a) == .stroll, let grid = zoneGrid else {
            moveExecutive(a, animated: true, now: .now)
            return
        }
        let seed = OfficeStroll.seed(for: a.member.id)
        a.strollCount += 1
        let from = a.heading ?? a.tile
        guard let goal = OfficeStroll.target(from: from, zone: kit.spots.zoneTiles, seed: seed, step: a.strollCount),
              let route = grid.path(from: from, to: goal), !route.isEmpty else { strollPause(a); return }
        place(a, at: from)
        a.root.zPosition = yDown(from) + 0.5
        run(route: [from] + route, for: a) { [weak self] in self?.strollPause(a) }
        if a.behavior.bubble == .alert { setBubble(a); positionAccessoryAndBubble(a) }   // izin "!" balonu yürürken de görünür
    }

    private func strollPause(_ a: OfficeActor) {
        guard a.strolling, !a.leaving, actors[a.member.id] === a else { return }
        a.moving = false
        if let t = a.heading { a.tile = t }
        a.heading = nil
        a.root.zPosition = yDown(a.tile) + 0.5
        a.direction = .down   // duraklarken alt ajanlara bakar
        a.behavior = OfficeBehavior.behavior(for: a.member.status, atDesk: false, executive: true)
        applyPose(a)
        let seed = OfficeStroll.seed(for: a.member.id)
        a.root.run(.sequence([.wait(forDuration: OfficeStroll.pause(seed: seed, step: a.strollCount)), .run { [weak self, weak a] in
            guard let self, let a else { return }
            self.strollStep(a)
        }]), withKey: "stroll")
    }

    /// Tahta katmanı: yönetici tahtada yazıyorsa 3 kareli animasyon, değilse gizli (animasyon yok).
    private func setBoardWriting(_ a: OfficeActor) {
        guard a.isExecutive else { return }
        updateBoardOverlay(writing: a.atBoard && a.behavior.pose == .typing && !a.leaving)
    }

    private func updateBoardOverlay(writing: Bool) {
        guard let index = kit.spots.boardIndex else { return }
        if writing {
            if boardOverlay == nil {
                let frames = assets.boardFrames(theme: theme)
                guard let first = frames.first else { return }
                let node = SKSpriteNode(texture: first)
                node.anchorPoint = .zero
                node.size = OfficePixelArt.boardWriteSize
                let f = kit.layout.furniture[index], b = kit.bounds
                let origin = OfficePixelArt.boardWriteOrigin
                node.position = CGPoint(x: CGFloat((f.col - b.minCol) * 16) + origin.x,
                                        y: CGFloat(kit.worldHeight) - (CGFloat((f.row - b.minRow) * 16) + origin.y + OfficePixelArt.boardWriteSize.height))
                node.zPosition = 0.3
                content.addChild(node)
                boardOverlay = node
            }
            guard let node = boardOverlay else { return }
            node.isHidden = false
            if node.action(forKey: "write") == nil {
                node.run(.repeatForever(.animate(with: assets.boardFrames(theme: theme), timePerFrame: 0.5, resize: false, restore: false)), withKey: "write")
            }
        } else if let node = boardOverlay {
            node.removeAction(forKey: "write")
            node.isHidden = true
        }
    }

    // MARK: Konuşma balonu

    /// Ajanın balon metnini ve süre sayacını günceller (düğüme dokunmaz); metin/süre durumu değiştiyse true.
    /// Balon yalnızca çalışırken (düşünüyor/araç) vardır; 10 sn olay gelmezse söner. İzin bekleme "!" balonu bundan ayrıdır.
    @discardableResult
    private func evaluateBubble(_ a: OfficeActor, now: Date) -> Bool {
        let m = a.member
        let expired = OfficeBubbleText.isExpired(activityAt: m.activityAt, now: now)
        let text = expired ? nil : OfficeBubbleText.text(status: m.status, activity: m.activity, target: m.target)
        let changed = text != a.bubbleText || expired != a.bubbleExpired
        a.bubbleText = text
        a.bubbleExpired = expired
        if text != nil, let remaining = OfficeBubbleText.remaining(activityAt: m.activityAt, now: now) {
            if !a.bubbleTimer || a.bubbleActivityAt != m.activityAt {
                a.bubbleActivityAt = m.activityAt
                a.bubbleTimer = true
                a.body.run(.sequence([.wait(forDuration: remaining), .run { [weak self, weak a] in
                    guard let self, let a else { return }
                    self.expireBubble(a)
                }]), withKey: "bubbleExpiry")
            }
        } else if a.bubbleTimer {
            a.body.removeAction(forKey: "bubbleExpiry")
            a.bubbleTimer = false
        }
        return changed
    }

    private func expireBubble(_ a: OfficeActor) {
        a.bubbleTimer = false
        a.bubbleExpired = true
        a.bubbleText = nil
        renderBubble(a)
        if !a.moving && !a.away && !a.leaving { setBubble(a) }
        notify()
    }

    /// Metin balonunu düğüme uygular: yalnızca seviye ≥ 2 yakınlıkta, karakter yerinde (yürümüyor) ve metin varsa görünür.
    private func renderBubble(_ a: OfficeActor, reposition: Bool = true) {
        guard let text = a.bubbleText, bubblesOn, isVisible, !a.moving, !a.away, !a.leaving else {
            if let tb = a.textBubble, !tb.node.isHidden { tb.node.isHidden = true; resolveOverlays() }
            return
        }
        let tb: OfficeTextBubble
        if let existing = a.textBubble { tb = existing } else {
            tb = OfficeTextBubble(theme: theme)
            tb.node.zPosition = 5_500
            a.root.addChild(tb.node)
            a.textBubble = tb
        }
        if tb.text != text {
            let wasShown = !tb.node.isHidden && !tb.text.isEmpty
            tb.setText(text, assets: assets)
            if wasShown {
                tb.node.removeAction(forKey: "fade")
                tb.node.alpha = 0.3
                tb.node.run(.fadeAlpha(to: 1, duration: 0.15), withKey: "fade")
            } else {
                tb.node.alpha = 1
            }
        }
        if tb.node.isHidden { tb.node.isHidden = false }
        if reposition { positionAccessoryAndBubble(a) }
    }

    // MARK: Poz

    /// Oturma/ayakta pozunu ve ek öğeleri (balon, PC ekranı) mevcut davranışa göre kurar.
    private func applyPose(_ a: OfficeActor) {
        stopIdle(a)
        a.body.removeAction(forKey: "pose")
        var frames: [Int]
        switch a.behavior.pose {
        case .typing: frames = [OfficeCharacterSheet.frameIndex(.typing(0)), OfficeCharacterSheet.frameIndex(.typing(1))]
        case .reading: frames = [OfficeCharacterSheet.frameIndex(.reading(0)), OfficeCharacterSheet.frameIndex(.reading(1))]
        case .sitting: frames = [OfficeCharacterSheet.frameIndex(.stand)]
        }
        if theme == .vector {
            // Vektör ek pozlar: izin beklerken el kaldırma (9-10); tahtada yazarken kol yukarı yazma (7-8; aşağı bakarken ayakta).
            if a.behavior.bubble == .alert { frames = [9, 10] }
            else if a.atBoard && a.behavior.pose == .typing { frames = a.direction == .up ? [7, 8] : [OfficeCharacterSheet.frameIndex(.stand)] }
        }
        let tex = frames.map { self.tex(a, a.direction, $0) }
        a.body.xScale = (OfficeCharacterSheet.mirrorsHorizontally(a.direction) ? -1 : 1) * abs(a.body.xScale)
        a.body.texture = tex[0]
        a.body.position.y = a.upright ? 0 : -Self.sitDrop   // tahtada/voltada ayakta (oturma çökmesi yok)
        if a.behavior.pose != .sitting && tex.count > 1 {
            // Okuma (izin bekleme) yavaş, yazma hızlı.
            let t = a.behavior.pose == .typing ? 0.28 : 0.6
            a.body.run(.repeatForever(.animate(with: tex, timePerFrame: t, resize: false, restore: false)), withKey: "pose")
        }
        setBubble(a)
        setPC(a)
        setBoardWriting(a)
        renderBubble(a, reposition: false)
        positionAccessoryAndBubble(a)
        notify()
    }

    private func setBubble(_ a: OfficeActor) {
        a.bubble?.removeFromParent()
        a.bubble = nil
        guard let kind = a.behavior.bubble, let tex = assets.bubbleTexture(kind, theme: theme) else { return }
        // Yakınken "…" yerine "Düşünüyor…" metin balonu; 10 sn olay yoksa hiçbir düşünme balonu kalmaz.
        if kind == .thinking && (bubblesOn || a.bubbleExpired) { return }
        let node = SKSpriteNode(texture: tex)
        if theme == .vector, let size = OfficeVectorUI.overlaySize(kind == .alert ? "bubble_alert" : "bubble_think") { node.size = size }
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
        if let c = pcComputer[pc], let f = assets.computerFrames(c, theme: theme) {
            if a.behavior.pcOn, !f.on.isEmpty {
                node.run(.repeatForever(.animate(with: f.on, timePerFrame: 0.45, resize: false, restore: false)), withKey: "screen")
            } else {
                node.texture = f.off
            }
        }
        updateScreenGlow(pc, on: a.behavior.pcOn)
    }

    /// Aksesuar baş üstünde, balon sağ üstte; oturma pozunda baş birkaç piksel aşağıdadır (ayakta/yürürken değil).
    private func positionAccessoryAndBubble(_ a: OfficeActor) {
        let s = a.body.yScale
        let headTop = headTop(a)
        if let acc = a.accessory {
            acc.position = CGPoint(x: 0, y: headTop - 1)
            acc.xScale = s; acc.yScale = s
        }
        a.bubble?.position = CGPoint(x: 7 * s, y: headTop - 8 * s)
        placeRoleAccessory(a)
        a.label.position = CGPoint(x: 0, y: labelY(a))
        if let tb = a.textBubble, !tb.node.isHidden {
            tb.node.setScale(1 / zoom)
            tb.setFlipped(a.root.position.x > CGFloat(kit.worldWidth) / 2)
        }
        resolveOverlays()
    }

    /// Baş üstü (root'a göre): oturma ve ayakta okuma pozlarında baş birkaç piksel aşağıdadır.
    private func headTop(_ a: OfficeActor) -> CGFloat {
        let still = !a.moving && !a.hopping && !a.away
        let low = still && (!a.upright || a.behavior.pose == .reading)
        return (low ? 28 : 30) * a.body.yScale + a.body.position.y
    }

    /// Ad etiketinin (varsa) y konumu: baş + aksesuar üstü. Yan yana oturan salon koltuklarında (kanepe) tek sütundakini bir kademe yukarı al.
    private func labelY(_ a: OfficeActor) -> CGFloat {
        labelBaseY(a) + CGFloat(a.labelLevel) * OfficeLabelLayout.step / zoom
    }

    private func labelBaseY(_ a: OfficeActor) -> CGFloat {
        let s = a.body.yScale
        let top = headTop(a) + (a.accessory?.size.height ?? 0) * s + 3
        let stagger: CGFloat = a.seat.kind == .lounge && a.seat.tile.col % 2 != 0 ? 14 / zoom : 0
        return top + stagger
    }

    /// Etiketler (vektör) önce, balonlar sonra: balon etiket kademesini de hesaba katar.
    private func resolveOverlays() {
        resolveLabelOverlaps()
        resolveBubbleOverlaps()
    }

    /// Vektör etiketleri: yalnızca üye/konum/genişlik/zoom değişince yeniden hesaplanır (`OfficeLabelLayout`).
    private func resolveLabelOverlaps() {
        guard theme == .vector else { return }
        var items: [OfficeLabelItem] = []
        for a in actors.values where a.labelBuilt && !a.labelWidths.isEmpty && !a.label.isHidden {
            if a.moving || a.hopping || a.leaving { continue }
            items.append(OfficeLabelItem(id: a.member.id, x: a.root.position.x, y: a.root.position.y + labelBaseY(a), widths: a.labelWidths))
        }
        items.sort { $0.id < $1.id }
        guard items != lastLabelItems || zoom != lastLabelZoom else { return }
        lastLabelItems = items; lastLabelZoom = zoom
        let result = OfficeLabelLayout.resolve(items, zoom: zoom).placements
        for item in items {
            guard let a = actors[item.id], let p = result[item.id] else { continue }
            if a.labelVariant != p.variant { applyLabelVariant(a, p.variant) }
            a.labelLevel = p.level
            a.label.position = CGPoint(x: 0, y: labelY(a))
        }
    }

    /// Metin balonlarını yerleştirir: etiketin (varsa) üstünde; komşu balonla çakışan balon dikeyde yukarı kayar (balon boyu kadar),
    /// çakışma kalmayana dek. Soldan sağa sırayla yerleştirilir (sol balon sabit, sağdaki kayar).
    private func resolveBubbleOverlaps() {
        let z = zoom
        var placed: [(rect: CGRect, owner: String?)] = []
        if theme == .vector {
            // Etiketler engeldir (kendi etiketi hariç): balon komşunun etiketine binmez.
            for a in actors.values where a.labelBuilt && !a.label.isHidden {
                let w = (a.labelWidths.indices.contains(a.labelVariant) ? a.labelWidths[a.labelVariant] : 0) + OfficeLabelLayout.margin
                placed.append((CGRect(x: a.root.position.x - w / 2 / z, y: a.root.position.y + labelY(a), width: w / z, height: OfficeLabelLayout.height / z), a.member.id))
            }
        }
        let shown = actors.values.filter { a in a.textBubble.map { !$0.node.isHidden } ?? false }
            .sorted { ($0.root.position.x, $0.root.position.y) < ($1.root.position.x, $1.root.position.y) }
        for a in shown {
            guard let tb = a.textBubble else { continue }
            let tail = tb.tailX / z
            let step = (tb.height + 1) / z
            let labelSpace: CGFloat = a.labelBuilt && !a.label.isHidden ? 16 / z : 1 / z
            let base = labelY(a) + labelSpace
            let w = tb.width / z, x = a.root.position.x
            let minX = tb.flipped ? x + tail - w : x - tail
            var lift: CGFloat = 0
            for _ in 0..<8 {
                let rect = CGRect(x: minX, y: a.root.position.y + base + lift, width: w, height: tb.height / z).insetBy(dx: -1 / z, dy: -0.5 / z)
                if placed.contains(where: { $0.owner != a.member.id && $0.rect.intersects(rect) }) { lift += step } else { break }
            }
            tb.node.position = CGPoint(x: 0, y: base + lift)
            placed.append((CGRect(x: minX, y: a.root.position.y + base + lift, width: w, height: tb.height / z), nil))
        }
    }

    private func buildAccessory(_ a: OfficeActor) {
        guard theme == .pixel else { return }   // vektör: model/rol aksesuarı karaktere pişirilmiş (ek düğüm yok)
        if let role = a.appearance.role, a.roleAccessory == nil, let name = OfficeArt.roleAccessoryName(role.accessory), let tex = assets.artTexture(name) {
            let n = SKSpriteNode(texture: tex)
            n.size = tex.size()
            n.zPosition = 11
            a.root.addChild(n)
            a.roleAccessory = n
            placeRoleAccessory(a)
        }
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
    private func run(route: [OfficeTile], for a: OfficeActor, onStep: (@MainActor (OfficeTile) -> Void)? = nil, completion: @escaping @MainActor () -> Void) {
        stopIdle(a)
        a.root.removeAction(forKey: "move")
        a.body.removeAction(forKey: "pose")
        a.bubble?.removeFromParent(); a.bubble = nil
        a.textBubble?.node.isHidden = true
        a.body.position.y = 0
        var actions: [SKAction] = []
        for (from, to) in zip(route, route.dropFirst()) {
            let dir = direction(from: from, to: to)
            let base = theme == .vector && a.carryingBox ? 15 : 0
            let walk = (0..<4).map { tex(a, dir, base + OfficeCharacterSheet.frameIndex(.walk($0))) }
            let z = max(yDown(from), yDown(to)) + 0.5
            actions.append(.run { [weak a, weak self] in
                guard let a else { return }
                self?.placeRoleAccessory(a)
                onStep?(from)
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

    private func arrive(_ a: OfficeActor, animated: Bool = true) {
        guard !a.leaving, actors[a.member.id] === a else { return }
        a.moving = false
        a.direction = a.seat.facing
        a.tile = a.seat.tile
        a.root.zPosition = yDown(a.seat.tile) + 0.5
        a.behavior = OfficeBehavior.behavior(for: a.member.status, atDesk: a.seat.kind == .desk, executive: a.isExecutive)
        a.away = false
        a.atBoard = false; a.toBoard = false
        endStroll(a)
        if let s = a.awaySeatID { awayLounge.remove(s); a.awaySeatID = nil }
        if a.isExecutive {
            switch executiveMode(a) {
            case .board: goToBoard(a, animated: animated); return   // çalışırken tahta önünde ayakta
            case .stroll: beginStroll(a, animated: animated); return
            case .seated: break
            }
        }
        applyPose(a)
        notify()
    }

    private func depart(_ id: String, animated: Bool) {
        guard let a = actors.removeValue(forKey: id) else { return }
        if let pc = a.seat.pcIndex, pcOccupied[pc] == id {
            pcOccupied[pc] = nil
            pcNodes[pc]?.removeAction(forKey: "screen")
            if let c = pcComputer[pc], let f = assets.computerFrames(c, theme: theme) { pcNodes[pc]?.texture = f.off }
            updateScreenGlow(pc, on: false)
        }
        if let s = a.awaySeatID { awayLounge.remove(s); a.awaySeatID = nil }
        a.leaving = true
        a.away = true
        leaveStanding(a)
        a.body.removeAction(forKey: "bubbleExpiry"); a.bubbleTimer = false; a.bubbleText = nil
        a.textBubble?.node.isHidden = true
        a.bubble?.removeFromParent(); a.bubble = nil
        a.label.isHidden = true
        resolveOverlays()
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
        // Her odada kahve makinesi var; salon koltukları ajan koltuğu/dinlenme yeri değildir (ofis v3).
        if let coffee = kit.spots.coffee { return (coffee, kit.spots.coffeeFacing, nil) }
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
            a.body.texture = self.tex(a, a.direction, 1)
            a.body.xScale = (OfficeCharacterSheet.mirrorsHorizontally(a.direction) ? -1 : 1) * abs(a.body.xScale)
            if target.seatID != nil { a.body.position.y = -Self.sitDrop }
            a.idleCount += 1
            a.root.run(.sequence([.wait(forDuration: OfficeIdle.stay(seed: a.member.id, n: a.idleCount)), .run { [weak self, weak a] in
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
        leaveStanding(a)
        let from = a.heading ?? a.tile
        guard animated, let route = kit.grid.path(from: from, to: a.seat.tile) else {
            a.root.removeAction(forKey: "move"); a.root.removeAction(forKey: "coffee"); a.moving = false
            place(a, at: a.seat.tile); arrive(a, animated: animated); return
        }
        place(a, at: from)
        run(route: [from] + route, for: a) { [weak self] in self?.arrive(a) }
    }

    // MARK: Ofis v3 — bilgisayar + rol aksesuarı

    private func configureComputer(_ node: SKSpriteNode, pc i: Int) {
        let seat = kit.spots.seats.first { $0.pcIndex == i }
        let c: OfficeComputer = seat.map { $0.kind == .executive ? OfficeComputer.executive : OfficeComputer.pick(roomID: id, seatID: Self.seatKey($0)) }
            ?? OfficeComputer.pick(roomID: id, seatID: 10_000 + i)
        pcComputer[i] = c
        node.size = CGSize(width: 16, height: 32)
        if let f = assets.computerFrames(c, theme: theme) { node.texture = f.off }
        pcNodes[i] = node
    }

    /// Koltuğun kademeden bağımsız anahtarı (bilgisayar türü seçimi): satır * 100 + sütun.
    static func seatKey(_ s: OfficeSeat) -> Int { s.tile.row * 100 + s.tile.col }

    func computer(forPC i: Int) -> OfficeComputer? { pcComputer[i] }

    /// Rol aksesuarı konumu: yüz/baş/gövde/el. Arkaya bakarken yüz ve gövde aksesuarları gizlenir.
    private func placeRoleAccessory(_ a: OfficeActor) {
        guard let node = a.roleAccessory, let role = a.appearance.role else { return }
        let s = abs(a.body.yScale), by = a.body.position.y
        let front = a.direction != .up
        let handX: CGFloat = (a.direction == .left ? -7 : 7) * s
        switch role.accessory {
        case .glasses: node.isHidden = !front; node.position = CGPoint(x: 0, y: by + 23 * s)
        case .headphones: node.isHidden = false; node.position = CGPoint(x: 0, y: by + 25 * s)
        case .hood: node.isHidden = !front; node.position = CGPoint(x: 0, y: by + 17 * s)
        case .vest: node.isHidden = !front; node.position = CGPoint(x: 0, y: by + 11 * s)
        case .tie: node.isHidden = !front; node.position = CGPoint(x: 0, y: by + 11 * s)
        case .tag: node.isHidden = !front; node.position = CGPoint(x: 4 * s, y: by + 9 * s)
        case .none, .binoculars, .book, .magnifier, .compass, .clipboard, .ruler: node.isHidden = false; node.position = CGPoint(x: handX, y: by + 10 * s)
        }
        node.setScale(s)
    }

    // MARK: Ofis v3 — gece ışığı

    func setNight(_ on: Bool, animated: Bool) {
        nightWanted = on
        restyleChrome()
        if theme == .vector { for a in actors.values { nightLift(a) }; for a in leavingActors { nightLift(a) } }
        if on { buildNightIfNeeded() }
        guard let root = nightRoot else { return }
        let target: CGFloat = on ? 1 : 0
        for node in [root] + (nightWindows.map { [$0] } ?? []) {
            node.removeAction(forKey: "fade")
            if animated && isVisible {
                node.isHidden = false
                node.run(.sequence([.fadeAlpha(to: target, duration: OfficeLighting.crossfade), .run { [weak node] in node?.isHidden = target == 0 }]), withKey: "fade")
            } else {
                node.alpha = target
                node.isHidden = target == 0 || !isVisible
            }
        }
        for a in actors.values { if let pc = a.seat.pcIndex, pcOccupied[pc] == a.member.id { updateScreenGlow(pc, on: a.behavior.pcOn) } }
    }

    /// Gece katmanı: hafif lacivert multiply örtü, tavan lambası (geniş sıcak ışık), her masada lamba + ışık havuzu, tahta lambası.
    /// Vektör temada ayrıca parlak gece pencereleri ve zemine mavi ay ışığı vurgusu. Statik sprite'lar (animasyon yok); oda görünmezken gizli.
    private func buildNightIfNeeded() {
        guard nightRoot == nil, isVisible else { return }
        let w = CGFloat(kit.worldWidth), h = CGFloat(kit.worldHeight), b = kit.bounds
        let lp = theme.lighting
        let vec = theme == .vector
        let root = SKNode()
        root.zPosition = 4000
        root.alpha = 0
        root.isHidden = true
        let dim = SKSpriteNode(color: SKColor(red: lp.multiplyColor[0], green: lp.multiplyColor[1], blue: lp.multiplyColor[2], alpha: 1), size: CGSize(width: w, height: h))
        dim.anchorPoint = .zero
        dim.alpha = CGFloat(lp.multiplyNodeAlpha)
        dim.blendMode = .multiply
        root.addChild(dim)
        if lp.hasWash {
            let wash = SKSpriteNode(color: SKColor(red: lp.overlayRGB[0], green: lp.overlayRGB[1], blue: lp.overlayRGB[2], alpha: 1), size: CGSize(width: w, height: h))
            wash.anchorPoint = .zero
            wash.alpha = CGFloat(lp.overlayAlpha)
            wash.zPosition = 0.5
            root.addChild(wash)
        }
        func glow(_ name: String, size: CGSize, at p: CGPoint, alpha: CGFloat) {
            guard let t = assets.artTexture(vec ? "v" + name : name, theme: theme) else { return }
            let g = SKSpriteNode(texture: t, size: size)
            g.position = p; g.blendMode = .add; g.alpha = alpha; g.zPosition = 1
            root.addChild(g)
        }
        func sprite(_ name: String, at p: CGPoint) {
            guard let t = assets.artTexture(name, theme: theme) else { return }
            let n = SKSpriteNode(texture: t, size: vec ? (OfficeVectorArt.artSize(name) ?? t.size()) : t.size())
            n.anchorPoint = CGPoint(x: 0.5, y: 0)
            n.position = p; n.zPosition = 2
            root.addChild(n)
        }
        glow("glow_bulb", size: CGSize(width: w * 1.3, height: h * 1.15), at: CGPoint(x: w / 2, y: h * 0.55), alpha: CGFloat(lp.bulbAlpha))
        for (_, f, a) in kit.dynamicFurniture where a.id == "DESK_FRONT" || a.id == "SMALL_TABLE_FRONT" {
            let x = CGFloat((f.col - b.minCol) * 16) + (a.id == "DESK_FRONT" ? 24 : 16)
            let y = h - CGFloat((f.row - b.minRow) * 16) - 14
            glow("glow_pool", size: CGSize(width: 64, height: 36), at: CGPoint(x: x, y: y - 3), alpha: CGFloat(lp.poolAlpha))
            sprite("lamp", at: CGPoint(x: x, y: y - 1))
        }
        for f in kit.layout.furniture where f.assetID == "WHITEBOARD" {
            glow("glow_pool", size: CGSize(width: 60, height: 36), at: CGPoint(x: CGFloat((f.col - b.minCol) * 16 + 16), y: h - CGFloat((f.row - b.minRow) * 16 + 14)), alpha: CGFloat(lp.boardAlpha))
        }
        if vec, let tex = assets.windowTexture(night: true) {
            let back = SKNode()
            back.zPosition = 0.05
            back.alpha = 0
            back.isHidden = true
            for r in OfficeVectorArt.windowRects(layout: kit.layout, catalog: assets.catalog) {
                let x = r.midX - CGFloat(b.minCol * 16), y = h - (r.midY - CGFloat(b.minRow * 16))
                let n = SKSpriteNode(texture: tex, size: r.size)
                n.position = CGPoint(x: x, y: y)
                back.addChild(n)
                glow("glow_moon", size: CGSize(width: 26, height: 44), at: CGPoint(x: x, y: y - 22), alpha: CGFloat(lp.windowAlpha))
            }
            content.addChild(back)
            nightWindows = back
        }
        content.addChild(root)
        nightRoot = root
    }

    /// PC ekranı parıltısı (gece, yalnızca ekran açıkken).
    private func updateScreenGlow(_ pc: Int, on: Bool) {
        guard let root = nightRoot else { return }
        if !on { screenGlows[pc]?.isHidden = true; return }
        if screenGlows[pc] == nil, let t = assets.artTexture(theme == .vector ? "vglow_screen" : "glow_screen", theme: theme), pc < kit.layout.furniture.count {
            let f = kit.layout.furniture[pc], b = kit.bounds
            let g = SKSpriteNode(texture: t, size: CGSize(width: 30, height: 20))
            g.position = CGPoint(x: CGFloat((f.col - b.minCol) * 16 + 8), y: CGFloat(kit.worldHeight) - CGFloat((f.row - b.minRow) * 16 + 6))
            g.blendMode = .add; g.zPosition = 3; g.alpha = CGFloat(theme.lighting.screenAlpha)
            root.addChild(g)
            screenGlows[pc] = g
        }
        screenGlows[pc]?.isHidden = false
    }

    // MARK: Ofis v3 — boşta varyantları

    var variantCount: Int { actors.values.filter { $0.idleVariant != nil }.count }
    var walkerCount: Int { actors.values.filter { $0.away || $0.moving }.count }

    /// Masada boşta oturan, şu an hiçbir şey yapmayan karakterler (varyant adayları), kimliğe göre sıralı.
    func idleCandidates() -> [OfficeActor] {
        actors.values.filter { $0.behavior.pose == .sitting && !$0.isExecutive && $0.seat.kind == .desk && !$0.moving && !$0.away && !$0.leaving && !$0.hopping && $0.idleVariant == nil }
            .sorted { $0.member.id < $1.member.id }
    }

    /// Bir boşta varyantı oynatır (sonlu SKAction; bitince normal poza döner). Okuma / kahve / esneme / zzz.
    @discardableResult
    func startIdleVariant(id: String) -> OfficeIdleVariant? {
        guard isVisible, let a = actors[id], a.idleVariant == nil, !a.moving, !a.away, !a.leaving else { return nil }
        let v = OfficeIdle.variant(seed: a.member.id, n: a.idleCount)
        let len = OfficeIdle.length(seed: a.member.id, n: a.idleCount)
        a.idleCount += 1
        a.idleVariant = v
        let s = abs(a.body.yScale)
        let vec = theme == .vector
        func tex(_ pose: OfficeCharacterSheet.Pose) -> SKTexture { self.tex(a, a.direction, OfficeCharacterSheet.frameIndex(pose)) }
        func extra(_ frame: Int) -> SKTexture { self.tex(a, a.direction, frame) }
        func overlay(_ name: String, x: CGFloat, y: CGFloat) -> SKSpriteNode? {
            guard let t = assets.artTexture(name, theme: theme) else { return nil }
            let n = SKSpriteNode(texture: t, size: vec ? (OfficeVectorArt.artSize(name) ?? t.size()) : t.size())
            n.position = CGPoint(x: x * s, y: y * s); n.setScale(s); n.zPosition = 12
            a.root.addChild(n)
            a.idleOverlay = n
            return n
        }
        switch v {
        case .read:
            a.body.run(.repeatForever(.animate(with: [tex(.reading(0)), tex(.reading(1))], timePerFrame: 0.7, resize: false, restore: false)), withKey: "idle")
        case .coffee where vec:
            // Vektör: fincan eldedir (13) ve ağıza kalkar (14); ayrı fincan düğümü yok.
            a.body.run(.repeatForever(.sequence([.setTexture(extra(13), resize: false), .wait(forDuration: 1.4), .setTexture(extra(14), resize: false), .wait(forDuration: 0.9)])), withKey: "idle")
        case .coffee:
            if let cup = overlay("cup", x: 6, y: 8 + a.body.position.y) {
                cup.run(.repeatForever(.sequence([.wait(forDuration: 1.4), .moveBy(x: 0, y: 3 * s, duration: 0.4), .wait(forDuration: 0.5), .moveBy(x: 0, y: -3 * s, duration: 0.4)])))
            }
        case .yawn:
            a.body.run(.repeatForever(.sequence([.animate(with: [vec ? extra(11) : tex(.reading(0))], timePerFrame: 0.3, resize: false, restore: false), .moveBy(x: 0, y: 1.5, duration: 0.12),
                                                 .moveBy(x: 0, y: -1.5, duration: 0.12), .animate(with: [tex(.stand)], timePerFrame: 0.3, resize: false, restore: false), .wait(forDuration: 1.2)])), withKey: "idle")
        case .zzz:
            if vec { a.body.texture = extra(12) }
            if let z = overlay("zzz", x: 8, y: headTop(a) / max(s, 0.01) - 2) {
                z.run(.repeatForever(.sequence([.moveBy(x: 0, y: 2, duration: 0.9), .moveBy(x: 0, y: -2, duration: 0.9)])))
            }
        }
        a.root.run(.sequence([.wait(forDuration: len), .run { [weak self, weak a] in
            guard let self, let a, a.idleVariant != nil else { return }
            self.applyPose(a)
        }]), withKey: "idleEnd")
        notify()
        return v
    }

    private func stopIdle(_ a: OfficeActor) {
        guard a.idleVariant != nil || a.idleOverlay != nil else { return }
        a.idleVariant = nil
        a.root.removeAction(forKey: "idleEnd")
        a.body.removeAction(forKey: "idle")
        a.idleOverlay?.removeFromParent()
        a.idleOverlay = nil
        a.body.position.y = a.upright ? 0 : -Self.sitDrop
    }

    // MARK: Ofis v3 — temizlikçi + taşıyıcı (yardımcı karakterler)

    /// Roller dışı yardımcı karakter (planlayıcıya girmez): `leavingActors` listesinde izlenir (ölçek/animasyon durumu).
    private func makeProp(label: String, tint: OfficeRGB, blend: Double, prop: OfficeVectorCharacter.Prop = .none) -> OfficeActor {
        let member = OfficeMember(id: "__\(label)__", parentID: nil, kind: .subagent, label: label, badge: .unknown, status: .tool(label), groupIndex: 0)
        var look = OfficeAppearance(characterIndex: 1, tint: tint, tintBlend: blend, accessory: .none, small: false, badgeText: "")
        look.prop = prop
        let seat = kit.spots.seats.first ?? OfficeSeat(id: -1, tile: kit.spots.entrance, facing: .down, kind: .desk, pcIndex: nil)
        let a = OfficeActor(member: member, appearance: look, seat: seat, texture: assets.characterTexture(for: look, direction: .left, frame: 1, theme: theme, night: nightWanted), theme: theme)
        nightLift(a)
        a.leaving = true
        a.root.position = point(kit.spots.door)
        a.root.zPosition = yDown(kit.spots.door) + 0.5
        a.root.alpha = 0
        content.addChild(a.root)
        leavingActors.append(a)
        applyScale(a)
        a.root.run(.fadeIn(withDuration: 0.25))
        return a
    }

    private func dismissProp(_ a: OfficeActor, completion: @escaping @MainActor () -> Void) {
        a.root.run(.fadeOut(withDuration: 0.25)) {
            MainActor.assumeIsolated {
                a.root.removeFromParent()
                self.leavingActors.removeAll { $0 === a }
                completion()
                self.notify()
            }
        }
    }

    /// Temizlikçi zamanlayıcısı (saf kural: `OfficeCleaner.shouldStart`). Başladıysa true.
    @discardableResult
    func cleanerTick(now: Date, scenePaused: Bool = false) -> Bool {
        guard !isPlaceholder, memberCount > 0 else { return false }
        if cleanerDueAt == nil { cleanerDueAt = now.addingTimeInterval(OfficeCleaner.delay(seed: id, n: cleanerRuns)); return false }
        guard OfficeCleaner.shouldStart(now: now, dueAt: cleanerDueAt, roomVisible: isVisible, scenePaused: scenePaused, busy: cleaning || carrying) else { return false }
        return startCleaner(now: now)
    }

    @discardableResult
    func startCleaner(now: Date) -> Bool {
        let spots = kit.spots
        let route = OfficeCleaner.route(grid: kit.grid, entrance: spots.entrance, laneRows: OfficeRoomTemplates.laneRows(stations: tier.stations))
        cleanerRuns += 1
        cleanerDueAt = now.addingTimeInterval(OfficeCleaner.delay(seed: id, n: cleanerRuns))
        guard route.count > 3, !cleaning else { return false }
        cleaning = true
        let a = makeProp(label: "temizlikçi", tint: OfficeRGB(r: 0.15, g: 0.45, b: 0.98), blend: 0.6, prop: .cleaner)
        if let t = assets.artTexture("mop", theme: theme) {
            let mop = SKSpriteNode(texture: t, size: theme == .vector ? (OfficeVectorArt.artSize("mop") ?? t.size()) : t.size())
            mop.anchorPoint = CGPoint(x: 0.5, y: 0)
            mop.position = CGPoint(x: theme == .vector ? 7 : 8, y: 1)
            mop.zPosition = 11
            mop.run(.repeatForever(.sequence([.rotate(toAngle: 0.18, duration: 0.25), .rotate(toAngle: -0.18, duration: 0.25)])))
            a.root.addChild(mop)
        }
        var steps = [spots.door] + route
        steps.append(spots.door)
        run(route: steps, for: a, onStep: { [weak self] tile in self?.addTrail(at: tile) }) { [weak self] in
            self?.dismissProp(a) { self?.cleaning = false }
        }
        notify()
        return true
    }

    /// Yürünen karoda kısa süre parlayan açık şerit.
    private func addTrail(at t: OfficeTile) {
        let n = SKSpriteNode(color: SKColor(red: 0.8, green: 0.97, blue: 1, alpha: 1), size: CGSize(width: 14, height: 7))
        n.alpha = 0.5
        n.blendMode = .add
        n.position = CGPoint(x: point(t).x, y: point(t).y + 3)
        n.zPosition = 0.5
        content.addChild(n)
        n.run(.sequence([.fadeOut(withDuration: 3.2), .removeFromParent()]))
    }

    /// Büyüme: yeni masa bloğunu gizle, taşıyıcı kapıdan masayı getirip bırakır (0.4 sn düşme), bilgisayar belirir, çıkar; sonra
    /// bekleyen yeni ajan yürüyüp oturur.
    private func startCarrier(for seat: OfficeSeat) {
        let bc = 1 + 4 * ((seat.tile.col - 1) / 4), br = seat.tile.row - 2
        var parts: [(node: SKNode, isDesk: Bool)] = []
        for (i, f, a) in kit.dynamicFurniture where f.row == br && ((f.col == bc && (a.id == "DESK_FRONT" || a.id == "PC_FRONT_OFF")) || (f.col == bc + 2 && a.id == "PC_FRONT_OFF")) {
            if let n = furnitureNodes[i] { parts.append((n, a.id == "DESK_FRONT")) }
        }
        let spots = kit.spots
        let target = OfficeTile(bc + 1, br + 2)
        guard !parts.isEmpty, let there = kit.grid.path(from: spots.entrance, to: target), let back = kit.grid.path(from: target, to: spots.entrance) else {
            finishCarrier(); return
        }
        carrying = true
        for p in parts { p.node.alpha = 0 }
        let a = makeProp(label: "taşıyıcı", tint: OfficeRGB(r: 0.9, g: 0.55, b: 0.15), blend: 0.5, prop: .carrier)
        var box: SKSpriteNode?
        if theme == .vector { a.carryingBox = true }   // vektör: koli gövdeye pişirilmiş taşıma karelerinde
        else if let t = assets.artTexture("box") {
            let n = SKSpriteNode(texture: t, size: t.size())
            n.anchorPoint = CGPoint(x: 0.5, y: 0)
            n.position = CGPoint(x: 0, y: 14)
            n.zPosition = 11
            a.root.addChild(n)
            box = n
        }
        run(route: [spots.door, spots.entrance] + there, for: a) { [weak self] in
            guard let self else { return }
            box?.removeFromParent()
            a.carryingBox = false
            a.body.texture = self.tex(a, .up, 1)
            for p in parts {
                if p.isDesk {
                    let home = p.node.position
                    p.node.position = CGPoint(x: home.x, y: home.y + 24)
                    p.node.run(.group([.move(to: home, duration: OfficeCarrier.dropDuration), .fadeIn(withDuration: OfficeCarrier.dropDuration)]))
                } else {
                    p.node.run(.sequence([.wait(forDuration: OfficeCarrier.dropDuration), .fadeIn(withDuration: 0.2)]))
                }
            }
            a.root.run(.wait(forDuration: 0.9)) {
                MainActor.assumeIsolated {
                    self.run(route: [target] + back + [spots.door], for: a) {
                        self.dismissProp(a) { self.finishCarrier() }
                    }
                }
            }
        }
        notify()
    }

    private func finishCarrier() {
        carrying = false
        let pending = pendingSpawns
        pendingSpawns = [:]
        for (_, p) in pending.sorted(by: { $0.key < $1.key }) where actors[p.member.id] == nil { spawn(p.member, seat: p.seat, animated: true, now: .now) }
        notify()
    }

    // MARK: Ofis v3 — tıklama / üzerine gelme

    /// Odanın yerel noktasında (y yukarı) en üstteki karakter.
    func actor(atLocal p: CGPoint) -> OfficeActor? {
        var best: OfficeActor?
        for a in actors.values where !a.leaving {
            let s = abs(a.body.yScale)
            let r = CGRect(x: a.root.position.x - 9 * s, y: a.root.position.y + a.body.position.y - 1, width: 18 * s, height: 31 * s)
            if r.contains(p), best == nil || a.root.zPosition > best!.root.zPosition { best = a }
        }
        return best
    }

    /// Beyaz tahtaya (yönetici kartı) isabet mi.
    func boardContains(_ p: CGPoint) -> Bool {
        guard let i = kit.spots.boardIndex, i < kit.layout.furniture.count else { return false }
        let f = kit.layout.furniture[i], b = kit.bounds
        return CGRect(x: CGFloat((f.col - b.minCol) * 16), y: CGFloat(kit.worldHeight) - CGFloat((f.row - b.minRow) * 16 + 32), width: 32, height: 32).contains(p)
    }

    var executiveMemberID: String? { actors.values.first { $0.isExecutive }?.member.id }
    func member(id: String) -> OfficeMember? { actors[id]?.member }
    func actorTop(id: String) -> CGPoint? { actors[id].map { CGPoint(x: $0.root.position.x, y: $0.root.position.y + 32 * abs($0.body.yScale)) } }

    private func notify() { onAnimationChange?() }
}
