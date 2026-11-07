import Foundation

/// Güç akışı şemasındaki düğüm kimliği.
enum FlowNodeID: Hashable, Sendable {
    case adapter, mac, battery
    case device(String)
}

/// Renk anlamı (görünüm `Color`'a çevirir; model SwiftUI'dan bağımsız kalır).
enum FlowTint: Equatable, Sendable { case green, blue, orange, red, teal, gray }

struct FlowNode: Equatable, Identifiable, Sendable {
    enum LabelSide: Sendable { case above, below }

    var id: FlowNodeID
    var title: String
    /// Büyük değer: "70 W", "36 W", "%78".
    var value: String
    /// Küçük açıklama: "MagSafe", "Mac", "şarj oluyor".
    var caption: String
    var symbol: String
    var isActive: Bool
    /// Yalnız pil düğümü: simge doluluğu (0...100).
    var level: Int?
    /// Izgara konumu: sütun -1 (sol) / 0 (orta) / 1 (sağ); satır 0 (üst) / 1 (alt).
    var column: Int
    var row: Int
    var isCharging = false
    var tint: FlowTint
    var tooltip: String

    /// Üst satırda etiket dairenin üstünde, alt satırda altında durur.
    var labelSide: LabelSide { row == 0 ? .above : .below }
}

/// Güç akışı düğümü olmayan (görüntü-yalnız ya da çekişi bilinmeyen) bağlı aksesuar: diyagramın altında küçük çip.
struct FlowChip: Equatable, Identifiable, Sendable {
    var id: String
    var symbol: String
    var title: String
    var tooltip: String
}

struct FlowEdge: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable { case adapterToMac, adapterToBattery, batteryToMac, macToDevice }

    var id: String
    var kind: Kind
    var from: FlowNodeID
    var to: FlowNodeID
    /// nil: bilinmiyor (ölçülemeyen aksesuar).
    var watts: Double?
    /// Yaklaşık ("≈"): ölçüm değil, ayrılan güç.
    var isApproximate = false
    /// Akış var mı (eşik üstü). Pasif kenar gri ve durağan çizilir.
    var isActive: Bool
    var label: String
    var tint: FlowTint
    var tooltip: String

    /// Çizgi kalınlığı (pt): watt'ın log ölçeği.
    var thickness: Double { FlowScale.thickness(watts: watts ?? 0) }
    /// Noktaların hızı (pt/sn).
    var speed: Double { isActive ? FlowScale.speed(watts: watts ?? 0) : 0 }
    /// Noktalar arası boşluk (pt).
    var dotSpacing: Double { 8 + thickness * 2.2 }
}

/// Watt → görsel ölçek. Log: 1 W ile 100 W birbirinden ayırt edilir, 100 W üstü sabit.
enum FlowScale {
    static let maxWatts = 100.0

    /// 0...1.
    static func norm(watts: Double) -> Double {
        let w = max(0, watts)
        return min(1, log10(1 + w) / log10(1 + maxWatts))
    }

    static func thickness(watts: Double) -> Double { 1.5 + 3.5 * norm(watts: watts) }
    static func speed(watts: Double) -> Double { 16 + 64 * norm(watts: watts) }
}

/// Güç akışının saf modeli: `BatteryReading` (+ aksesuarlar) → düğümler, yönlü kenarlar, bölünme.
/// Kaynaklar: adaptör → Mac (+ pil), pil → Mac, Mac → aksesuar. Mac düğümü SystemLoad'dır; USB aksesuarlarının çektiği güç
/// zaten onun içindedir, bu yüzden aksesuar kenarları Mac'ten çıkar (toplama eklenmez).
struct PowerFlowModel: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        /// Fişte, pil şarj oluyor: adaptör → Mac + adaptör → pil.
        case pluggedCharging
        /// Fişte, pil dolu/şarj olmuyor: adaptör → Mac.
        case pluggedIdle
        /// Fişte ama adaptör yetmiyor: adaptör → Mac + pil → Mac.
        case pluggedSupplementing
        /// Pilde: pil → Mac.
        case onBattery
    }

    /// Bu eşiğin altı (W) "boşta" sayılır; pil kenarı titremesin.
    static let idleWatts = 0.3
    static let maxDevices = 2

    var mode: Mode
    var nodes: [FlowNode]
    var edges: [FlowEdge]
    /// Düğüm olmayan bağlı aksesuarlar (diyagramın altında çip).
    var chips: [FlowChip] = []
    /// VoiceOver özeti.
    var summary: String

    var hasDeviceNodes: Bool { nodes.contains { $0.column > 0 } }
    var hasMotion: Bool { edges.contains { $0.isActive } }
    func node(_ id: FlowNodeID) -> FlowNode? { nodes.first { $0.id == id } }
    func edge(_ kind: FlowEdge.Kind) -> FlowEdge? { edges.first { $0.kind == kind } }
    var deviceEdges: [FlowEdge] { edges.filter { $0.kind == .macToDevice } }

    // MARK: Hesap

    /// Pil gücü (W, işaretli: + şarj, − deşarj). Yön IsCharging/akım işaretinden, büyüklük telemetriden.
    static func signedBatteryWatts(_ r: BatteryReading) -> Double {
        let telemetry = r.batteryPowerW.map(abs)
        let vi: Double? = {
            guard let v = r.voltageMV, let a = r.amperageMA else { return nil }
            return abs(Double(v) * Double(a) / 1_000_000)
        }()
        let magnitude = (telemetry.flatMap { $0 > 0 ? $0 : nil }) ?? vi ?? 0
        if r.isCharging { return magnitude }
        if let b = r.batteryPowerW, abs(b) >= idleWatts { return b }
        if let a = r.amperageMA, a <= -20 { return -magnitude }
        if let a = r.amperageMA, a >= 20 { return magnitude }
        return 0
    }

    /// Adaptörden sisteme giren güç (W): SystemPowerIn, yoksa V × A.
    static func adapterOutWatts(_ r: BatteryReading) -> Double? {
        if let w = r.systemPowerW { return max(0, w) }
        if let v = r.systemVoltageInMV, let a = r.systemCurrentInMA { return max(0, Double(v) * Double(a) / 1_000_000) }
        return nil
    }

    static func make(_ r: BatteryReading, deviceLevels: [DeviceBattery] = []) -> PowerFlowModel {
        let plugged = r.isPluggedIn
        let batt = signedBatteryWatts(r)
        let charging = batt > idleWatts
        let supplementing = plugged && batt < -idleWatts
        let adapterOut = plugged ? adapterOutWatts(r) : nil

        // Mac yükü: SystemLoad → SystemPowerIn − şarj → |pil| (pilde) → V×A.
        let load: Double? = {
            if let l = r.systemLoadMW { return max(0, Double(l) / 1000) }
            if plugged, let a = adapterOut { return max(0, a - max(0, batt) + max(0, -batt)) }
            if !plugged, batt < -idleWatts { return -batt }
            return adapterOutWatts(r)
        }()

        let mode: Mode = !plugged ? .onBattery : (supplementing ? .pluggedSupplementing : (charging ? .pluggedCharging : .pluggedIdle))

        var edges: [FlowEdge] = []
        func fmt(_ w: Double?) -> String { w.map { BatteryFormat.watts($0) } ?? "—" }
        func edge(_ kind: FlowEdge.Kind, _ from: FlowNodeID, _ to: FlowNodeID, _ w: Double?, _ tint: FlowTint, _ tip: String,
                  approx: Bool = false, id: String? = nil) -> FlowEdge {
            let active = (w ?? 0) >= idleWatts
            return FlowEdge(id: id ?? kind.rawValue, kind: kind, from: from, to: to, watts: w, isApproximate: approx, isActive: active,
                            label: (approx ? "≈" : "") + (w == nil ? "?" : fmt(w)), tint: active ? tint : .gray, tooltip: tip)
        }

        switch mode {
        case .pluggedCharging, .pluggedIdle:
            let toMac = load ?? adapterOut
            edges.append(edge(.adapterToMac, .adapter, .mac, toMac, .green, "Adaptör → Mac: \(fmt(toMac))"))
            if mode == .pluggedCharging {
                edges.append(edge(.adapterToBattery, .adapter, .battery, batt, .blue, "Adaptör → pil (şarj): \(fmt(batt))"))
            }
        case .pluggedSupplementing:
            let toMac = adapterOut ?? max(0, (load ?? 0) + batt)
            edges.append(edge(.adapterToMac, .adapter, .mac, toMac, .green, "Adaptör → Mac: \(fmt(toMac))"))
            edges.append(edge(.batteryToMac, .battery, .mac, -batt, .orange,
                              "Pil → Mac: \(fmt(-batt)). Adaptör Mac'in ihtiyacına yetmiyor, fark pilden geliyor."))
        case .onBattery:
            let w = load ?? (batt < 0 ? -batt : nil)
            edges.append(edge(.batteryToMac, .battery, .mac, w, .orange, "Pil → Mac: \(fmt(w))"))
        }

        // Aksesuarlar: ölçülemez; ayrılan güç varsa "≈". Pozisyon: sağ sütun.
        // Yalnız Mac'ten ayrılan gücü bilinen aygıtlar düğüm olur; görüntü-yalnız ya da çekişi bilinmeyenler çip olur ("?" kenarı yok).
        let sinks = r.accessories.filter(\.drawsKnownPower)
        let shown = Array(sinks.prefix(maxDevices))
        let extra = sinks.count - shown.count
        var deviceNodes: [FlowNode] = []
        for (i, a) in shown.enumerated() {
            let w = a.allocatedMW.map { Double($0) / 1000 }
            let id = FlowNodeID.device(a.id)
            let level = deviceLevels.first { $0.kind == .iPhone || $0.kind == .iPad }.flatMap { a.kind == .phone ? $0.level : nil }
            var tip = "\(a.name) · \(a.portName)"
            if !a.detail.isEmpty { tip += "\n\(a.detail)" }
            if let w { tip += "\nAyrılan güç ≈ \(BatteryFormat.watts(w)) (USB ayrılan akım × 5 V). Gerçek çekiş değil." }
            if a.kind == .phone, let level { tip += "\nPil: %\(level)" }
            let e = edge(.macToDevice, .mac, id, w, .teal, tip, approx: true, id: "device." + a.id)
            edges.append(e)
            deviceNodes.append(FlowNode(
                id: id, title: a.name, value: "≈" + BatteryFormat.watts(w),
                caption: (a.kind == .phone && level != nil ? "%\(level!) · " : "") + a.portName + (i == shown.count - 1 && extra > 0 ? " +\(extra)" : ""),
                symbol: deviceSymbol(a.kind), isActive: e.isActive, level: nil, column: 1, row: i, tint: e.isActive ? .teal : .gray, tooltip: tip))
        }

        let chips: [FlowChip] = r.accessories.filter { !$0.drawsKnownPower }.map { a in
            var tip = "\(a.name) · \(a.portName)"
            if !a.detail.isEmpty { tip += "\n\(a.detail)" }
            tip += a.isDisplayOnly ? "\nYalnız görüntü bağlantısı: Mac'ten güç çektiği bilinmiyor." : "\nApple Silicon bu portun çektiği gücü göstermiyor."
            return FlowChip(id: a.id, symbol: deviceSymbol(a.kind), title: a.name + " · " + a.portName, tooltip: tip)
        }

        let nodes = [adapterNode(r, mode: mode, out: adapterOut), macNode(r, load: load, adapterOut: adapterOut),
                     batteryNode(r, batt: batt, mode: mode)] + deviceNodes
        let summary = Self.summary(mode: mode, adapterOut: adapterOut, load: load, batt: batt, level: r.level, devices: shown.count, chips: chips)
        return PowerFlowModel(mode: mode, nodes: nodes, edges: edges, chips: chips, summary: summary)
    }

    static func deviceSymbol(_ k: PowerPortAccessory.Kind) -> String {
        switch k {
        case .phone: "iphone"
        case .storage: "externaldrive.fill"
        case .display: "display"
        case .hub: "cable.connector.horizontal"
        case .other: "cable.connector"
        }
    }

    // MARK: Düğümler

    private static func adapterNode(_ r: BatteryReading, mode: Mode, out: Double?) -> FlowNode {
        let plugged = r.isPluggedIn
        let rated = r.adapterLabelWatts
        let symbol = r.cable == .magSafe ? "magsafe.batterypack" : (r.cable == .wireless ? "wave.3.right" : "powerplug.fill")
        var tip = ""
        if plugged {
            tip = r.adapterDisplayName ?? "Güç adaptörü"
            if let rated { tip += "\nAnma gücü: \(rated) W" }
            var contract: [String] = []
            if let v = r.adapterVoltageMV { contract.append(volts(v)) }
            if let a = r.adapterCurrentMA { contract.append(amps(a)) }
            if let v = r.adapterVoltageMV, let a = r.adapterCurrentMA {
                tip += "\nSözleşme: \(volts(v)) × \(amps(a)) (\(BatteryFormat.watts(Double(v) * Double(a) / 1_000_000)))"
            } else if !contract.isEmpty { tip += "\nSözleşme: " + contract.joined(separator: " × ") }
            tip += "\nKablo/port: \(r.cable.title)" + (r.adapterPortName.map { " · \($0)" } ?? "")
            if let out { tip += "\nŞu an verdiği: \(BatteryFormat.watts(out))" }
            if let loss = r.adapterEfficiencyLossMW, loss > 0 {
                let l = Double(loss) / 1000
                tip += "\nAdaptör kaybı: \(BatteryFormat.watts(l))"
                if let out, out + l > 0 { tip += " (verim %\(Int((out / (out + l) * 100).rounded())))" }
            }
        } else {
            tip = "Güç adaptörü takılı değil"
        }
        return FlowNode(id: .adapter, title: "Adaptör", value: plugged ? (rated.map { "\($0) W" } ?? "—") : "—",
                        caption: plugged ? r.cable.title : "Fiş yok", symbol: symbol, isActive: plugged, level: nil,
                        column: -1, row: 0, tint: plugged ? .green : .gray, tooltip: tip)
    }

    private static func macNode(_ r: BatteryReading, load: Double?, adapterOut: Double?) -> FlowNode {
        var tip = "Mac'in tükettiği güç: \(BatteryFormat.watts(load))"
        if r.isPluggedIn, let v = r.systemVoltageInMV, let a = r.systemCurrentInMA {
            tip += "\nGiriş: \(volts(v)) × \(amps(a))"
        }
        if !r.accessories.isEmpty { tip += "\nBağlı USB aksesuarların çektiği güç bu değerin içindedir." }
        return FlowNode(id: .mac, title: "Mac", value: load.map { BatteryFormat.watts($0) } ?? "—", caption: "Mac", symbol: "laptopcomputer",
                        isActive: (load ?? 0) >= idleWatts, level: nil, column: 0, row: 0, tint: .orange, tooltip: tip)
    }

    private static func batteryNode(_ r: BatteryReading, batt: Double, mode: Mode) -> FlowNode {
        let state: String = switch mode {
        case .pluggedCharging: "şarj oluyor"
        case .onBattery: "boşalıyor"
        case .pluggedSupplementing: "adaptöre yardım"
        case .pluggedIdle: r.state == .full ? "dolu" : "şarj olmuyor"
        }
        var tip = "Pil %\(r.level) · \(state)"
        if abs(batt) >= idleWatts { tip += " · \(BatteryFormat.watts(batt))" }
        if let v = r.voltageMV { tip += "\nVoltaj: \(volts(v))" }
        if let a = r.amperageMA { tip += " · Akım: \(BatteryFormat.int(abs(a))) mA" }
        return FlowNode(id: .battery, title: "Pil", value: "%\(r.level)", caption: state, symbol: "battery.100percent",
                        isActive: abs(batt) >= idleWatts, level: r.level, column: 0, row: 1, isCharging: mode == .pluggedCharging,
                        tint: batteryTint(level: r.level, charging: mode == .pluggedCharging, full: r.state == .full), tooltip: tip)
    }

    /// Pil rengi: şarj olurken/doluyken yeşil; düşükte turuncu; kritikte kırmızı; aksi halde yeşil.
    static func batteryTint(level: Int, charging: Bool, full: Bool) -> FlowTint {
        if charging || full { return .green }
        if level <= 10 { return .red }
        if level <= 20 { return .orange }
        return .green
    }

    static func volts(_ mV: Int) -> String {
        (Double(mV) / 1000).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "tr_TR"))) + " V"
    }

    static func amps(_ mA: Int) -> String {
        (Double(mA) / 1000).formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "tr_TR"))) + " A"
    }

    private static func summary(mode: Mode, adapterOut: Double?, load: Double?, batt: Double, level: Int, devices: Int, chips: [FlowChip]) -> String {
        let mac = BatteryFormat.watts(load)
        var s: String
        switch mode {
        case .pluggedCharging: s = "Adaptör \(BatteryFormat.watts(adapterOut)) veriyor: Mac'e \(mac), pile \(BatteryFormat.watts(batt))."
        case .pluggedIdle: s = "Adaptör Mac'e \(mac) veriyor; pil dolu ya da şarj olmuyor."
        case .pluggedSupplementing: s = "Adaptör \(BatteryFormat.watts(adapterOut)) veriyor, Mac \(mac) çekiyor; fark \(BatteryFormat.watts(-batt)) pilden geliyor."
        case .onBattery: s = "Mac pilden \(mac) çekiyor, pil %\(level)."
        }
        if devices > 0 { s += " \(devices) bağlı aksesuar." }
        if !chips.isEmpty { s += " Bağlı: " + chips.map(\.title).joined(separator: ", ") + "." }
        return s
    }
}
