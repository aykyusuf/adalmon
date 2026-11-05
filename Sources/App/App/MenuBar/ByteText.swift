import Foundation

enum ByteText {
    static let widestAuto = ("888,8", "MB")
    static let widestMB = ("88888", "MB")
    static let widestGB = ("888,8", "GB")
    private static let locale = Locale(identifier: "tr_TR")

    static func parts(_ bytes: Double, unit: ByteUnit, binary: Bool, showUnits: Bool) -> (number: String, unit: String) {
        let base: Double = binary ? 1024 : 1000
        let v = max(0, bytes)
        let (value, name): (Double, String) = switch unit {
        case .mb: (v / (base * base), "MB")
        case .gb: (v / (base * base * base), "GB")
        case .auto:
            switch v {
            case ..<(base * base): (v / base, "KB")
            case ..<(base * base * base): (v / (base * base), "MB")
            default: (v / (base * base * base), "GB")
            }
        }
        let digits: Int = switch unit {
        case .mb: 0
        case .gb: value < 100 ? 1 : 0
        case .auto: value < 100 && name != "KB" ? 1 : 0
        }
        let number = value.formatted(.number.precision(.fractionLength(digits)).grouping(.never).locale(locale))
        return (number, showUnits ? name : String(name.prefix(1)))
    }

    static func text(_ bytes: Double, unit: ByteUnit, binary: Bool, showUnits: Bool) -> String {
        let p = parts(bytes, unit: unit, binary: binary, showUnits: showUnits)
        return p.number + " " + p.unit
    }

    static func widest(unit: ByteUnit, showUnits: Bool) -> String {
        let w = switch unit {
        case .auto: widestAuto
        case .mb: widestMB
        case .gb: widestGB
        }
        return w.0 + " " + (showUnits ? w.1 : String(w.1.prefix(1)))
    }
}
