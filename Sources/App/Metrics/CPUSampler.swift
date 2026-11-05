import Darwin
import Foundation

/// host_processor_info tick farklarından CPU kullanımını hesaplar.
/// İş parçacığı güvenli değildir; `MetricsSampler` seri kuyruğundan çağrılır.
final class CPUSampler {
    private struct Ticks {
        var user: UInt32
        var system: UInt32
        var idle: UInt32
        var nice: UInt32
    }

    private let host = mach_host_self()
    private var previous: [Ticks] = []
    /// P/E çekirdek sayıları sabittir, bir kez okunur.
    private let performanceCores = Int(Sysctl.int32("hw.perflevel0.logicalcpu") ?? 0)
    private let efficiencyCores = Int(Sysctl.int32("hw.perflevel1.logicalcpu") ?? 0)

    func sample() -> CPUStats {
        let current = readTicks()
        defer { previous = current }

        var perCore = [Double](repeating: 0, count: current.count)
        var sumUser: UInt64 = 0
        var sumSystem: UInt64 = 0
        var sumTotal: UInt64 = 0

        if previous.count == current.count {
            for (index, now) in current.enumerated() {
                let before = previous[index]
                // Tick sayaçları 32 bit; taşmaya karşı wrapping çıkarma.
                let user = UInt64(now.user &- before.user)
                let system = UInt64(now.system &- before.system)
                let idle = UInt64(now.idle &- before.idle)
                let nice = UInt64(now.nice &- before.nice)
                let total = user + system + idle + nice
                if total > 0 {
                    perCore[index] = Double(user + system + nice) / Double(total)
                }
                sumUser += user + nice
                sumSystem += system
                sumTotal += total
            }
        }

        let totalDouble = Double(sumTotal)
        return CPUStats(
            total: sumTotal == 0 ? 0 : Double(sumUser + sumSystem) / totalDouble,
            user: sumTotal == 0 ? 0 : Double(sumUser) / totalDouble,
            system: sumTotal == 0 ? 0 : Double(sumSystem) / totalDouble,
            perCore: perCore,
            performanceCores: performanceCores,
            efficiencyCores: efficiencyCores,
            loadAverage: loadAverage()
        )
    }

    private func readTicks() -> [Ticks] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return [] }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), size)
        }

        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { core in
            let base = core * stride
            return Ticks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            )
        }
    }

    private func loadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return [0, 0, 0] }
        return loads
    }
}
