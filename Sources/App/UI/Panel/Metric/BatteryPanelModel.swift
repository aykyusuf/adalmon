import SwiftUI

/// Pil paneli içeriği (Juicy tarzı ayrıntılı panel). Saf: `BatteryReading` + son yenileme zamanı.
struct BatteryPanelModel: Equatable {
    var level: Int
    var tint: Color
    var charging: Bool
    var statusTitle: String
    /// "DOLANA KADAR" / "BOŞALANA KADAR" / "TAM ŞARJLI".
    var untilLabel: String
    var untilValue: String

    var healthText: String
    var healthWord: String
    var healthTint: Color
    var healthFraction: Double
    var healthNote: String?
    var cyclesText: String
    var cycleFraction: Double

    var celsiusText: String
    var fahrenheitText: String
    var temperatureStatus: String
    var temperatureNote: String
    var temperatureTint: Color

    var powerText: String
    var voltageText: String
    var voltageNote: String
    var currentText: String
    var currentDirection: CurrentDirection
    var chargingStateText: String

    var isPluggedIn: Bool
    var flowSourceText: String
    var flowCenterText: String
    var flowNote: String
    var flowUsage: String
    var chargerText: String
    var cableText: String
    var macTakesText: String

    var remainingText: String
    var currentFullText: String
    var designText: String
    var updatedText: String

    var lowPowerMode: Bool

    enum CurrentDirection: Equatable { case charging, discharging, idle }

    static func make(_ r: BatteryReading, lastRefresh: Date?, now: Date = .now) -> BatteryPanelModel {
        let f = PowerFlowSummary(r)
        let tint = BatteryPalette.tint(r)
        let health = r.primaryHealthPercent
        let tempStatus = BatteryFormat.temperatureStatus(r.temperatureC)

        let (untilLabel, untilValue): (String, String) = switch r.state {
        case .full: ("TAM ŞARJLI", "∞")
        case .charging: ("DOLANA KADAR", r.timeToFullMinutes.map(BatteryFormat.clock) ?? "…")
        case .pluggedNotCharging: ("ŞARJ OLMUYOR", "∞")
        case .onBattery: ("BOŞALANA KADAR", r.timeToEmptyMinutes.map(BatteryFormat.clock) ?? "…")
        }
        let statusTitle: String = switch r.state {
        case .full: "Tam şarjlı"
        case .charging: "Şarj oluyor"
        case .pluggedNotCharging: "Takılı, şarj olmuyor"
        case .onBattery: "Pil kullanılıyor"
        }
        let amps = r.amperageMA
        let direction: CurrentDirection = (amps ?? 0) > 20 ? .charging : ((amps ?? 0) < -20 ? .discharging : .idle)
        let chargingState: String = switch r.state {
        case .charging: "Şarj oluyor"
        case .full: "Şarj olmuyor"
        case .pluggedNotCharging: "Şarj olmuyor"
        case .onBattery: "Deşarj oluyor"
        }
        let voltage = r.voltageMV.map { Double($0) / 1000 }
        let sysW = r.systemPowerW
        let usage: String = {
            guard let w = sysW else { return "Güç ölçülemiyor" }
            if w < 8 { return "Hafif kullanım: web ve belgeler" }
            if w < 20 { return "Orta kullanım: tarayıcı ve uygulamalar" }
            return "Yoğun kullanım: derleme, video, oyun"
        }()
        let flowNote: String = switch r.state {
        case .full: "Pil dolu"
        case .charging: "Pil şarj oluyor" + (r.chargeRateW.map { $0 > 0.05 ? " · \(BatteryFormat.watts($0))" : "" } ?? "")
        case .pluggedNotCharging: "Mac adaptörden çalışıyor"
        case .onBattery: "Mac pilden çalışıyor"
        }
        return BatteryPanelModel(
            level: r.level, tint: tint, charging: r.isCharging, statusTitle: statusTitle,
            untilLabel: untilLabel, untilValue: untilValue,
            healthText: health.map { "%\($0)" } ?? "—",
            healthWord: health.map { $0 >= 80 ? "İyi" : ($0 >= 70 ? "Orta" : "Zayıf") } ?? "—",
            healthTint: BatteryPalette.healthTint(health),
            healthFraction: Double(health ?? 0) / 100,
            healthNote: r.rawHealthPercent.flatMap { raw in r.appleMaxCapacityPercent != nil ? "ham %\(raw)" : nil },
            cyclesText: "\(BatteryFormat.int(r.cycles))/\(BatteryFormat.int(r.cycleLimit))",
            cycleFraction: min(1, Double(r.cycles ?? 0) / Double(max(1, r.cycleLimit))),
            celsiusText: BatteryFormat.temp(r.temperatureC),
            fahrenheitText: r.temperatureC.map { ($0 * 9 / 5 + 32).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "tr_TR"))) + " °F" } ?? "—",
            temperatureStatus: tempStatus?.title ?? "Okunamıyor",
            temperatureNote: Self.temperatureNote(tempStatus),
            temperatureTint: BatteryPalette.tempTint(r.temperatureC),
            powerText: BatteryFormat.watts(sysW),
            voltageText: voltage.map { $0.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "tr_TR"))) + " V" } ?? "—",
            voltageNote: voltage.map { $0 >= 9 && $0 <= 13.8 ? "Normal voltaj" : "Olağandışı voltaj" } ?? "—",
            currentText: amps.map { "\(BatteryFormat.int(abs($0))) mA" } ?? "—",
            currentDirection: direction,
            chargingStateText: chargingState,
            isPluggedIn: r.isPluggedIn,
            flowSourceText: r.isPluggedIn ? f.adapterWatts : "Pil",
            flowCenterText: f.macWatts,
            flowNote: flowNote, flowUsage: usage,
            chargerText: r.isPluggedIn ? f.adapterWatts : "—",
            cableText: r.isPluggedIn ? f.cableTitle : "—",
            macTakesText: f.macWatts,
            remainingText: BatteryFormat.mAh(r.rawCurrentMAh),
            currentFullText: BatteryFormat.mAh(r.rawMaxMAh),
            designText: BatteryFormat.mAh(r.designMAh),
            updatedText: updatedText(lastRefresh ?? r.timestamp, now: now),
            lowPowerMode: r.lowPowerMode)
    }

    static func temperatureNote(_ s: BatteryFormat.TemperatureStatus?) -> String {
        switch s {
        case .cool: "Serin: kapasite geçici düşebilir"
        case .normal: "Optimum performans"
        case .warm: "Ilık: yük altında normal"
        case .hot: "Sıcak: şarj yavaşlayabilir"
        case nil: "Sensör okunamıyor"
        }
    }

    /// "az önce", "3 dk önce", "2 sa önce".
    static func updatedText(_ date: Date, now: Date) -> String {
        let s = Int(max(0, now.timeIntervalSince(date)))
        if s < 10 { return "az önce" }
        if s < 60 { return "\(s) sn önce" }
        if s < 3600 { return "\(s / 60) dk önce" }
        return "\(s / 3600) sa önce"
    }
}
