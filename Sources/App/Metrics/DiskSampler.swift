import Darwin
import Foundation
import IOKit

/// "/" volume alanı (statfs + URL resource values) ve IOKit blok sürücü throughput'u.
final class DiskSampler {
    private struct Space {
        var total: UInt64
        var free: UInt64
        var available: UInt64
    }

    /// Alan bilgisi yavaş değişir; her çağrıda sorgulamak yerine bu kadar çağrıda bir yenilenir.
    private static let spaceRefreshInterval = 120

    private var previousCounters: (read: UInt64, write: UInt64)?
    private var cachedSpace: Space?
    private var callsSinceSpace = 0

    func sample(elapsed: Double) -> DiskStats {
        let space = currentSpace()
        var readRate = 0.0
        var writeRate = 0.0

        if let counters = readCounters() {
            if let previous = previousCounters, elapsed > 0 {
                // Sürücü kaybolursa toplam geriye gidebilir; negatif sıçramayı 0'a sabitle.
                readRate = counters.read >= previous.read ? Double(counters.read - previous.read) / elapsed : 0
                writeRate = counters.write >= previous.write ? Double(counters.write - previous.write) / elapsed : 0
            }
            previousCounters = counters
        }

        return DiskStats(
            totalBytes: space.total,
            freeBytes: space.free,
            availableBytes: space.available,
            readBytesPerSecond: readRate,
            writeBytesPerSecond: writeRate
        )
    }

    private func currentSpace() -> Space {
        if let cachedSpace, callsSinceSpace < Self.spaceRefreshInterval {
            callsSinceSpace += 1
            return cachedSpace
        }
        callsSinceSpace = 1

        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        let values = try? url.resourceValues(forKeys: keys)
        let total = UInt64(max(0, values?.volumeTotalCapacity ?? 0))

        var free: UInt64 = 0
        var fs = statfs()
        if statfs("/", &fs) == 0 {
            free = UInt64(fs.f_bavail) * UInt64(fs.f_bsize)
        }
        let available = UInt64(max(0, values?.volumeAvailableCapacityForImportantUsage ?? Int64(free)))

        let space = Space(total: total, free: free, available: available)
        cachedSpace = space
        return space
    }

    /// Tüm IOBlockStorageDriver'ların kümülatif okuma/yazma byte toplamı.
    private func readCounters() -> (read: UInt64, write: UInt64)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var write: UInt64 = 0
        var found = false
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let property = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0),
                  let statistics = property.takeRetainedValue() as? [String: Any] else { continue }
            found = true
            read += (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            write += (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return found ? (read, write) : nil
    }
}
