import Foundation

// IOHIDEventSystemClient özel API'si (Stats, macmon ve "hot" aynı çağrıları kullanır).
// Başlık dosyası yok; imzalar bu projeden önce Stats (Modules/Sensors/bridge.h) ve macmon (src/sources.rs) ile aynı.
@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: CFTypeRef, _ matching: CFDictionary) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: CFTypeRef) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: CFTypeRef, _ key: CFString) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: CFTypeRef, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: Int32) -> Double

/// Apple Silicon sıcaklık sensörlerini IOHID üzerinden okur. İstemci bir kez oluşturulur, servis listesi önbelleğe alınır.
/// Thread safety: yalnızca tek seri kuyruktan kullanılmalı.
final class HIDTemperatureSensors {
    private static let temperatureEventType: Int64 = 15 // kIOHIDEventTypeTemperature
    private static let temperatureField: Int32 = 15 << 16 // IOHIDEventFieldBase(type)
    private static let enumerationInterval: TimeInterval = 60

    private let client: CFTypeRef?
    /// Her `CopyEvent` bir IPC turu (~1 ms); yalnızca ilgilenilen sensörler okunur.
    private let isRelevant: (String) -> Bool
    private var services: [(name: String, service: CFTypeRef)] = []
    private var lastEnumeration: Date?

    init(isRelevant: @escaping (String) -> Bool = { _ in true }) {
        self.isRelevant = isRelevant
        client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue()
        guard let client else { return }
        // AppleVendor usage page 0xff00, usage 5 = sıcaklık sensörleri.
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = IOHIDEventSystemClientSetMatching(client, matching)
    }

    /// Sensör adı → °C (filtrelenmemiş).
    func readAll() -> [String: Double] {
        guard let client else { return [:] }
        refreshServicesIfNeeded(client: client)

        var result: [String: Double] = [:]
        for (name, service) in services {
            guard let event = IOHIDServiceClientCopyEvent(service, Self.temperatureEventType, 0, 0)?.takeRetainedValue() else { continue }
            result[name] = IOHIDEventGetFloatValue(event, Self.temperatureField)
        }
        return result
    }

    private func refreshServicesIfNeeded(client: CFTypeRef) {
        if let lastEnumeration, Date().timeIntervalSince(lastEnumeration) < Self.enumerationInterval { return }
        lastEnumeration = Date()
        guard let array = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [CFTypeRef] else {
            services = []
            return
        }
        services = array.compactMap { service in
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String, isRelevant(name) else { return nil }
            return (name, service)
        }
    }
}
