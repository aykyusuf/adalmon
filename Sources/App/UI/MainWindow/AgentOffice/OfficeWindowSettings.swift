import AppKit
import Foundation
import Observation

/// Ayrı "Ajan ofisi" penceresinin anahtarları. UserDefaults'ta tek JSON olarak durur; bozuk/eksik kayıt varsayılana düşer.
struct OfficeWindowSettings: Codable, Equatable, Sendable {
    /// Hep üstte: pencere düzeyi `.floating` (kapalıyken `.normal`).
    var alwaysOnTop = false
    /// Tüm masaüstlerinde (Space) görünür: `.canJoinAllSpaces`.
    var allSpaces = false
    /// Şeffaf başlık çubuğu (başlık metni gizlenir, sahne arkasından görünür).
    var transparentTitlebar = false

    static let defaultsKey = "officeWindow.settings"
    static let `default` = OfficeWindowSettings()

    init(alwaysOnTop: Bool = false, allSpaces: Bool = false, transparentTitlebar: Bool = false) {
        self.alwaysOnTop = alwaysOnTop
        self.allSpaces = allSpaces
        self.transparentTitlebar = transparentTitlebar
    }

    // Eksik anahtarlar varsayılan olur (eski/kısmi kayıt); türü yanlış bir değer tüm kaydı geçersiz kılar.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? false
        allSpaces = try c.decodeIfPresent(Bool.self, forKey: .allSpaces) ?? false
        transparentTitlebar = try c.decodeIfPresent(Bool.self, forKey: .transparentTitlebar) ?? false
    }

    var level: NSWindow.Level { alwaysOnTop ? .floating : .normal }
    var collectionBehavior: NSWindow.CollectionBehavior { allSpaces ? [.canJoinAllSpaces] : [] }

    func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    /// Bozuk, boş ya da JSON olmayan veri varsayılanı verir.
    static func decode(_ data: Data?) -> OfficeWindowSettings {
        guard let data, let value = try? JSONDecoder().decode(OfficeWindowSettings.self, from: data) else { return .default }
        return value
    }

    static func load(from defaults: UserDefaults) -> OfficeWindowSettings {
        decode(defaults.data(forKey: defaultsKey))
    }

    func save(to defaults: UserDefaults) {
        defaults.set(encoded(), forKey: Self.defaultsKey)
    }

    @MainActor
    func apply(to window: NSWindow) {
        window.level = level
        window.collectionBehavior = collectionBehavior
        window.titlebarAppearsTransparent = transparentTitlebar
        window.titleVisibility = transparentTitlebar ? .hidden : .visible
    }
}

/// Pencere çerçevesinin kalıcı kaydı (x, y, genişlik, yükseklik dizisi) ve doğrulaması. Saf işlevler: ekranlar parametredir.
enum OfficeWindowFrame {
    static let defaultsKey = "officeWindow.frame"
    static let minSize = NSSize(width: 480, height: 360)
    static let defaultSize = NSSize(width: 760, height: 520)
    /// Kayıtlı çerçevenin görünür bir ekranla en az bu kadar (her iki eksende) kesişmesi gerekir; yoksa (ekran çıkarılmış) varsayılan.
    static let minVisibleOverlap: CGFloat = 80

    static func encode(_ frame: NSRect) -> [Double] {
        [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height]
    }

    /// Geçersiz (sayı olmayan, eksik/fazla öğeli, sonlu olmayan, devasa) kayıt ya da hiçbir ekranda görünmeyen çerçeve nil.
    /// Küçük boyutlar `minSize`'a yükseltilir.
    static func decode(_ raw: Any?, visibleFrames: [NSRect]) -> NSRect? {
        guard let numbers = raw as? [NSNumber], numbers.count == 4 else { return nil }
        let v = numbers.map(\.doubleValue)
        guard v.allSatisfy(\.isFinite), v[2] <= 20_000, v[3] <= 20_000, abs(v[0]) <= 100_000, abs(v[1]) <= 100_000 else { return nil }
        guard v[2] > 0, v[3] > 0 else { return nil }
        let frame = NSRect(x: v[0], y: v[1], width: max(v[2], minSize.width), height: max(v[3], minSize.height))
        let visible = visibleFrames.contains { screen in
            let overlap = screen.intersection(frame)
            return !overlap.isNull && overlap.width >= minVisibleOverlap && overlap.height >= minVisibleOverlap
        }
        return visible ? frame : nil
    }

    /// Görünür alanın ortasında `defaultSize` (alana sığacak şekilde kırpılır).
    static func defaultFrame(visible: NSRect) -> NSRect {
        let width = min(visible.width, defaultSize.width)
        let height = min(visible.height, defaultSize.height)
        return NSRect(x: (visible.midX - width / 2).rounded(), y: (visible.midY - height / 2).rounded(),
                      width: width.rounded(), height: height.rounded())
    }
}

/// Pencere içeriğinin paylaştığı durum: anahtarlar (kalıcı) ve odak odası. Değişince denetleyici pencereye uygular ve kaydeder.
@MainActor @Observable
final class OfficeWindowState {
    var settings: OfficeWindowSettings {
        didSet { if settings != oldValue { onSettingsChange?(settings) } }
    }
    /// Odaklanılan oda (oturum kimliği); nil: hepsi görünür.
    var selectedRoom: String?
    @ObservationIgnored var onSettingsChange: ((OfficeWindowSettings) -> Void)?

    init(settings: OfficeWindowSettings) {
        self.settings = settings
    }
}
