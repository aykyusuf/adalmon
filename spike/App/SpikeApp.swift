import SwiftUI
@preconcurrency import NetworkExtension
import SystemExtensions

@main
struct SpikeApp: App {
    @State private var ctl = FilterController()
    var body: some Scene {
        WindowGroup("Adalmon Spike") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("1. Extension'ı yükle") { ctl.activate() }
                    Button("2. Filtreyi aç") { ctl.enableFilter() }
                }
                HStack {
                    Button("Filtreyi kapat") { ctl.disableFilter() }
                    Button("Extension'ı kaldır") { ctl.deactivate() }
                }
                Text("Log: log stream --predicate 'subsystem == \"com.yusufayik.adalmon\"'")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                ScrollView {
                    Text(ctl.status).font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
            }
            .padding()
            .frame(minWidth: 520, minHeight: 320)
        }
    }
}

@MainActor @Observable
final class FilterController: NSObject, @preconcurrency OSSystemExtensionRequestDelegate {
    static let extID = "com.yusufayik.adalmon.filter"
    var status = ""

    private func say(_ s: String) {
        status = "[\(Date.now.formatted(date: .omitted, time: .standard))] \(s)\n" + status
    }

    func activate() {
        let r = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: Self.extID, queue: .main)
        r.delegate = self
        OSSystemExtensionManager.shared.submitRequest(r)
        say("activation istendi")
    }

    func deactivate() {
        Task {
            await setFilter(enabled: false, remove: true)
            let r = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: Self.extID, queue: .main)
            r.delegate = self
            OSSystemExtensionManager.shared.submitRequest(r)
            say("deactivation istendi")
        }
    }

    func enableFilter() { Task { await setFilter(enabled: true, remove: false) } }
    func disableFilter() { Task { await setFilter(enabled: false, remove: false) } }

    private func setFilter(enabled: Bool, remove: Bool) async {
        let m = NEFilterManager.shared()
        do {
            try await m.loadFromPreferences()
            if remove {
                try await m.removeFromPreferences()
                say("filtre konfigürasyonu silindi")
                return
            }
            if enabled {
                let cfg = NEFilterProviderConfiguration()
                cfg.filterSockets = true
                cfg.filterPackets = false
                m.providerConfiguration = cfg
                m.localizedDescription = "Adalmon Spike"
            }
            m.isEnabled = enabled
            try await m.saveToPreferences()
            say(enabled ? "filtre AÇIK" : "filtre KAPALI")
        } catch {
            say("filtre hata: \(error.localizedDescription)")
        }
    }

    // MARK: OSSystemExtensionRequestDelegate
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        say("replace \(existing.bundleVersion) -> \(ext.bundleVersion)")
        return .replace
    }
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        say("ONAY GEREKLİ: Sistem Ayarları > Genel > Giriş Öğeleri ve Uzantılar > Ağ Uzantıları")
    }
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        say("sonuç: \(result == .completed ? "tamam" : "reboot gerekli")")
    }
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        say("HATA: \(error.localizedDescription)")
    }
}
