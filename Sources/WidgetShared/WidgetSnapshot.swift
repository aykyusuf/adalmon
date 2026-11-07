import Foundation

/// Uygulama ile widget eklentisi arasındaki sabitler. İki hedefe de derlenir.
enum WidgetShared {
    static let appGroupID = "BC62U5TGCQ.com.yusufayik.adalmon"
    static let snapshotFileName = "widget-snapshot.json"
    static let schemaVersion = 1
    /// Bu süreden eski veri "Adalmon'dan veri gelmedi" ile işaretlenir.
    static let staleAfter: TimeInterval = 15 * 60

    enum Kind {
        static let allBatteries = "AdalmonAllBatteries"
        static let macBattery = "AdalmonMacBattery"
        static let system = "AdalmonSystem"
        static let mobileQuota = "AdalmonMobileQuota"
        static let all = [allBatteries, macBattery, system, mobileQuota]
    }

    static var snapshotURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?.appending(path: snapshotFileName)
    }
}

/// Widget'ların okuduğu küçük JSON özeti. Alanlar geriye dönük uyumlu okunur (eksik alan → varsayılan).
struct WidgetSnapshot: Codable, Equatable, Sendable {
    var schemaVersion = WidgetShared.schemaVersion
    var generatedAt: Date
    var mac: MacEntry?
    var devices: [DeviceEntry] = []
    /// Menü çubuğuna sabitlenmiş cihaz kimlikleri (sıralı).
    var pinnedDeviceIDs: [String] = []
    var system: SystemEntry?

    enum MacState: String, Codable, Sendable { case charging, onBattery, full, pluggedNotCharging }

    struct MacEntry: Codable, Equatable, Sendable {
        var level: Int
        var state: MacState
        var minutesToEmpty: Int?
        var minutesToFull: Int?
        var healthPercent: Int?
        var cycles: Int?
        var cycleLimit: Int?
        var temperatureC: Double?
        var adapterWatts: Int?
        var powerW: Double?
        var lowPowerMode = false

        var isCharging: Bool { state == .charging }

        init(level: Int, state: MacState, minutesToEmpty: Int? = nil, minutesToFull: Int? = nil, healthPercent: Int? = nil, cycles: Int? = nil,
             cycleLimit: Int? = nil, temperatureC: Double? = nil, adapterWatts: Int? = nil, powerW: Double? = nil, lowPowerMode: Bool = false) {
            self.level = level; self.state = state; self.minutesToEmpty = minutesToEmpty; self.minutesToFull = minutesToFull
            self.healthPercent = healthPercent; self.cycles = cycles; self.cycleLimit = cycleLimit; self.temperatureC = temperatureC
            self.adapterWatts = adapterWatts; self.powerW = powerW; self.lowPowerMode = lowPowerMode
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            level = try c.decode(Int.self, forKey: .level)
            state = (try? c.decodeIfPresent(MacState.self, forKey: .state)) ?? .onBattery
            minutesToEmpty = try c.decodeIfPresent(Int.self, forKey: .minutesToEmpty)
            minutesToFull = try c.decodeIfPresent(Int.self, forKey: .minutesToFull)
            healthPercent = try c.decodeIfPresent(Int.self, forKey: .healthPercent)
            cycles = try c.decodeIfPresent(Int.self, forKey: .cycles)
            cycleLimit = try c.decodeIfPresent(Int.self, forKey: .cycleLimit)
            temperatureC = try c.decodeIfPresent(Double.self, forKey: .temperatureC)
            adapterWatts = try c.decodeIfPresent(Int.self, forKey: .adapterWatts)
            powerW = try c.decodeIfPresent(Double.self, forKey: .powerW)
            lowPowerMode = try c.decodeIfPresent(Bool.self, forKey: .lowPowerMode) ?? false
        }
    }

    struct DeviceEntry: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var name: String
        var symbol: String
        var level: Int?
        var isCharging = false
        var isApproximate = false
        var isConnected = true
        var lastSeen: Date

        init(id: String, name: String, symbol: String, level: Int? = nil, isCharging: Bool = false, isApproximate: Bool = false,
             isConnected: Bool = true, lastSeen: Date) {
            self.id = id; self.name = name; self.symbol = symbol; self.level = level; self.isCharging = isCharging
            self.isApproximate = isApproximate; self.isConnected = isConnected; self.lastSeen = lastSeen
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
            symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "dot.radiowaves.left.and.right"
            level = try c.decodeIfPresent(Int.self, forKey: .level)
            isCharging = try c.decodeIfPresent(Bool.self, forKey: .isCharging) ?? false
            isApproximate = try c.decodeIfPresent(Bool.self, forKey: .isApproximate) ?? false
            isConnected = try c.decodeIfPresent(Bool.self, forKey: .isConnected) ?? true
            lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen) ?? .distantPast
        }
    }

    struct SystemEntry: Codable, Equatable, Sendable {
        var cpuPercent: Double
        var ramPercent: Double
        var downBytesPerSec: Double
        var upBytesPerSec: Double
        var mobileTodayBytes: UInt64
        var dailyCapBytes: UInt64
        var cycleUsedBytes: UInt64?
        var monthlyCapBytes: UInt64?
        var isOnMobile = false

        init(cpuPercent: Double, ramPercent: Double, downBytesPerSec: Double, upBytesPerSec: Double, mobileTodayBytes: UInt64,
             dailyCapBytes: UInt64, cycleUsedBytes: UInt64? = nil, monthlyCapBytes: UInt64? = nil, isOnMobile: Bool = false) {
            self.cpuPercent = cpuPercent; self.ramPercent = ramPercent; self.downBytesPerSec = downBytesPerSec
            self.upBytesPerSec = upBytesPerSec; self.mobileTodayBytes = mobileTodayBytes; self.dailyCapBytes = dailyCapBytes
            self.cycleUsedBytes = cycleUsedBytes; self.monthlyCapBytes = monthlyCapBytes; self.isOnMobile = isOnMobile
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            cpuPercent = try c.decodeIfPresent(Double.self, forKey: .cpuPercent) ?? 0
            ramPercent = try c.decodeIfPresent(Double.self, forKey: .ramPercent) ?? 0
            downBytesPerSec = try c.decodeIfPresent(Double.self, forKey: .downBytesPerSec) ?? 0
            upBytesPerSec = try c.decodeIfPresent(Double.self, forKey: .upBytesPerSec) ?? 0
            mobileTodayBytes = try c.decodeIfPresent(UInt64.self, forKey: .mobileTodayBytes) ?? 0
            dailyCapBytes = try c.decodeIfPresent(UInt64.self, forKey: .dailyCapBytes) ?? 0
            cycleUsedBytes = try c.decodeIfPresent(UInt64.self, forKey: .cycleUsedBytes)
            monthlyCapBytes = try c.decodeIfPresent(UInt64.self, forKey: .monthlyCapBytes)
            isOnMobile = try c.decodeIfPresent(Bool.self, forKey: .isOnMobile) ?? false
        }

        var dailyFraction: Double { dailyCapBytes == 0 ? 0 : Double(mobileTodayBytes) / Double(dailyCapBytes) }
        var monthlyFraction: Double? {
            guard let cap = monthlyCapBytes, cap > 0, let used = cycleUsedBytes else { return nil }
            return Double(used) / Double(cap)
        }
    }

    init(generatedAt: Date, mac: MacEntry? = nil, devices: [DeviceEntry] = [], pinnedDeviceIDs: [String] = [], system: SystemEntry? = nil) {
        self.generatedAt = generatedAt
        self.mac = mac
        self.devices = devices
        self.pinnedDeviceIDs = pinnedDeviceIDs
        self.system = system
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, generatedAt, mac, devices, pinnedDeviceIDs, system }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        mac = try? c.decodeIfPresent(MacEntry.self, forKey: .mac)
        devices = (try? c.decodeIfPresent([DeviceEntry].self, forKey: .devices)) ?? []
        pinnedDeviceIDs = (try? c.decodeIfPresent([String].self, forKey: .pinnedDeviceIDs)) ?? []
        system = try? c.decodeIfPresent(SystemEntry.self, forKey: .system)
    }

    func isStale(at now: Date) -> Bool { now.timeIntervalSince(generatedAt) > WidgetShared.staleAfter }

    /// Zaman damgaları hariç aynı içerik mi (gereksiz yazma/yenileme olmasın).
    func hasSameContent(as other: WidgetSnapshot) -> Bool {
        func strip(_ s: WidgetSnapshot) -> WidgetSnapshot {
            var c = s
            c.generatedAt = .distantPast
            c.devices = c.devices.map { var d = $0; d.lastSeen = .distantPast; return d }
            return c
        }
        return strip(self) == strip(other)
    }

    // MARK: Kodlama

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    func encoded() throws -> Data { try Self.encoder().encode(self) }
    static func decode(_ data: Data) throws -> WidgetSnapshot { try decoder().decode(WidgetSnapshot.self, from: data) }
}

/// Dosya okuma/yazma. Yazma atomik (yarım dosya görülmez).
enum WidgetSnapshotStore {
    static func read(from url: URL? = WidgetShared.snapshotURL) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? WidgetSnapshot.decode(data)
    }

    @discardableResult
    static func write(_ snapshot: WidgetSnapshot, to url: URL? = WidgetShared.snapshotURL) -> Bool {
        guard let url, let data = try? snapshot.encoded() else { return false }
        do {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

extension WidgetSnapshot {
    /// Önizleme ve ilk widget galerisi için örnek veri.
    static func sample(now: Date = .now) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now,
            mac: MacEntry(level: 78, state: .onBattery, minutesToEmpty: 192, minutesToFull: nil, healthPercent: 86, cycles: 178,
                          cycleLimit: 1000, temperatureC: 31.4, adapterWatts: nil, powerW: 15.8),
            devices: [
                DeviceEntry(id: "yusuf iphone", name: "iPhone", symbol: "iphone", level: 79, lastSeen: now),
                DeviceEntry(id: "airpods", name: "AirPods Pro", symbol: "airpodspro", level: 70, isApproximate: true, lastSeen: now),
                DeviceEntry(id: "keyboard", name: "Magic Keyboard", symbol: "keyboard", level: 18, lastSeen: now),
                DeviceEntry(id: "ipad", name: "iPad", symbol: "ipad", level: 56, isCharging: true, lastSeen: now),
                DeviceEntry(id: "mouse", name: "Magic Mouse", symbol: "magicmouse", level: 9, lastSeen: now),
                DeviceEntry(id: "watch", name: "Apple Watch", symbol: "applewatch", level: 64, isConnected: false, lastSeen: now.addingTimeInterval(-7200)),
            ],
            pinnedDeviceIDs: ["yusuf iphone", "airpods"],
            system: SystemEntry(cpuPercent: 23, ramPercent: 61, downBytesPerSec: 1_240_000, upBytesPerSec: 86_000,
                                mobileTodayBytes: 1_260_000_000, dailyCapBytes: 3_000_000_000,
                                cycleUsedBytes: 9_400_000_000, monthlyCapBytes: 30_000_000_000, isOnMobile: true))
    }
}
