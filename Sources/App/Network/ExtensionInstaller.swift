@preconcurrency import NetworkExtension
import Observation
import SystemExtensions

/// Filtre system extension'ını yükler/kaldırır ve NEFilterManager ayarını yönetir.
@MainActor @Observable
final class ExtensionInstaller: NSObject, @preconcurrency OSSystemExtensionRequestDelegate {
    enum State: Equatable { case unknown, notInstalled, needsApproval, installing, active, failed(String) }

    private(set) var state: State = .unknown

    /// Hız sınırı için saydam proxy açık mı (en az bir sınır varken ve filtre kuruluyken).
    private(set) var proxyActive = false
    /// Saydam proxy ayarı kaydedilemediyse / başlatılamadıysa son hata.
    private(set) var proxyError: String?
    /// AppModel ayarlar: en az bir uygulama sınırı var mı. Yoksa proxy kapalı kalır (sıfır ek yük).
    private var proxyWanted = false
    private var proxySyncTask: Task<Void, Never>?

    func refresh() async {
        let m = NEFilterManager.shared()
        try? await m.loadFromPreferences()
        state = (m.providerConfiguration != nil && m.isEnabled) ? .active : .notInstalled
    }

    /// Filtre zaten kuruluysa, uygulamanın içindeki (daha yeni) extension sürümüyle sessizce değiştirir.
    func updateIfInstalled() {
        guard state == .active else { return }
        syncProxy()
        let r = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: IPC.filterBundleID, queue: .main)
        r.delegate = self
        OSSystemExtensionManager.shared.submitRequest(r)
    }

    func install() {
        state = .installing
        let r = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: IPC.filterBundleID, queue: .main)
        r.delegate = self
        OSSystemExtensionManager.shared.submitRequest(r)
    }

    func uninstall() {
        Task {
            let m = NEFilterManager.shared()
            try? await m.loadFromPreferences()
            try? await m.removeFromPreferences()
            await removeProxyConfiguration()
            let r = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: IPC.filterBundleID, queue: .main)
            r.delegate = self
            OSSystemExtensionManager.shared.submitRequest(r)
            state = .notInstalled
        }
    }

    private func enableFilter() async {
        let m = NEFilterManager.shared()
        do {
            try await m.loadFromPreferences()
            let cfg = NEFilterProviderConfiguration()
            cfg.filterSockets = true
            cfg.filterPackets = false
            m.providerConfiguration = cfg
            m.localizedDescription = "Adalmon"
            m.isEnabled = true
            try await m.saveToPreferences()
            state = .active
            syncProxy()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Saydam proxy (hız sınırı)

    /// Sınır olup olmadığını bildir; değiştiyse proxy açılır/kapanır.
    func setProxyWanted(_ wanted: Bool) {
        guard wanted != proxyWanted else { return }
        proxyWanted = wanted
        syncProxy()
    }

    /// Proxy ayarını `proxyWanted` ve filtre durumuna göre uygular. Ardışık çağrılar sıraya girer.
    func syncProxy() {
        let previous = proxySyncTask
        proxySyncTask = Task {
            await previous?.value
            await applyProxy(enabled: proxyWanted && state == .active)
        }
    }

    private static func loadProxyManager() async throws -> NETransparentProxyManager? {
        let all = try await NETransparentProxyManager.loadAllFromPreferences()
        return all.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == IPC.filterBundleID }
    }

    private func applyProxy(enabled: Bool) async {
        do {
            var manager = try await Self.loadProxyManager()
            if manager == nil {
                // Hiç sınır yoksa ayar oluşturma (ilk kayıt kullanıcıdan onay ister).
                guard enabled else { proxyActive = false; return }
                let m = NETransparentProxyManager()
                let proto = NETunnelProviderProtocol()
                proto.providerBundleIdentifier = IPC.filterBundleID
                proto.serverAddress = "Adalmon"
                m.protocolConfiguration = proto
                m.localizedDescription = "Adalmon hız sınırı"
                manager = m
            }
            guard let manager else { return }
            if enabled {
                // Yeniden başlatmadan sonra da açılsın diye her zaman bağlan kuralı.
                let rule = NEOnDemandRuleConnect()
                rule.interfaceTypeMatch = .any
                manager.onDemandRules = [rule]
                manager.isOnDemandEnabled = true
                manager.isEnabled = true
                try await manager.saveToPreferences()
                try await manager.loadFromPreferences()
                if manager.connection.status == .disconnected || manager.connection.status == .invalid {
                    try manager.connection.startVPNTunnel()
                }
                proxyActive = true
            } else {
                manager.connection.stopVPNTunnel()
                if manager.isEnabled || manager.isOnDemandEnabled {
                    manager.isOnDemandEnabled = false
                    manager.isEnabled = false
                    try await manager.saveToPreferences()
                }
                proxyActive = false
            }
            proxyError = nil
        } catch {
            proxyError = error.localizedDescription
            proxyActive = false
        }
    }

    private func removeProxyConfiguration() async {
        proxySyncTask?.cancel()
        guard let m = try? await Self.loadProxyManager() else { return }
        m.connection.stopVPNTunnel()
        try? await m.removeFromPreferences()
        proxyActive = false
    }

    // MARK: OSSystemExtensionRequestDelegate

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        state = .needsApproval
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        guard request.identifier == IPC.filterBundleID, state != .notInstalled else { return }
        Task { await enableFilter() }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        state = .failed(error.localizedDescription)
    }
}
