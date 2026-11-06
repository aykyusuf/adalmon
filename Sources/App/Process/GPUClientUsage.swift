import Foundation
import IOKit

/// Süreç başına GPU süresi: IOAccelerator → AGXDeviceUserClient çocukları → `AppUsage.accumulatedGPUTime` (ns, birikimli).
/// Belgesiz/özel; yoksa boş sözlük döner. Yalnızca "Süreçler" sayfası görünürken çağrılır (~1,6 ms).
enum GPUClientUsage {
    static func snapshot() -> [pid_t: UInt64] {
        var out: [pid_t: UInt64] = [:]
        var accelerators: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &accelerators) == KERN_SUCCESS else { return out }
        defer { IOObjectRelease(accelerators) }
        while case let accelerator = IOIteratorNext(accelerators), accelerator != 0 {
            defer { IOObjectRelease(accelerator) }
            var children: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &children) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(children) }
            while case let client = IOIteratorNext(children), client != 0 {
                defer { IOObjectRelease(client) }
                guard let creator = IORegistryEntryCreateCFProperty(client, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? String,
                      let usage = IORegistryEntryCreateCFProperty(client, "AppUsage" as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? [[String: Any]],
                      let pid = parsePID(creator) else { continue }
                let total = usage.reduce(UInt64(0)) { $0 &+ (($1["accumulatedGPUTime"] as? NSNumber)?.uint64Value ?? 0) }
                out[pid, default: 0] &+= total
            }
        }
        return out
    }

    /// "pid 601, WindowServer" → 601
    static func parsePID(_ creator: String) -> pid_t? {
        guard creator.hasPrefix("pid ") else { return nil }
        let digits = creator.dropFirst(4).prefix { $0.isNumber }
        return Int32(digits)
    }
}
