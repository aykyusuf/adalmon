import CoreBluetooth
import Foundation

/// CoreBluetooth: (1) sisteme bağlı BLE cihazların Battery Service (0x180F / 0x2A19) değeri, (2) kısa pencerede AirPods reklam taraması.
/// Pil için: sürekli tarama ve bildirim (notify) yok; her tur bir kez okur, tarama ~10 sn ile sınırlıdır.
/// Bluetooth izin penceresi `CBCentralManager` oluşturulunca çıkar; bu yüzden nesne ancak ilk `start()` çağrısında kurulur.
final class BluetoothBatterySource: NSObject, @unchecked Sendable {
    enum State: Sendable, Equatable { case unknown, unauthorized, poweredOff, unsupported, ready }

    struct GATTSample: Sendable, Equatable {
        var name: String
        var level: Int
    }

    struct Callbacks: Sendable {
        var state: @Sendable (State) -> Void
        var gatt: @Sendable ([GATTSample]) -> Void
        var advertisement: @Sendable (AppleProximityAdvertisement, Int) -> Void
    }

    static let scanWindow: TimeInterval = 10

    private let callbacks: Callbacks
    private let queue = DispatchQueue(label: "adalmon.bluetooth", qos: .utility)
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var samples: [UUID: GATTSample] = [:]
    private var pendingReads = 0
    private var wantsRefresh = false
    private var wantsScan = false
    private var scanStop: DispatchWorkItem?

    init(callbacks: Callbacks) {
        self.callbacks = callbacks
    }

    static var isAuthorized: Bool { CBCentralManager.authorization == .allowedAlways }
    static var isDenied: Bool { CBCentralManager.authorization == .denied || CBCentralManager.authorization == .restricted }

    /// `scan`: AirPods reklam taraması da yapılsın mı.
    func refresh(scan: Bool) {
        queue.async { [self] in
            wantsRefresh = true
            wantsScan = scan
            if central == nil {
                central = CBCentralManager(delegate: self, queue: queue, options: [CBCentralManagerOptionShowPowerAlertKey: false])
            } else if central?.state == .poweredOn {
                run()
            }
        }
    }

    func stop() {
        queue.async { [self] in
            scanStop?.cancel()
            central?.stopScan()
            for p in peripherals.values { central?.cancelPeripheralConnection(p) }
            peripherals = [:]
        }
    }

    // MARK: Tur

    private func run() {
        guard let central, central.state == .poweredOn, wantsRefresh else { return }
        wantsRefresh = false
        samples = [:]
        let connected = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: GATTBattery.serviceUUID)])
        peripherals = Dictionary(uniqueKeysWithValues: connected.map { ($0.identifier, $0) })
        pendingReads = connected.count
        for p in connected {
            p.delegate = self
            if p.state == .connected { p.discoverServices([CBUUID(string: GATTBattery.serviceUUID)]) } else { central.connect(p) }
        }
        if connected.isEmpty { callbacks.gatt([]) }
        if wantsScan { startScan() }
    }

    private func startScan() {
        guard let central else { return }
        scanStop?.cancel()
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        let stop = DispatchWorkItem { [weak self] in self?.central?.stopScan() }
        scanStop = stop
        queue.asyncAfter(deadline: .now() + Self.scanWindow, execute: stop)
    }

    private func finishRead(_ p: CBPeripheral) {
        pendingReads -= 1
        central?.cancelPeripheralConnection(p)
        if pendingReads <= 0 { callbacks.gatt(Array(samples.values)) }
    }
}

extension BluetoothBatterySource: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state: State = switch central.state {
        case .poweredOn: .ready
        case .poweredOff: .poweredOff
        case .unauthorized: .unauthorized
        case .unsupported: .unsupported
        default: .unknown
        }
        callbacks.state(state)
        if central.state == .poweredOn { run() }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([CBUUID(string: GATTBattery.serviceUUID)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        finishRead(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let adv = AppleProximityAdvertisement.parse(manufacturerData: data) else { return }
        callbacks.advertisement(adv, RSSI.intValue)
    }
}

extension BluetoothBatterySource: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: GATTBattery.serviceUUID) }) else {
            finishRead(peripheral)
            return
        }
        peripheral.discoverCharacteristics([CBUUID(string: GATTBattery.levelUUID)], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard error == nil, let c = service.characteristics?.first(where: { $0.uuid == CBUUID(string: GATTBattery.levelUUID) }) else {
            finishRead(peripheral)
            return
        }
        peripheral.readValue(for: c)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        if error == nil, let data = characteristic.value, let level = GATTBattery.parseLevel(data), let name = peripheral.name {
            samples[peripheral.identifier] = GATTSample(name: name, level: level)
        }
        finishRead(peripheral)
    }
}
