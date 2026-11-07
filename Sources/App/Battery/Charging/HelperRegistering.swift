import Foundation
import ServiceManagement

/// Yardımcıyı kaydeden/kaldıran katman. Testlerde sahtesi kullanılır; testlerde gerçek kayıt YAPILMAZ.
@MainActor
protocol HelperRegistering {
    var state: HelperInstallState { get }
    func register() throws
    func unregister() async throws
    func openLoginItemsSettings()
}

@MainActor
struct SMAppServiceRegistration: HelperRegistering {
    private var service: SMAppService { SMAppService.daemon(plistName: HelperConstants.launchDaemonPlistName) }

    var state: HelperInstallState {
        switch service.status {
        case .notRegistered: .notInstalled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        // Hiç kaydedilmemiş bir daemon için de .notFound döner; bu bir hata değil, "kurulmadı" demektir.
        // Paket gerçekten eksikse register() hata fırlatır ve o zaman gösterilir.
        case .notFound: .notInstalled
        @unknown default: .failed("bilinmeyen durum")
        }
    }

    func register() throws { try service.register() }
    func unregister() async throws { try await service.unregister() }
    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }
}
