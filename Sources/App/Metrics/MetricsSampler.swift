import Darwin
import Foundation

/// CPU, bellek, disk, ağ ve GPU örnekleyicilerini birleştirir; önceki örnekleri tutup farkları hesaplar.
///
/// Thread safety: bu sınıf kilit kullanmaz. `sample()` yalnızca tek bir seri arka plan kuyruğundan
/// çağrılmalıdır; `@unchecked Sendable` bu varsayıma dayanır.
/// Maliyet: alt süreç başlatılmaz, yalnızca Mach/sysctl/IOKit çağrıları yapılır.
final class MetricsSampler: MetricsSampling, @unchecked Sendable {
    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let disk = DiskSampler()
    private let network = NetworkInterfaceSampler()
    private let gpu = GPUSampler()
    private let gpuReport = GPUReportSampler()
    private let temperature = TemperatureSampler()

    private let nanosecondsPerTick: Double
    private var lastTick: UInt64?

    init() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        nanosecondsPerTick = Double(timebase.numer) / Double(max(timebase.denom, 1))
    }

    func sample() -> SystemSnapshot {
        let now = mach_absolute_time()
        let elapsed = lastTick.map { Double(now &- $0) * nanosecondsPerTick / 1_000_000_000 } ?? 0
        lastTick = now

        return SystemSnapshot(
            timestamp: Date(),
            cpu: cpu.sample(),
            memory: memory.sample(),
            disk: disk.sample(elapsed: elapsed),
            network: network.sample(elapsed: elapsed),
            gpu: gpuStats(),
            temperature: temperature.sample()
        )
    }

    /// IOAccelerator meşgul süresi + IOReport frekans ağırlıklı yük. Biri yoksa diğeri yine döner.
    private func gpuStats() -> GPUStats? {
        let report = gpuReport.sample()
        var stats = gpu.sample()
        if stats == nil, let report {
            stats = GPUStats(utilization: report.activeResidency, rendererUtilization: nil, tilerUtilization: nil, memoryUsedBytes: nil)
        }
        if let report {
            stats?.load = report.load
            stats?.activeResidency = report.activeResidency
            stats?.frequencyMHz = report.frequencyMHz
            stats?.maxFrequencyMHz = report.maxFrequencyMHz
        }
        return stats
    }
}
