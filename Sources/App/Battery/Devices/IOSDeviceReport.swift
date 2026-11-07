import Foundation

/// "Raporu kopyala / Dosya olarak kaydet" için düz metin.
enum IOSDeviceReport {
    static func text(_ d: IOSDeviceDetails, includeSerials: Bool = true, now: Date = .now) -> String {
        var lines: [String] = []
        func add(_ title: String, _ value: String?) { lines.append(title + ": " + (value ?? "—")) }
        func mAh(_ v: Int?) -> String? { v.map { BatteryFormat.int($0) + " mAh" } }
        func temp(_ v: Double?) -> String? { v.map { BatteryFormat.temp($0) } }
        func mA(_ v: Int?) -> String? { v.map { BatteryFormat.int($0) + " mA" } }
        func mV(_ v: Int?) -> String? { v.map { String(format: "%.2f V", Double($0) / 1000).replacingOccurrences(of: ".", with: ",") } }

        lines.append("Adalmon · \(d.name) pil raporu")
        lines.append("Oluşturulma: " + now.formatted(.dateTime.day().month(.wide).year().hour().minute().locale(Locale(identifier: "tr_TR"))))
        lines.append("")
        lines.append("Cihaz")
        add("  Model", d.modelName + (d.productType.isEmpty ? "" : " (\(d.productType))"))
        add("  iOS sürümü", d.systemVersion)
        if includeSerials { add("  Seri no", d.deviceSerial) }
        add("  Bağlantı", d.connection.title)
        lines.append("")
        lines.append("Sağlık")
        add("  Maksimum kapasite", d.healthPercent.map { "%\($0)" })
        add("  Ham oran (AppleRawMax ÷ tasarım)", d.rawHealthPercent.map { "%\($0)" })
        add("  Döngü sayısı", d.cycleCount.map { BatteryFormat.int($0) })
        lines.append("")
        lines.append("Şarj")
        add("  Seviye", d.level.map { "%\($0)" })
        add("  Durum", d.isCharging ? "Şarj oluyor" : (d.fullyCharged ? "Tam şarjlı" : (d.externalConnected ? "Bağlı, şarj olmuyor" : "Pilde")))
        lines.append("")
        lines.append("Kapasite")
        add("  Tam dolu (nominal)", mAh(d.nominalMAh))
        add("  Tam dolu (ham)", mAh(d.rawMaxMAh))
        add("  Tasarım", mAh(d.designMAh))
        add("  Kalan (ham)", mAh(d.rawCurrentMAh))
        add("  Gerilim", mV(d.voltageMV))
        add("  Akım", mA(d.amperageMA))
        add("  Sıcaklık", temp(d.temperatureC))
        lines.append("")
        lines.append("Pil")
        add("  Üretici", d.manufacturer)
        add("  Hücre gerilimleri", d.cellVoltagesMV.isEmpty ? nil : d.cellVoltagesMV.map { "\($0) mV" }.joined(separator: ", "))
        add("  Şarj aleti", d.adapterWatts.map { "\($0) W" + (d.adapterName.map { " · " + $0.trimmingCharacters(in: .whitespaces) } ?? "") })
        if includeSerials { add("  Pil seri no", d.batterySerial) }
        lines.append("")
        lines.append("Ömür boyu")
        add("  Ortalama sıcaklık", temp(d.lifetimeAvgTempC))
        add("  Sıcaklık aralığı", d.lifetimeMinTempC.flatMap { lo in d.lifetimeMaxTempC.map { BatteryFormat.temp(lo) + " … " + BatteryFormat.temp($0) } })
        add("  En yüksek şarj akımı", mA(d.lifetimeMaxChargeMA))
        add("  En yüksek deşarj akımı", mA(d.lifetimeMaxDischargeMA))
        add("  Gerilim aralığı", d.lifetimeMinVoltageMV.flatMap { lo in d.lifetimeMaxVoltageMV.map { (mV(lo) ?? "") + " … " + (mV($0) ?? "") } })
        add("  Çalışma süresi", d.lifetimeOperatingHours.map { "\(BatteryFormat.int($0)) sa (\($0 / 24) gün)" })
        return lines.joined(separator: "\n")
    }

    static func fileName(_ d: IOSDeviceDetails, now: Date = .now) -> String {
        let safe = d.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(safe) pil raporu \(now.formatted(.iso8601.year().month().day())).txt"
    }
}
