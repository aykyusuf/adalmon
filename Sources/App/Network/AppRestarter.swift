import AppKit

/// Bağlantı sıfırlama işe yaramayınca yedek yol: uygulamayı kapatıp yeniden açar (Chrome sekmeleri kendi geri yükler).
@MainActor
enum AppRestarter {
    private static let terminateTimeout: Duration = .seconds(10)

    /// `.app` paketini kapatır, çıkmasını bekler (en çok 10 sn; zorla kapatmaz), sonra yeniden açar.
    /// Paket değilse, çalışmıyorsa, kapanmadıysa ya da açılamadıysa `false`.
    static func restart(appKey: String) async -> Bool {
        guard appKey.hasSuffix(".app") else { return false }
        let url = URL(fileURLWithPath: appKey)
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.standardizedFileURL == url.standardizedFileURL
        }
        guard !running.isEmpty else { return false }

        for app in running { app.terminate() }
        let deadline = ContinuousClock.now + terminateTimeout
        while running.contains(where: { !$0.isTerminated }) {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(200))
        }

        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return true
        } catch {
            NSLog("Adalmon: uygulama yeniden açılamadı: \(error.localizedDescription)")
            return false
        }
    }
}
