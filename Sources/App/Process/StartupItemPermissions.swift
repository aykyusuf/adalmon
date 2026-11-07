import Foundation

/// Bir başlangıç öğesini değiştirme yetkisi (saf). Apple'ın kendi öğelerine ve yönetici gerektiren
/// (kök sahipli) klasörlerdekilere dokunulmaz.
struct StartupItemPermissions: Equatable, Sendable {
    var canModify: Bool
    /// `canModify` false ise ipucu/sebep.
    var reason: String?
    /// Sebep yönetici izniyse Sistem Ayarları'na yönlendirme önerilir.
    var needsAdmin: Bool

    static let adminReason = "Yönetici izni gerekir"
    static let appleReason = "Apple'ın kendi öğeleri değiştirilemez"
    static let invalidLabelReason = "Geçersiz etiket"

    /// Dokunulmaz etiket önekleri: Apple ve Adalmon'un kendisi.
    static let protectedPrefixes = ["com.apple.", "com.yusufayik.adalmon"]

    static func evaluate(label: String, scope: StartupItem.Scope) -> StartupItemPermissions {
        if protectedPrefixes.contains(where: { label.hasPrefix($0) }) {
            return StartupItemPermissions(canModify: false, reason: appleReason, needsAdmin: false)
        }
        guard LaunchctlCommand.isValidLabel(label) else {
            return StartupItemPermissions(canModify: false, reason: invalidLabelReason, needsAdmin: false)
        }
        switch scope {
        case .user: return StartupItemPermissions(canModify: true, reason: nil, needsAdmin: false)
        case .allUsers, .daemon: return StartupItemPermissions(canModify: false, reason: adminReason, needsAdmin: true)
        }
    }

    static func evaluate(_ item: StartupItem) -> StartupItemPermissions { evaluate(label: item.label, scope: item.scope) }
}
