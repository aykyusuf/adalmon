import Foundation
import IOKit

/// IORegistry'den HID cihaz pilleri (izin gerekmez; birkaç yüz mikrosaniye).
enum HIDBatteryReader {
    static let serviceClasses = ["AppleDeviceManagementHIDEventService", "BNBMouseDevice", "AppleBluetoothHIDKeyboard", "BNBTrackpadDevice"]

    static func read(now: Date = .now) -> [DeviceReading] {
        var out: [DeviceReading] = []
        for cls in serviceClasses {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &iterator) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                defer { IOObjectRelease(entry) }
                var unmanaged: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      let props = unmanaged?.takeRetainedValue() as? [String: Any],
                      props["BatteryPercent"] != nil,
                      let reading = HIDBatteryParser.reading(from: props, now: now) else { continue }
                out.append(reading)
            }
        }
        return out
    }
}
