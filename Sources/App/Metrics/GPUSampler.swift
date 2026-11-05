import Foundation
import IOKit

/// IOAccelerator "PerformanceStatistics" üzerinden GPU kullanımını okur.
final class GPUSampler {
    func sample() -> GPUStats? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let property = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0),
                  let statistics = property.takeRetainedValue() as? [String: Any],
                  let device = percent(statistics["Device Utilization %"]) else { continue }
            return GPUStats(
                utilization: device,
                rendererUtilization: percent(statistics["Renderer Utilization %"]),
                tilerUtilization: percent(statistics["Tiler Utilization %"]),
                memoryUsedBytes: (statistics["In use system memory"] as? NSNumber)?.uint64Value
            )
        }
        return nil
    }

    /// 0-100 değerini 0...1 aralığına çevirir.
    private func percent(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        return min(max(number.doubleValue / 100, 0), 1)
    }
}
