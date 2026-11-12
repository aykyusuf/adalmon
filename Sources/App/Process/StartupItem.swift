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

    /// Plist'in gösterdiği program çalıştırılamaz durumda (bozuk ajan).
    enum Problem: Sendable, Equatable {
        /// `Program`/`ProgramArguments[0]` (ve `BundleProgram`) yok.
        case noProgram
        /// Program yolu diskte yok (uygulama silinmiş).
        case programMissing(String)

        var title: String {
            switch self {
            case .noProgram: "Program tanımsız"
            case .programMissing: "Program bulunamıyor"
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
    var problem: Problem? = nil

    var isBroken: Bool { problem != nil }
}
