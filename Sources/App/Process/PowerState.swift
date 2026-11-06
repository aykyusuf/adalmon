import Foundation
import IOKit.ps

/// Güç durumu: pilde mi, yüzde kaç, Düşük Güç Modu. Saatlik klasör taramasını atlama kararı için.
enum PowerState {
    struct Snapshot: Sendable, Equatable {
        var onBattery: Bool
        var batteryPercent: Int?
        var lowPowerMode: Bool
    }

    static func current() -> Snapshot {
        let lpm = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return Snapshot(onBattery: false, batteryPercent: nil, lowPowerMode: lpm)
        }
        var onBattery = false
        var percent: Int?
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            if (d[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue { onBattery = true }
            if let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 { percent = cur * 100 / max }
        }
        return Snapshot(onBattery: onBattery, batteryPercent: percent, lowPowerMode: lpm)
    }
}

/// Veri hacmi (Data) birimindeki boş alan: `statfs` (saf boş, mikrosaniye) ve Finder'ın "önemli kullanım" değeri.
enum VolumeSpace {
    static let dataVolume = "/System/Volumes/Data"

    static func freeBytes() -> UInt64? {
        var st = statfs()
        guard statfs(dataVolume, &st) == 0 || statfs("/", &st) == 0 else { return nil }
        return UInt64(st.f_bavail) &* UInt64(st.f_bsize)
    }

    /// Purgeable alan dahil (Finder'ın gösterdiği); daha yavaş, seyrek çağır.
    static func importantFreeBytes() -> UInt64? {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }
    }
}
