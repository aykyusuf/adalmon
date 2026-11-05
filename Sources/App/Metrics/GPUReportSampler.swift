import Darwin
import Foundation
import IOKit

/// GPU performans durumu (P-state) dağılımından türetilen değerler.
struct GPUFrequencyMetrics: Sendable, Equatable {
    /// 0...1 frekans ağırlıklı yük: Σ(süre_i × frekans_i) / (toplam süre × en yüksek frekans).
    var load: Double
    /// 0...1 OFF dışındaki durumlarda geçen süre oranı (powermetrics "HW active residency").
    var activeResidency: Double
    /// Aktif sürede ortalama frekans (MHz, süre ağırlıklı). Aktif süre ~0 ise nil.
    var frequencyMHz: Double?
    var maxFrequencyMHz: Double
}

/// IOReport "GPU Stats / GPU Performance States / GPUPH" kanalından (sudo gerekmez) frekans ağırlıklı
/// GPU yükünü okur. vladkens/macmon ile aynı yöntem. Abonelik bir kez kurulur; her çağrıda bir örnek
/// alınıp öncekiyle farkı hesaplanır. Seri bir kuyruktan çağrılmalıdır.
final class GPUReportSampler {
    private static let retryInterval: TimeInterval = 60
    private static let idleStates: Set<String> = ["OFF", "IDLE", "DOWN"]

    private var api: IOReportAPI?
    private var subscription: UnsafeMutableRawPointer?
    private var subscribedChannels: UnsafeMutableRawPointer?
    private var previous: UnsafeMutableRawPointer?
    private var frequenciesMHz: [Double] = []
    private var retryAfter: Date?

    deinit { teardown() }

    /// İlk çağrı taban örneği alır ve nil döner. Hata olursa nil döner ve 60 sn yeniden denemez.
    func sample() -> GPUFrequencyMetrics? {
        if let retryAfter, Date() < retryAfter { return nil }
        if subscription == nil {
            guard setup() else { return fail() }
        }
        guard let api, let current = api.createSamples(subscription, subscribedChannels, nil) else { return fail() }
        guard let last = previous else {
            previous = current
            return nil
        }
        let deltaPointer = api.createSamplesDelta(last, current, nil)
        Unmanaged<CFDictionary>.fromOpaque(last).release()
        previous = current
        guard let deltaPointer else { return fail() }
        let delta = Unmanaged<CFDictionary>.fromOpaque(deltaPointer).takeRetainedValue()
        guard let residencies = gpuphResidencies(in: delta, api: api) else { return fail() }
        return Self.compute(residencies: residencies, frequenciesMHz: frequenciesMHz)
    }

    // MARK: Pure math

    /// `residencies` GPUPH durumları sırasıyla (OFF, P1, P2, ...); `frequenciesMHz` pmgr tablosu (OFF için 0 dahil).
    /// Tablodaki sıfır frekanslı (OFF) girişler ve boşta durumları atlanır, kalanlar sırayla eşlenir.
    static func compute(residencies: [(name: String, value: Int64)], frequenciesMHz: [Double]) -> GPUFrequencyMetrics? {
        let freqs = frequenciesMHz.filter { $0 > 0 }
        guard let maxFreq = freqs.max(), maxFreq > 0,
              let offset = residencies.firstIndex(where: { !idleStates.contains($0.name) }) else { return nil }
        let active = residencies[offset...].prefix(freqs.count)
        let total = residencies.reduce(0.0) { $0 + Double(max($1.value, 0)) }
        guard total > 0 else { return nil }

        var activeTime = 0.0, weighted = 0.0
        for (index, state) in active.enumerated() {
            let time = Double(max(state.value, 0))
            activeTime += time
            weighted += time * freqs[index]
        }
        let residency = min(max(activeTime / total, 0), 1)
        return GPUFrequencyMetrics(
            load: min(max(weighted / (total * maxFreq), 0), 1),
            activeResidency: residency,
            frequencyMHz: residency > 0.01 && activeTime > 0 ? weighted / activeTime : nil,
            maxFrequencyMHz: maxFreq
        )
    }

    /// pmgr "voltage-states9" verisi: 8 baytlık (frekans, voltaj) LE UInt32 çiftleri. Sıra korunur.
    static func parseFrequencyTable(_ data: Data) -> [Double] {
        let bytes = [UInt8](data)
        let raw = stride(from: 0, to: bytes.count - bytes.count % 8, by: 8).map { i in
            UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
        }
        // GPU tablosu Hz (macmon tüm çiplerde 1e6'ya böler); kHz görünen tablolar için emniyet.
        let scale: Double = (raw.max() ?? 0) > 100_000_000 ? 1_000_000 : 1_000
        return raw.map { Double($0) / scale }
    }

    // MARK: IOReport

    private func gpuphResidencies(in delta: CFDictionary, api: IOReportAPI) -> [(name: String, value: Int64)]? {
        guard let channels = (delta as NSDictionary)["IOReportChannels"] as? NSArray else { return nil }
        for case let item as NSDictionary in channels {
            let pointer = Unmanaged.passUnretained(item).toOpaque()
            guard Self.string(api.channelName(pointer)) == "GPUPH" else { continue }
            let count = api.stateCount(pointer)
            guard count > 1 else { return nil }
            return (0..<count).map { i in
                (Self.string(api.stateName(pointer, i)) ?? "S\(i)", api.stateResidency(pointer, i))
            }
        }
        return nil
    }

    private func setup() -> Bool {
        guard let api = api ?? IOReportAPI.load() else { return false }
        self.api = api
        let table = Self.readFrequencyTable()
        guard table.contains(where: { $0 > 0 }) else { return false }
        frequenciesMHz = table

        let group = "GPU Stats" as CFString, subgroup = "GPU Performance States" as CFString
        guard let channels = api.copyChannelsInGroup(Unmanaged.passUnretained(group).toOpaque(),
                                                     Unmanaged.passUnretained(subgroup).toOpaque(), 0, 0, 0) else { return false }
        defer { Unmanaged<CFDictionary>.fromOpaque(channels).release() }
        var subscribed: UnsafeMutableRawPointer?
        guard let sub = api.createSubscription(nil, channels, &subscribed, 0, nil) else {
            if let subscribed { Unmanaged<CFDictionary>.fromOpaque(subscribed).release() }
            return false
        }
        guard let subscribed else {
            Unmanaged<AnyObject>.fromOpaque(sub).release()
            return false
        }
        subscription = sub
        subscribedChannels = subscribed
        return true
    }

    private func fail() -> GPUFrequencyMetrics? {
        teardown()
        retryAfter = Date().addingTimeInterval(Self.retryInterval)
        return nil
    }

    private func teardown() {
        if let previous { Unmanaged<CFDictionary>.fromOpaque(previous).release() }
        if let subscribedChannels { Unmanaged<CFDictionary>.fromOpaque(subscribedChannels).release() }
        if let subscription { Unmanaged<AnyObject>.fromOpaque(subscription).release() }
        previous = nil
        subscribedChannels = nil
        subscription = nil
    }

    private static func string(_ pointer: UnsafeRawPointer?) -> String? {
        pointer.map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
    }

    /// IORegistry'de `pmgr` (M6+ için `pmgr-child`) düğümündeki GPU DVFS tablosu.
    private static func readFrequencyTable() -> [Double] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMIODevice"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var name = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(entry, &name) == KERN_SUCCESS else { continue }
            let nodeName = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard nodeName == "pmgr" || nodeName == "pmgr-child",
                  let property = IORegistryEntryCreateCFProperty(entry, "voltage-states9" as CFString, kCFAllocatorDefault, 0),
                  let data = property.takeRetainedValue() as? Data else { continue }
            let table = parseFrequencyTable(data)
            if table.contains(where: { $0 > 0 }) { return table }
        }
        return []
    }
}

/// libIOReport.dylib (özel API, dyld paylaşımlı önbelleğinde) fonksiyonları; dlsym ile çözülür.
/// Create/Copy dönüşleri +1, Get dönüşleri +0 sahipliktedir.
private struct IOReportAPI {
    typealias CopyChannelsInGroup = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UInt64, UInt64, UInt64) -> UnsafeMutableRawPointer?
    typealias CreateSubscription = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?,
                                                   UnsafeMutablePointer<UnsafeMutableRawPointer?>?, UInt64, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    typealias CreateSamples = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    typealias CreateSamplesDelta = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    typealias ChannelGetString = @convention(c) (UnsafeRawPointer?) -> UnsafeRawPointer?
    typealias StateGetCount = @convention(c) (UnsafeRawPointer?) -> Int32
    typealias StateGetName = @convention(c) (UnsafeRawPointer?, Int32) -> UnsafeRawPointer?
    typealias StateGetResidency = @convention(c) (UnsafeRawPointer?, Int32) -> Int64

    let copyChannelsInGroup: CopyChannelsInGroup
    let createSubscription: CreateSubscription
    let createSamples: CreateSamples
    let createSamplesDelta: CreateSamplesDelta
    let channelName: ChannelGetString
    let stateCount: StateGetCount
    let stateName: StateGetName
    let stateResidency: StateGetResidency

    static func load() -> IOReportAPI? {
        guard let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW | RTLD_LOCAL) else { return nil }
        func symbol<T>(_ name: String, _: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let copy = symbol("IOReportCopyChannelsInGroup", CopyChannelsInGroup.self),
              let subscribe = symbol("IOReportCreateSubscription", CreateSubscription.self),
              let samples = symbol("IOReportCreateSamples", CreateSamples.self),
              let delta = symbol("IOReportCreateSamplesDelta", CreateSamplesDelta.self),
              let name = symbol("IOReportChannelGetChannelName", ChannelGetString.self),
              let count = symbol("IOReportStateGetCount", StateGetCount.self),
              let stateName = symbol("IOReportStateGetNameForIndex", StateGetName.self),
              let residency = symbol("IOReportStateGetResidency", StateGetResidency.self) else { return nil }
        return IOReportAPI(copyChannelsInGroup: copy, createSubscription: subscribe, createSamples: samples,
                           createSamplesDelta: delta, channelName: name, stateCount: count,
                           stateName: stateName, stateResidency: residency)
    }
}
