import Foundation

/// SMAppService.daemon durumunun uygulama içi karşılığı.
enum HelperInstallState: Equatable, Sendable {
    case notInstalled
    /// Kullanıcı Sistem Ayarları › Genel › Giriş Öğeleri'nde onaylamalı.
    case requiresApproval
    case enabled
    /// Paket içinde plist/yardımcı yok (ör. uygulama /Applications dışında ya da imzasız derleme).
    case notFound
    case failed(String)

    var title: String {
        switch self {
        case .notInstalled: "Kurulu değil"
        case .requiresApproval: "Sistem Ayarları'nda onay gerekiyor"
        case .enabled: "Kurulu ve çalışıyor"
        case .notFound: "Yardımcı pakette bulunamadı"
        case let .failed(message): "Hata: \(message)"
        }
    }

    var isEnabled: Bool { self == .enabled }
}
