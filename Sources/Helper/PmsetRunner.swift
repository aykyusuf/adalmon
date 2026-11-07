import Foundation

/// `pmset -a lowpowermode 0|1`. Sabit yol ve sabit argümanlar; kullanıcıdan gelen metin komuta girmez.
struct PmsetRunner: PowerSettingApplying {
    func setLowPowerMode(_ enabled: Bool) -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/pmset")
        process.arguments = ["-a", "lowpowermode", enabled ? "1" : "0"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); return false }
        return process.terminationStatus == 0
    }

    func isLowPowerModeEnabled() -> Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
}
