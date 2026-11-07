import Foundation
import IOKit.ps

/// Dahili pilin yüzdesi ve güç kaynağı durumu (IOPS).
struct IOPSBatteryProvider: BatteryProviding {
    func snapshot() -> BatterySnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let level = d[kIOPSCurrentCapacityKey] as? Int else { continue }
            return BatterySnapshot(
                level: level,
                isPluggedIn: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
                isCharging: d[kIOPSIsChargingKey] as? Bool ?? false,
                isFullyCharged: d[kIOPSIsChargedKey] as? Bool ?? false)
        }
        return nil
    }
}
