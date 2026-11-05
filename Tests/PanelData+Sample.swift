import Foundation
@testable import Adalmon

extension PanelData {
    /// Gerçekçi sahte veri: 8 uygulama, 60 sn geçmiş, sıcaklık, mobil kota.
    static var sample: PanelData {
        let wave = (0..<60).map { 0.5 + 0.35 * sin(Double($0) / 6) }
        let snapshot = SystemSnapshot(
            timestamp: .now,
            cpu: CPUStats(total: 0.23, user: 0.15, system: 0.08, perCore: [], performanceCores: 8, efficiencyCores: 4, loadAverage: [2.31, 2.1, 1.9]),
            memory: MemoryStats(totalBytes: 16_000_000_000, usedBytes: 9_800_000_000, appBytes: 6_000_000_000, wiredBytes: 2_000_000_000,
                                compressedBytes: 1_000_000_000, cachedBytes: 3_000_000_000, swapUsedBytes: 500_000_000,
                                swapTotalBytes: 2_000_000_000, pressure: .normal),
            disk: DiskStats(totalBytes: 994_000_000_000, freeBytes: 300_000_000_000, availableBytes: 312_400_000_000,
                            readBytesPerSecond: 2_100_000, writeBytesPerSecond: 640_000),
            network: InterfaceStats(primaryInterface: "en0", downloadBytesPerSecond: 1_840_000, uploadBytesPerSecond: 96_000,
                                    cumulativeIn: [:], cumulativeOut: [:]),
            gpu: GPUStats(utilization: 0.12, rendererUtilization: 0.1, tilerUtilization: 0.05, memoryUsedBytes: 1_200_000_000,
                          load: 0.08, activeResidency: 0.11, frequencyMHz: 1_120, maxFrequencyMHz: 1_578),
            temperature: TemperatureStats(cpu: 54, cpuMax: 61, gpu: 48, ssd: 40, battery: 31)
        )
        func app(_ path: String, _ mb: Double, mobile: Double = 0, _ domains: [String]) -> AppUsage {
            let bytes = UInt64(mb * 1_000_000)
            return AppUsage(app: path, bytes: bytes, mobileBytes: UInt64(mobile * 1_000_000),
                            domains: domains.enumerated().map { ($0.element, bytes / UInt64($0.offset + 2)) })
        }
        let today = [
            app("/Applications/Safari.app", 1_240, mobile: 210, ["youtube.com", "apple.com"]),
            app("/System/Applications/Music.app", 812, ["apple.com"]),
            app("/System/Applications/Mail.app", 344, mobile: 12, ["icloud.com", "google.com"]),
            app("/System/Applications/Photos.app", 221, ["icloud.com"]),
            app("/System/Applications/Messages.app", 96, ["apple.com"]),
            app("/System/Applications/Maps.app", 61, ["apple.com"]),
            app("nsurlsessiond", 48, ["apple.com"]),
            app("/System/Applications/News.app", 22, ["apple.com"]),
        ]
        let last60 = [
            app("/Applications/Safari.app", 41.2, ["youtube.com"]),
            app("/System/Applications/Music.app", 12.8, ["apple.com"]),
            app("/System/Applications/Mail.app", 1.4, ["icloud.com"]),
            app("/System/Applications/Messages.app", 0.3, ["apple.com"]),
        ]
        return PanelData(
            snapshot: snapshot,
            cpuHistory: wave.map { $0 * 0.4 },
            gpuHistory: wave.map { $0 * 0.2 },
            memHistory: wave.map { 0.55 + $0 * 0.1 },
            downHistory: wave.map { $0 * 2_000_000 },
            upHistory: wave.map { $0 * 150_000 },
            last60: last60,
            today: today,
            downLast60: 52_000_000, upLast60: 3_700_000,
            downToday: 2_640_000_000, upToday: 204_000_000,
            mobileToday: 1_220_000_000, wifiToday: 1_620_000_000, unattributedMobile: 40_000_000,
            dailyCapBytes: 3_000_000_000,
            blockedApps: ["/System/Applications/News.app"],
            isMobile: false, medium: .wifi, interfaceName: "en0",
            filterConnected: true, installerState: .active,
            proxyPorts: [], proxyOwnerPaths: [], toast: nil
        )
    }
}
