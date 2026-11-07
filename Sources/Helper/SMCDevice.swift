import Foundation
import IOKit

/// AppleSMC'ye gerçek erişim. YALNIZCA yardımcı süreçte derlenir. Yazma yalnızca `SMCWriteAllowlist` onaylıysa yapılır.
final class SMCDevice: SMCAccessing, @unchecked Sendable {
    private struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0 }
    private typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )
    private struct Param {
        var key: UInt32 = 0
        var vers = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Command: UInt8 {
        case writeBytes = 6
        case readBytes = 5
        case readKeyInfo = 9
    }

    private let lock = NSLock()
    private var connection: io_connect_t = 0

    init() {}

    deinit { if connection != 0 { IOServiceClose(connection) } }

    // MARK: SMCAccessing

    func descriptor(of key: SMCKey) -> SMCKeyDescriptor? {
        lock.lock(); defer { lock.unlock() }
        guard let info = keyInfo(Self.code(key)) else { return nil }
        return SMCKeyDescriptor(size: Int(info.dataSize), dataType: Self.string(info.dataType))
    }

    func read(_ key: SMCKey) -> [UInt8]? {
        lock.lock(); defer { lock.unlock() }
        guard let info = keyInfo(Self.code(key)) else { return nil }
        var input = Param()
        input.key = Self.code(key)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = Command.readBytes.rawValue
        guard let output = call(&input) else { return nil }
        let size = min(Int(info.dataSize), 32)
        return withUnsafeBytes(of: output.bytes) { Array($0.prefix(size)) }
    }

    func write(_ write: SMCWrite) -> Bool {
        guard SMCWriteAllowlist.permits(write) else { return false }
        lock.lock(); defer { lock.unlock() }
        let code = Self.code(write.key)
        guard let info = keyInfo(code), Int(info.dataSize) == write.bytes.count, write.bytes.count <= 32 else { return false }
        var input = Param()
        input.key = code
        input.keyInfo.dataSize = info.dataSize
        input.data8 = Command.writeBytes.rawValue
        withUnsafeMutableBytes(of: &input.bytes) { raw in
            for (index, byte) in write.bytes.enumerated() { raw[index] = byte }
        }
        return call(&input) != nil
    }

    // MARK: Düşük seviye

    private func keyInfo(_ code: UInt32) -> KeyInfo? {
        var input = Param()
        input.key = code
        input.data8 = Command.readKeyInfo.rawValue
        guard let output = call(&input), output.keyInfo.dataSize > 0 else { return nil }
        return output.keyInfo
    }

    private func open() -> Bool {
        if connection != 0 { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess, conn != 0 else { return false }
        connection = conn
        return true
    }

    private func call(_ input: inout Param) -> Param? {
        guard open() else { return nil }
        var output = Param()
        var outputSize = MemoryLayout<Param>.stride
        let status = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<Param>.stride, &output, &outputSize)
        guard status == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    private static func code(_ key: SMCKey) -> UInt32 {
        key.rawValue.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func string(_ value: UInt32) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) }, as: UTF8.self)
    }
}
