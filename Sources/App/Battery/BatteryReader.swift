import Foundation
import IOKit
import IOKit.ps

/// IOPS + IORegistry (AppleSmartBattery) okuması. Root gerekmez; tek okuma birkaç yüz mikrosaniye.
enum BatteryReader {
    /// Dahili pil yoksa (masaüstü Mac) nil.
    static func read(now: Date = .now, lowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled) -> BatteryReading? {
        guard let registry = registryProperties() else { return nil }
        let ps = internalBatteryDescription() ?? [:]
        var reading = AppleSmartBatteryParser.parse(registry: registry, powerSource: ps, now: now, lowPowerMode: lowPowerMode)
        if reading.isPluggedIn, !reading.adapterIsWireless, let cable = activePortCable() { reading.cable = cable }
        let ports = PowerPortAccessoryReader.read()
        reading.accessories = ports.accessories
        if reading.isPluggedIn { reading.adapterPortName = ports.adapterPortName }
        return reading
    }

    static func internalBatteryDescription() -> [String: Any]? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            if (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType { return d }
        }
        return nil
    }

    static func registryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }

    /// Bağlı (ConnectionActive) USB‑C/MagSafe portunun adından kablo türü. Yalnızca fişte okunur.
    static func activePortCable() -> BatteryCable? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleHPMInterface"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var found: BatteryCable?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var name = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &name)
            let n = String(cString: name)
            let active = IORegistryEntryCreateCFProperty(entry, "ConnectionActive" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Bool ?? false
            guard active else { continue }
            if n.localizedCaseInsensitiveContains("MagSafe") { return .magSafe }
            if n.localizedCaseInsensitiveContains("USB") { found = .usbC }
        }
        return found
    }
}
