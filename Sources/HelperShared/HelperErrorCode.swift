import Foundation

enum HelperErrorCode: String, Codable, Sendable, Equatable, Error {
    case outOfRange
    case unsupported
    case conflictsWithLimit
    case smcFailure
    case pmsetFailure
    case versionMismatch
    case batteryUnavailable

    var message: String {
        switch self {
        case .outOfRange: "Değer izin verilen aralığın dışında."
        case .unsupported: "Bu Mac'te ya da bu macOS sürümünde desteklenmiyor."
        case .conflictsWithLimit: "Şarj sınırı açıkken elle şarj engellenemez."
        case .smcFailure: "Donanım yazması başarısız oldu; şarj serbest bırakıldı."
        case .pmsetFailure: "Düşük güç modu değiştirilemedi."
        case .versionMismatch: "Yardımcı sürümü uygulamayla uyuşmuyor."
        case .batteryUnavailable: "Pil bilgisi okunamadı."
        }
    }
}
