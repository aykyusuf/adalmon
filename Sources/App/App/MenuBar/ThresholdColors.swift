import Foundation

/// Eşik renk modunda tek seviyenin rengi.
enum LevelColor: Codable, Hashable, Sendable {
    /// Bugünkü varsayılan: normal yeşil, uyarı turuncu, kritik kırmızı.
    case automatic
    /// Renksiz: menü çubuğunun etiket rengi (açık/koyu görünüme uyar).
    case none
    case custom(RGBAColor)
}

/// Eşik renk modunun seviye başına renkleri. Varsayılan (hepsi `.automatic`) bugünkü görünümün aynısıdır.
struct ThresholdColors: Codable, Equatable, Sendable {
    var normal: LevelColor = .automatic
    var warning: LevelColor = .automatic
    var critical: LevelColor = .automatic

    init(normal: LevelColor = .automatic, warning: LevelColor = .automatic, critical: LevelColor = .automatic) {
        self.normal = normal
        self.warning = warning
        self.critical = critical
    }

    subscript(level: ThresholdLevel) -> LevelColor {
        get {
            switch level {
            case .normal: normal
            case .warning: warning
            case .critical: critical
            }
        }
        set {
            switch level {
            case .normal: normal = newValue
            case .warning: warning = newValue
            case .critical: critical = newValue
            }
        }
    }

    var isDefault: Bool { self == ThresholdColors() }

    private enum CodingKeys: String, CodingKey { case normal, warning, critical }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        normal = (try? c.decodeIfPresent(LevelColor.self, forKey: .normal)) ?? .automatic
        warning = (try? c.decodeIfPresent(LevelColor.self, forKey: .warning)) ?? .automatic
        critical = (try? c.decodeIfPresent(LevelColor.self, forKey: .critical)) ?? .automatic
    }
}

extension ThresholdLevel {
    static let allLevels: [ThresholdLevel] = [.normal, .warning, .critical]

    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Uyarı"
        case .critical: "Kritik"
        }
    }
}

extension ThresholdColors {
    /// Panelin bellek baskısı renkleri: menü çubuğunda eşik renginde gösterilen ilk bellek bileşeninin renkleri.
    static func memory(in config: MenuBarConfig) -> ThresholdColors {
        config.components.first {
            $0.enabled && $0.colorMode == .threshold && $0.fields.contains { $0.category == .memory }
        }?.levelColors ?? ThresholdColors()
    }
}
