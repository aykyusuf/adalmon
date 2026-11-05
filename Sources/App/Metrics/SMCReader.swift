import Foundation
import IOKit

// AppleSMC okuyucu (yalnızca okuma). Apple'ın belgelenmiş bir API'si yok; protokol şu açık kaynak
// projelerdeki uygulamayla aynı (satırlar 2026-11-05 tarihli commit'lere sabitlendi):
//
// exelban/Stats @ d51378c2238d1c4148792a914b220d6ca1eca466
// - SMCKeyData_t düzeni (padding: UInt16 dahil, stride 80):
//   https://github.com/exelban/stats/blob/d51378c2238d1c4148792a914b220d6ca1eca466/SMC/smc.swift#L56-L99
// - Komutlar kernelIndex=2, readBytes=5, readIndex=8, readKeyInfo=9:
//   https://github.com/exelban/stats/blob/d51378c2238d1c4148792a914b220d6ca1eca466/SMC/smc.swift#L36-L44
// - IOServiceMatching("AppleSMC") + IOServiceOpen:
//   https://github.com/exelban/stats/blob/d51378c2238d1c4148792a914b220d6ca1eca466/SMC/smc.swift#L172-L186
// - IOConnectCallStructMethod(conn, 2, &input, stride, &output, &stride):
//   https://github.com/exelban/stats/blob/d51378c2238d1c4148792a914b220d6ca1eca466/SMC/smc.swift#L716-L721
// - M4 GPU anahtarları Tg0G, Tg0H (M4), Tg1U, Tg1k (M4 Pro/Max), Tg0K, Tg0L, Tg0d, Tg0e, Tg0j, Tg0k (tüm M4):
//   https://github.com/exelban/stats/blob/d51378c2238d1c4148792a914b220d6ca1eca466/Modules/Sensors/values.swift#L493-L518
//   M3 GPU = Tf14...Tf2A (L484-L491), M5 GPU = Tg0U, Tg0X, Tg0d, Tg0g, Tg0j, Tg1Y, Tg1c, Tg1g (L524-L552).
//
// vladkens/macmon @ 39e98aa73e49256e6281b2a228f6ef3499ae3209
// - KeyData yapısı: https://github.com/vladkens/macmon/blob/39e98aa73e49256e6281b2a228f6ef3499ae3209/src/sources.rs#L1471-L1488
// - read (selector 2, result 132 = anahtar yok):
//   https://github.com/vladkens/macmon/blob/39e98aa73e49256e6281b2a228f6ef3499ae3209/src/sources.rs#L1534-L1558
// - key info (data8=9) / indeksle anahtar (data8=8): .../src/sources.rs#L1568-L1585
// - "flt " = 4 bayt little-endian f32: .../src/sources.rs#L1609-L1628
// - #KEY sayısı big-endian u32: .../src/sources.rs#L1631-L1637
// - GPU anahtar seçimi: tüm anahtarlar bir kez sayılır, "Tg" önekli ve flt okunabilenler GPU
//   ("Tp"/"Te"/"Ts" CPU), değerlerin ortalaması alınır:
//   https://github.com/vladkens/macmon/blob/39e98aa73e49256e6281b2a228f6ef3499ae3209/src/metrics.rs#L476-L515
//   geçerlilik 0 < t <= 150: .../src/metrics.rs#L209-L217
//
// Burada macmon yaklaşımı kullanılıyor (çipe göre sabit liste yerine "Tg" önekli flt anahtarları);
// M4/M5 varyantları için ayrı tablo gerekmiyor. M3'te GPU "Tf" önekinde olduğundan bu yol M3'te boş
// kalabilir; M1/M2/M3'te IOHID "GPU MTR Temp Sensor" zaten var ve SMC hiç çağrılmaz.

/// Stats `SMCKeyData_t` ile aynı bellek düzeni (C `SMCParamStruct`, 80 bayt).
private struct SMCKeyData {
    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    var key: UInt32 = 0
    var vers = Version()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfo()
    /// C'de KeyInfo 12 bayta hizalanır; Swift `size` (9) kullandığı için açık dolgu gerekir.
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

/// AppleSMC'den anahtar okur. Bağlantı bir kez açılır ve nesne ömrü boyunca tutulur;
/// anahtar bilgileri (tip/boyut) ve GPU anahtar listesi önbelleğe alınır.
/// Thread safety: kilit yok; yalnızca tek seri kuyruktan kullanılmalı (TemperatureSampler gibi).
final class SMCReader {
    /// Anahtar keşfi için (ölü/sabit anahtarları elemek).
    static let gpuDiscoveryRange = 10.0...110.0
    /// Sürekli okumada: yük altında 110 üstünü atmamak için daha geniş (macmon 0 < t <= 150).
    static let gpuReadRange = 5.0...130.0

    private enum Command: UInt8 {
        case readBytes = 5
        case readIndex = 8
        case readKeyInfo = 9
    }

    private static let kernelIndex: UInt32 = 2
    private static let keyNotFound: UInt8 = 132
    static let typeFloat = fourCC("flt ")
    static let typeSP78 = fourCC("sp78")
    static let typeUInt32 = fourCC("ui32")

    private let connection: io_connect_t
    private var keyInfoCache: [UInt32: SMCKeyData.KeyInfo] = [:]
    private var cachedGPUKeys: [String]?

    /// AppleSMC açılamazsa (VM, izin) nil.
    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess, conn != 0 else { return nil }
        connection = conn
    }

    deinit {
        IOServiceClose(connection)
    }

    // MARK: Public

    /// Stats values.swift'teki GPU tabloları (yukarıdaki bağlantılar). M4 MacBook'ta 18 "Tg" anahtarı
    /// bulunuyor; hepsini okumak Debug'da ~3 ms sürdü (hedef < 2 ms). Tablo eşleşirse yalnızca onlar
    /// okunur (M4'te 8 anahtar); ortalama tüm 18 anahtarın ortalamasından ~0.2 °C farklı.
    static let knownGPUKeyTables: [[String]] = [
        ["Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"], // M4 / Pro / Max (L508-L518)
        ["Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g"], // M5 (L545-L552)
    ]

    /// Okunacak GPU anahtarları. Önce "Tg" önekli, 4 baytlık "flt " tipinde ve keşif anında 10...110 °C
    /// okuyan anahtarlar bulunur (macmon yöntemi); sonra en çok eşleşen Stats tablosuyla daraltılır,
    /// hiçbiri eşleşmezse bulunanların tamamı kullanılır. İlk çağrıda ~2800 anahtar bir kez sayılır
    /// (~15-30 ms), sonra liste önbellekte.
    var gpuTemperatureKeys: [String] {
        if let cachedGPUKeys { return cachedGPUKeys }
        let keys = Self.selectGPUKeys(discovered: discoveredGPUKeys())
        cachedGPUKeys = keys
        return keys
    }

    func discoveredGPUKeys() -> [String] {
        allKeys().filter { key in
            guard key.hasPrefix("Tg"), let value = readFloat(key) else { return false }
            return Self.gpuDiscoveryRange.contains(value)
        }
    }

    static func selectGPUKeys(discovered: [String]) -> [String] {
        let available = Set(discovered)
        let best = knownGPUKeyTables
            .map { table in table.filter(available.contains) }
            .max { $0.count < $1.count } ?? []
        return best.isEmpty ? discovered : best
    }

    /// GPU anahtarı → °C (yalnızca 5...130 aralığındaki değerler). Anahtar başına tek IPC (~80 µs).
    func gpuTemperatures() -> [String: Double] {
        var result: [String: Double] = [:]
        for key in gpuTemperatureKeys {
            if let value = readFloat(key), Self.gpuReadRange.contains(value) {
                result[key] = value
            }
        }
        return result
    }

    /// `#KEY` sayısı kadar anahtarı indeksle okur.
    func allKeys() -> [String] {
        guard let count = keyCount() else { return [] }
        var keys: [String] = []
        keys.reserveCapacity(Int(count))
        for index in 0..<count {
            var input = SMCKeyData()
            input.data8 = Command.readIndex.rawValue
            input.data32 = index
            guard let output = call(&input) else { continue }
            keys.append(Self.string(fromFourCC: output.key))
        }
        return keys
    }

    func keyCount() -> UInt32? {
        guard let bytes = readBytes("#KEY"), bytes.count >= 4 else { return nil }
        return bytes[0..<4].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    /// "flt " veya "sp78" tipindeki bir anahtarı Double olarak okur; diğer tiplerde nil.
    func readFloat(_ key: String) -> Double? {
        guard let info = keyInfo(Self.fourCC(key)), let bytes = readBytes(Self.fourCC(key), info: info) else { return nil }
        return Self.decode(bytes: bytes, type: info.dataType)
    }

    // MARK: Decoding (test edilebilir)

    static func decode(bytes: [UInt8], type: UInt32) -> Double? {
        switch type {
        case typeFloat:
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        case typeSP78:
            // İşaretli 8.8 sabit nokta, big-endian.
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256
        default:
            return nil
        }
    }

    static func fourCC(_ string: String) -> UInt32 {
        string.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    static func string(fromFourCC value: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: Private

    private func readBytes(_ key: String) -> [UInt8]? {
        let code = Self.fourCC(key)
        guard let info = keyInfo(code) else { return nil }
        return readBytes(code, info: info)
    }

    private func readBytes(_ code: UInt32, info: SMCKeyData.KeyInfo) -> [UInt8]? {
        var input = SMCKeyData()
        input.key = code
        input.keyInfo.dataSize = info.dataSize
        input.data8 = Command.readBytes.rawValue
        guard let output = call(&input) else { return nil }
        let size = min(Int(info.dataSize), 32)
        return withUnsafeBytes(of: output.bytes) { Array($0.prefix(size)) }
    }

    private func keyInfo(_ code: UInt32) -> SMCKeyData.KeyInfo? {
        if let cached = keyInfoCache[code] { return cached }
        var input = SMCKeyData()
        input.key = code
        input.data8 = Command.readKeyInfo.rawValue
        guard let output = call(&input) else { return nil }
        keyInfoCache[code] = output.keyInfo
        return output.keyInfo
    }

    private func call(_ input: inout SMCKeyData) -> SMCKeyData? {
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let status = IOConnectCallStructMethod(connection, Self.kernelIndex, &input, MemoryLayout<SMCKeyData>.stride, &output, &outputSize)
        guard status == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }
}
