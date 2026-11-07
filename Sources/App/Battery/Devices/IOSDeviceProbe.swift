import Foundation

struct IOSDeviceRef: Equatable, Sendable {
    var udid: String
    var connection: IOSDeviceDetails.Connection
}

enum IOSProbeFailure: Error, Equatable, Sendable {
    case libraryMissing
    case passwordProtected
    case notTrusted
    case unreachable(Int32)

    var message: String {
        switch self {
        case .libraryMissing: "libimobiledevice yüklenemedi"
        case .passwordProtected: "Cihazın kilidini aç ve tekrar dene"
        case .notTrusted: "Bu Mac'e güvenilmiyor: cihazı USB ile bağla ve “Güven”e dokun"
        case .unreachable(let code): "Cihaza ulaşılamadı (kod \(code))"
        }
    }
}

/// Test edilebilirlik için soyutlama: gerçek uygulama libimobiledevice, testler sahte kullanır.
protocol IOSDeviceProbing: Sendable {
    var isAvailable: Bool { get }
    func listDevices(includeNetwork: Bool) -> [IOSDeviceRef]
    func fetch(_ ref: IOSDeviceRef) -> Result<IOSDeviceDetails, IOSProbeFailure>
}

/// libimobiledevice üzerinden gerçek okuma. Bloklayıcıdır; ana iş parçacığı dışında çağır.
final class IOSDeviceProbe: IOSDeviceProbing, @unchecked Sendable {
    private let lib: LibIMobileDevice?
    private let label = "Adalmon"

    init(library: LibIMobileDevice? = LibIMobileDevice.load()) { lib = library }

    var isAvailable: Bool { lib != nil }

    func listDevices(includeNetwork: Bool) -> [IOSDeviceRef] {
        guard let lib else { return [] }
        var list: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
        var count: Int32 = 0
        guard lib.deviceList(&list, &count) == 0, let list else { return [] }
        defer { _ = lib.deviceListFree(list) }
        var seen: [String: IOSDeviceRef] = [:]
        for i in 0..<Int(count) {
            guard let info = list[i], let cUDID = info.load(as: UnsafePointer<CChar>?.self) else { continue }
            let type = info.load(fromByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: Int32.self)
            let udid = String(cString: cUDID)
            let connection: IOSDeviceDetails.Connection = type == 2 ? .wifi : .usb
            if connection == .wifi && !includeNetwork { continue }
            // Aynı cihaz hem USB hem ağda görünürse USB tercih edilir.
            if seen[udid]?.connection == .usb { continue }
            seen[udid] = IOSDeviceRef(udid: udid, connection: connection)
        }
        return seen.values.sorted { $0.udid < $1.udid }
    }

    func fetch(_ ref: IOSDeviceRef) -> Result<IOSDeviceDetails, IOSProbeFailure> {
        guard let lib else { return .failure(.libraryMissing) }
        var device: LibIMobileDevice.Handle?
        // IDEVICE_LOOKUP_USBMUX = 1<<1, IDEVICE_LOOKUP_NETWORK = 1<<2
        let options: Int32 = ref.connection == .usb ? 2 : 4
        let rc = ref.udid.withCString { lib.deviceNew(&device, $0, options) }
        guard rc == 0, let device else { return .failure(.unreachable(rc)) }
        defer { _ = lib.deviceFree(device) }

        var client: LibIMobileDevice.Handle?
        let hs = label.withCString { lib.lockdownHandshake(device, &client, $0) }
        guard hs == 0, let client else {
            switch hs {
            case -17: return .failure(.passwordProtected)
            case -4, -18, -19, -21, -20: return .failure(.notTrusted)
            default: return .failure(.unreachable(hs))
            }
        }
        defer { _ = lib.lockdownFree(client) }

        func value(_ domain: String?) -> [String: Any] {
            var node: LibIMobileDevice.Handle?
            let r: Int32
            if let domain { r = domain.withCString { lib.lockdownGetValue(client, $0, nil, &node) } } else { r = lib.lockdownGetValue(client, nil, nil, &node) }
            guard r == 0 else { return [:] }
            return lib.dictionary(consuming: node) ?? [:]
        }
        let general = value(nil)
        let battery = value("com.apple.mobile.battery")
        let ioreg = queryIORegistry(lib, device)
        guard !general.isEmpty || !battery.isEmpty else { return .failure(.unreachable(-1)) }
        return .success(IOSDeviceMapper.details(udid: ref.udid, connection: ref.connection, lockdown: general, battery: battery, ioreg: ioreg))
    }

    private func queryIORegistry(_ lib: LibIMobileDevice, _ device: LibIMobileDevice.Handle) -> [String: Any]? {
        var relay: LibIMobileDevice.Handle?
        guard label.withCString({ lib.diagnosticsStart(device, &relay, $0) }) == 0, let relay else { return nil }
        defer { _ = lib.diagnosticsGoodbye(relay); _ = lib.diagnosticsFree(relay) }
        var node: LibIMobileDevice.Handle?
        // iOS'ta pil: IOPMPowerSource sınıfı (AppleSmartBattery girdisi).
        let r = "IOPMPowerSource".withCString { lib.diagnosticsQuery(relay, nil, $0, &node) }
        guard r == 0 else { return nil }
        return lib.dictionary(consuming: node)
    }
}
