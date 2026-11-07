import Foundation

/// Modern giriş öğesi (SMAppService): Sistem Ayarları › Genel › Giriş Öğeleri'nde "Arka planda izin ver" olarak görünenler.
struct BackgroundItem: Identifiable, Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case loginItem, agent

        var title: String {
            switch self {
            case .loginItem: "Giriş öğesi"
            case .agent: "Arka plan ajanı"
            }
        }
    }

    var id: String
    /// Ebeveyn uygulamanın adı (varsa), yoksa öğenin kendi adı.
    var name: String
    /// Ebeveyn uygulama varsa öğenin kendi adı.
    var detail: String?
    var developer: String?
    var identifier: String
    var kind: Kind
    var isEnabled: Bool
}
