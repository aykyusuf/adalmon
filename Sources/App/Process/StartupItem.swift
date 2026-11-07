import Foundation

struct StartupItem: Identifiable, Sendable, Equatable {
    enum Scope: String, Sendable {
        case user = "Kullanıcı"
        case allUsers = "Tüm kullanıcılar"
        case daemon = "Sistem hizmeti"
    }

    enum Status: Sendable, Equatable {
        case enabled, disabled, unknown

        var title: String {
            switch self {
            case .enabled: "Açık"
            case .disabled: "Kapalı"
            case .unknown: "Bilinmiyor"
            }
        }
    }

    var id: String { plistPath }
    var label: String
    var name: String
    var plistPath: String
    var program: String?
    var scope: Scope
    var status: Status
    var runsAtLoad: Bool
}
