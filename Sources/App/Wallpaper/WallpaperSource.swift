import CoreGraphics
import Foundation

/// Duvar kâğıdının içerik kaynağı. Aynı anda yalnızca BİRİ çalışır: kaynak değişince diğeri tamamen durur
/// (video çözümü / oynatıcılar kapanır, pencere içeriği değişir).
enum WallpaperSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case video, office

    var id: String { rawValue }
    var title: String { self == .video ? "Video" : "Ajan ofisi" }
}

/// Ofis kaynağında etiketler (karakter adları, balonlar): Otomatik (zoom eşiği), Hep, Hiç.
enum OfficeLabelPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, always, never

    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Otomatik"
        case .always: "Hep"
        case .never: "Hiç"
        }
    }
}

enum OfficeWallpaperBackground: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Otomatik: ışık gece olunca Koyu, gündüz Açık (ışık modunu izler; "Işık" Otomatik ise yerel saate göre).
    case auto, dark, light, office

    var id: String { rawValue }
    /// Otomatik ise gece/gündüze göre Koyu ya da Açık; diğerleri kendisi.
    func resolved(night: Bool) -> OfficeWallpaperBackground { self == .auto ? (night ? .dark : .light) : self }
    var title: String {
        switch self {
        case .auto: "Otomatik"
        case .dark: "Koyu"
        case .light: "Açık"
        case .office: "Ofis"
        }
    }
    /// Sahne zemini (odaların dışı): koyu #0E1014, açık #E7EAF0. Ofis: temalı arka planın yedeği (piksel temada eski koyu zemin #12131A).
    var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .dark, .auto: (r: 14.0 / 255.0, g: 16.0 / 255.0, b: 20.0 / 255.0)
        case .light: (r: 231.0 / 255.0, g: 234.0 / 255.0, b: 240.0 / 255.0)
        case .office: (r: OfficeBackdropStyle.defaultSolid.r, g: OfficeBackdropStyle.defaultSolid.g, b: OfficeBackdropStyle.defaultSolid.b)
        }
    }
    /// Sahnenin arka plan stili: Ofis → temalı (vektör temada gradyan + doku), diğerleri düz renk.
    var style: OfficeBackdropStyle {
        if self == .office { return .themed }
        let c = rgb
        return .solid(OfficeRGB(r: c.r, g: c.g, b: c.b))
    }
}

/// Ofis duvar kâğıdı seçenekleri (tema ayrıca uygulamanın mevcut `officeTheme` ayarından gelir).
struct OfficeWallpaperOptions: Codable, Equatable, Sendable {
    var lighting: OfficeLightingMode = .auto
    var background: OfficeWallpaperBackground = .office
    var labels: OfficeLabelPolicy = .auto

    init() {}

    /// Eksik ya da bozuk anahtarlar varsayılana düşer.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = OfficeWallpaperOptions()
        lighting = (try? c.decodeIfPresent(OfficeLightingMode.self, forKey: .lighting)) ?? d.lighting
        background = (try? c.decodeIfPresent(OfficeWallpaperBackground.self, forKey: .background)) ?? d.background
        labels = (try? c.decodeIfPresent(OfficeLabelPolicy.self, forKey: .labels)) ?? d.labels
    }
}

extension OfficeLightingMode: Codable {}

/// Ayarlardan türeyen etkin kaynak. Saf: kaynak değişiminde neyin duracağı/başlayacağı buradan çıkar.
enum WallpaperSourcePlan: Equatable, Sendable {
    case off, video, office

    static func active(for settings: WallpaperSettings) -> WallpaperSourcePlan {
        guard settings.enabled else { return .off }
        return settings.source == .office ? .office : .video
    }

    var runsVideo: Bool { self == .video }
    var runsOffice: Bool { self == .office }

    /// `self` → `next` geçişinde durması gerekenler (iki kaynak asla birlikte etkin kalmaz).
    func stops(whenSwitchingTo next: WallpaperSourcePlan) -> Set<WallpaperSource> {
        var out: Set<WallpaperSource> = []
        if runsVideo && !next.runsVideo { out.insert(.video) }
        if runsOffice && !next.runsOffice { out.insert(.office) }
        return out
    }

    /// `self` → `next` geçişinde başlaması gerekenler.
    func starts(whenSwitchingTo next: WallpaperSourcePlan) -> Set<WallpaperSource> {
        var out: Set<WallpaperSource> = []
        if next.runsVideo && !runsVideo { out.insert(.video) }
        if next.runsOffice && !runsOffice { out.insert(.office) }
        return out
    }
}

/// Ofis duvar kâğıdının genel bakış kamerası (tüm odalar ekrana sığar, ortalanır) ve etiket eşiği. Saf mantık.
enum OfficeWallpaperCamera {
    /// Görünümün her kenarında bırakılan boşluk oranı.
    static let paddingFraction = 0.04
    /// Tek boş oda gibi küçük içerik dev görünmesin.
    static let maxZoom = 4.0
    /// Otomatik etiket eşiği: bunun altında (küçük ekran / çok oda) karakter etiketleri gizlenir.
    static let labelZoomThreshold = 1.5
    /// Metin balonları için eşik.
    static let bubbleZoomThreshold = 2.0

    /// 1...n sütunlu ızgaralar denenir; ekrana en büyük sığan dizilim seçilir (kesirli zoom). Satırlar sütun hizasına bağlı değil,
    /// birbirine bitişik dizilip yatay ortalanır (farklı boyutlu odalar arasında boşluk kalmaz).
    static func bestArrangement(_ sizes: [OfficeRoomSize], view: CGSize) -> OfficeRoomArrangement {
        guard !sizes.isEmpty, view.width > 0, view.height > 0 else { return OfficeRoomArranger.arrange(sizes, columns: 1) }
        var best: (arr: OfficeRoomArrangement, fit: Double)?
        for columns in 1...sizes.count {
            let arr = packed(sizes, columns: columns)
            let fit = min(view.width / arr.contentWidth, view.height / arr.contentHeight)
            if best == nil || fit > best!.fit + 1e-9 { best = (arr, fit) }
        }
        return best!.arr
    }

    /// Satır satır dizilim: her satırda odalar `gap` aralıkla yan yana, satır içerik genişliğinde ortalı; satır yüksekliği en uzun oda.
    static func packed(_ sizes: [OfficeRoomSize], columns requested: Int) -> OfficeRoomArrangement {
        let margin = OfficeRoomArranger.margin, gap = OfficeRoomArranger.gap
        let columns = max(1, min(requested, sizes.count))
        let rows = stride(from: 0, to: sizes.count, by: columns).map { Array(sizes[$0..<min($0 + columns, sizes.count)]) }
        let rowWidths = rows.map { $0.reduce(0) { $0 + $1.width } + gap * Double($0.count - 1) }
        let inner = rowWidths.max() ?? 0
        var cells: [OfficeRoomCell] = []
        var y = margin
        for (r, row) in rows.enumerated() {
            var x = margin + (inner - rowWidths[r]) / 2
            for s in row {
                cells.append(OfficeRoomCell(id: s.id, x: x, y: y, width: s.width, height: s.height))
                x += s.width + gap
            }
            y += (row.map(\.height).max() ?? 0) + gap
        }
        return OfficeRoomArrangement(cells: cells, columns: columns, contentWidth: inner + margin * 2, contentHeight: y - gap + margin)
    }

    /// Genel bakış zoom'u ve merkezi (içerik koordinatı). `integerOnly` (piksel tema): ≥1 iken tamsayıya iner.
    static func overview(content: CGSize, view: CGSize, integerOnly: Bool, maxZoom: Double = OfficeWallpaperCamera.maxZoom) -> (zoom: CGFloat, center: CGPoint) {
        let center = CGPoint(x: content.width / 2, y: content.height / 2)
        guard content.width > 0, content.height > 0, view.width > 0, view.height > 0 else { return (1, center) }
        let usable = 1 - 2 * paddingFraction
        var z = min(view.width * usable / content.width, view.height * usable / content.height)
        z = min(maxZoom, z)
        if integerOnly && z >= 1 { z = z.rounded(.down) }
        return (CGFloat(z), center)
    }

    static func showsLabels(_ policy: OfficeLabelPolicy, zoom: Double) -> Bool {
        switch policy {
        case .always: true
        case .never: false
        case .auto: zoom >= labelZoomThreshold
        }
    }

    static func showsBubbles(_ policy: OfficeLabelPolicy, zoom: Double) -> Bool {
        switch policy {
        case .always: zoom >= 1
        case .never: false
        case .auto: zoom >= bubbleZoomThreshold
        }
    }
}

/// Ofis kaynağının beslemesi: canlı üyeler ve ajan özelliği açık mı (kapalıyken sahne boş kalır).
struct OfficeFeedSnapshot: Equatable, Sendable {
    var members: [OfficeMember] = []
    var agentsEnabled = true

    /// Sahnede gösterilecek üyeler: özellik kapalıysa boş.
    var visibleMembers: [OfficeMember] { agentsEnabled ? members : [] }
    var sessionCount: Int { visibleMembers.filter { $0.parentID == nil }.count }
}

/// Denetleyiciye ajan verisini veren köprü (uygulama açılışında bağlanır; okunan @Observable alanlar izlenir).
struct OfficeWallpaperFeed {
    var snapshot: @MainActor () -> OfficeFeedSnapshot
    /// Duvar kâğıdı sahnesi oynarken true: arka plan işlemleri örneklemesi için gözlemci (UI görünürken talep-temelli yoklama).
    var setShellObserved: @MainActor (Bool) -> Void = { _ in }
}
