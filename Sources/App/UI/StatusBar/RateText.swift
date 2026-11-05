import Foundation

/// Hız ve miktar metnini sayı ve birim sütunlarına böler: "18,4 MB/s" → ("18,4", "MB/s").
enum RateText {
    static let widestNumber = "888,8"
    static let widestRateUnit = "MB/s"
    static let widestAmountUnit = "MB"
    static let widestShortUnit = "M"
    private static let locale = Locale(identifier: "tr_TR")

    static func parts(_ bytesPerSecond: Double, showUnits: Bool) -> (number: String, unit: String) {
        let s = Format.rate(bytesPerSecond)
        guard let space = s.lastIndex(of: " ") else { return (s, "") }
        let number = String(s[..<space])
        let unit = String(s[s.index(after: space)...])
        return (number, showUnits ? unit : String(unit.prefix(1)))
    }

    /// Toplam miktar: "640 MB", "4,3 GB" (sayı en fazla 5 karakter).
    static func amountParts(_ bytes: UInt64, showUnits: Bool) -> (number: String, unit: String) {
        let v = Double(bytes)
        let (value, unit): (Double, String) = switch v {
        case ..<1_000: (v, "B")
        case ..<1_000_000: (v / 1_000, "KB")
        case ..<1_000_000_000: (v / 1_000_000, "MB")
        default: (v / 1_000_000_000, "GB")
        }
        let digits = value < 100 && unit != "B" && unit != "KB" ? 1 : 0
        let number = value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
        return (number, showUnits ? unit : String(unit.prefix(1)))
    }
}
