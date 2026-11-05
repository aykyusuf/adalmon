import Foundation

/// Sayı biçimlendirme yardımcıları (Türkçe, ondalık ayırıcı virgül).
enum Format {
    private static let locale = Locale(identifier: "tr_TR")

    /// 1.234.567 → "1,2 MB"
    static func bytes(_ b: UInt64) -> String {
        Int64(clamping: b).formatted(.byteCount(style: .decimal).locale(locale))
    }

    /// Sabit genişlikte hız metni: "  0 KB/s", "12,4 MB/s"
    static func rate(_ bytesPerSecond: Double) -> String {
        let v = max(0, bytesPerSecond)
        switch v {
        case ..<1_000: return "\(Int(v)) B/s"
        case ..<1_000_000: return "\(Int(v / 1_000)) KB/s"
        case ..<100_000_000: return (v / 1_000_000).formatted(.number.precision(.fractionLength(1)).locale(locale)) + " MB/s"
        default: return "\(Int(v / 1_000_000)) MB/s"
        }
    }

    static func percent(_ fraction: Double) -> String {
        "%\(Int((max(0, min(1, fraction)) * 100).rounded()))"
    }

    /// MHz → "1,1 GHz".
    static func gigahertz(_ megahertz: Double) -> String {
        (max(0, megahertz) / 1_000).formatted(.number.precision(.fractionLength(1)).locale(locale)) + " GHz"
    }

    static func gigabytes(_ b: UInt64) -> String {
        (Double(b) / 1_000_000_000).formatted(.number.precision(.fractionLength(1)).locale(locale)) + " GB"
    }
}
