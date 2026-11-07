import Foundation

enum BatteryFormat {
    private static let locale = Locale(identifier: "tr_TR")

    /// "2:15" (saat:dakika).
    static func clock(_ minutes: Int) -> String {
        let m = max(0, minutes)
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }

    /// "3 sa 12 dk", "40 dk", "2 sa".
    static func long(_ minutes: Int) -> String {
        let m = max(0, minutes)
        let h = m / 60, r = m % 60
        if h == 0 { return "\(r) dk" }
        return r == 0 ? "\(h) sa" : "\(h) sa \(r) dk"
    }

    /// Panel büyük satırı: "Şarj oluyor · %100'e 0:40", "Pil · 3 sa 12 dk kaldı", "Tam şarjlı".
    static func statusLine(_ r: BatteryReading) -> String {
        switch r.state {
        case .full: return "Tam şarjlı"
        case .charging:
            if let t = r.timeToFullMinutes { return "Şarj oluyor · %100'e \(clock(t))" }
            return "Şarj oluyor · süre hesaplanıyor"
        case .pluggedNotCharging: return "Güç adaptörü bağlı · şarj olmuyor"
        case .onBattery:
            if let t = r.timeToEmptyMinutes { return "Pil · \(long(t)) kaldı" }
            return "Pil · süre hesaplanıyor"
        }
    }

    /// Menü çubuğu: pilde "2:15", şarjda "0:40"; bilinmiyorsa nil.
    static func menuBarTime(_ r: BatteryReading) -> String? {
        switch r.state {
        case .charging: r.timeToFullMinutes.map(clock)
        case .onBattery: r.timeToEmptyMinutes.map(clock)
        default: nil
        }
    }

    /// Uyarı balonu: "%15 kaldı · 9 dk".
    static func lowMessage(level: Int, minutes: Int?) -> String {
        "%\(level) kaldı" + (minutes.map { " · \(long($0))" } ?? "")
    }

    static func watts(_ w: Double?) -> String {
        guard let w else { return "—" }
        return abs(w).formatted(.number.precision(.fractionLength(abs(w) < 10 ? 1 : 0)).locale(locale)) + " W"
    }

    static func int(_ v: Int?) -> String {
        guard let v else { return "—" }
        return v.formatted(.number.locale(locale))
    }

    static func mAh(_ v: Int?) -> String { v.map { int($0) + " mAh" } ?? "—" }

    static func temp(_ c: Double?) -> String {
        guard let c else { return "—" }
        return c.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " °C"
    }

    static func percent(_ v: Int?) -> String { v.map { "%\($0)" } ?? "—" }

    enum TemperatureStatus: Equatable { case cool, normal, warm, hot

        var title: String {
            switch self {
            case .cool: "Serin"
            case .normal: "Normal"
            case .warm: "Ilık"
            case .hot: "Sıcak"
            }
        }
    }

    static func temperatureStatus(_ c: Double?) -> TemperatureStatus? {
        guard let c else { return nil }
        switch c {
        case ..<20: return .cool
        case ..<35: return .normal
        case ..<40: return .warm
        default: return .hot
        }
    }

    /// Son tam şarj ifadesi: "bugün 10:36", "dün 10:36", "5 Kas 10:36".
    static func relativeDay(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(.dateTime.hour().minute().locale(locale))
        if calendar.isDate(date, inSameDayAs: now) { return "bugün \(time)" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { return "dün \(time)" }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(locale)) + " " + time
    }
}
