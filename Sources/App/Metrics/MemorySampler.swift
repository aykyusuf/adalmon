import Darwin
import Foundation

/// host_statistics64 ve sysctl ile bellek durumunu okur.
final class MemorySampler {
    private let host = mach_host_self()
    private let totalBytes = Sysctl.uint64("hw.memsize") ?? 0
    private let pageSize = UInt64(getpagesize())

    func sample() -> MemoryStats {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return empty() }

        let page = pageSize
        let active = UInt64(stats.active_count) * page
        let inactive = UInt64(stats.inactive_count) * page
        let speculative = UInt64(stats.speculative_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let purgeable = UInt64(stats.purgeable_count) * page
        let external = UInt64(stats.external_page_count) * page
        let internalPages = UInt64(stats.internal_page_count) * page

        let gross = active + inactive + speculative + wired + compressed
        let used = gross > purgeable + external ? gross - purgeable - external : 0
        let app = internalPages > purgeable ? internalPages - purgeable : 0

        var swap = xsw_usage()
        let hasSwap = Sysctl.read("vm.swapusage", into: &swap)

        return MemoryStats(
            totalBytes: totalBytes,
            usedBytes: min(used, totalBytes),
            appBytes: app,
            wiredBytes: wired,
            compressedBytes: compressed,
            cachedBytes: purgeable + external,
            swapUsedBytes: hasSwap ? swap.xsu_used : 0,
            swapTotalBytes: hasSwap ? swap.xsu_total : 0,
            pressure: pressure()
        )
    }

    private func pressure() -> MemoryPressure {
        guard let level = Sysctl.int32("kern.memorystatus_vm_pressure_level") else { return .normal }
        return MemoryPressure(rawValue: Int(level)) ?? .normal
    }

    private func empty() -> MemoryStats {
        MemoryStats(
            totalBytes: totalBytes, usedBytes: 0, appBytes: 0, wiredBytes: 0, compressedBytes: 0,
            cachedBytes: 0, swapUsedBytes: 0, swapTotalBytes: 0, pressure: pressure()
        )
    }
}
