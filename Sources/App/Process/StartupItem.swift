import Foundation

/// Başlangıçta çalışan bir öğe (LaunchAgent plist'i). Salt okunur.
struct StartupItem: Identifiable, Sendable, Equatable {
    enum Scope: String, Sendable {
        case user = "Kullanıcı"
        case allUsers = "Tüm kullanıcılar"
    }

    enum Status: Sendable, Equatable {
        case enabled, disabled, unknown

        var title: String {
            switch self {
            case .enabled: "Etkin"
            case .disabled: "Devre dışı"
            case .unknown: "Bilinmiyor"
            }
        }
    }

    var id: String { plistPath }
    var label: String
    var name: String
    var plistPath: String
    /// Çalıştırılan dosya (Program / ProgramArguments[0]); yoksa nil.
    var program: String?
    var scope: Scope
    var status: Status
    /// Oturum açılışında mı (RunAtLoad) yoksa isteğe bağlı mı (KeepAlive/zamanlanmış) başlar.
    var runsAtLoad: Bool
}
