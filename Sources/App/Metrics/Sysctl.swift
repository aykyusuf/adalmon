import Foundation

/// `sysctlbyname` için küçük, ayırım yapmayan okuyucu.
enum Sysctl {
    /// Sabit boyutlu bir değeri (Int32, Int64, xsw_usage …) `value` içine okur. Başarısızsa false döner.
    static func read<T>(_ name: String, into value: inout T) -> Bool {
        var size = MemoryLayout<T>.size
        return withUnsafeMutableBytes(of: &value) { sysctlbyname(name, $0.baseAddress, &size, nil, 0) == 0 }
    }

    static func int32(_ name: String) -> Int32? {
        var value: Int32 = 0
        return read(name, into: &value) ? value : nil
    }

    static func uint64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        return read(name, into: &value) ? value : nil
    }
}
