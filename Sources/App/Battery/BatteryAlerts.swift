import Foundation

enum BatteryAlertPresentation: String, Codable, CaseIterable, Identifiable, Sendable {
    case bubbleCenter, bubbleTop, edgeGlow, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bubbleCenter: "Ekran ortası"
        case .bubbleTop: "Ekran üstü"
        case .edgeGlow: "Kenar parlaması"
        case .none: "Görsel yok"
        }
    }
}

/// Bir uyarının nasıl gösterileceği.
struct BatteryAlertAction: Codable, Equatable, Sendable {
    var enabled = true
    var presentation: BatteryAlertPresentation = .bubbleCenter
    /// Sistem sesi adı (NSSound(named:)); nil = sessiz.
    var sound: String? = "Glass"
    var notification = false

    init(enabled: Bool = true, presentation: BatteryAlertPresentation = .bubbleCenter, sound: String? = "Glass", notification: Bool = false) {
        self.enabled = enabled
        self.presentation = presentation
        self.sound = sound
        self.notification = notification
    }

    private enum CodingKeys: String, CodingKey { case enabled, presentation, sound, notification }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        presentation = (try? c.decodeIfPresent(BatteryAlertPresentation.self, forKey: .presentation)) ?? .bubbleCenter
        sound = try c.decodeIfPresent(String.self, forKey: .sound)
        notification = try c.decodeIfPresent(Bool.self, forKey: .notification) ?? false
    }
}

struct BatteryAlertThreshold: Codable, Equatable, Identifiable, Sendable {
    var value: Int
    var action: BatteryAlertAction
    var id: Int { value }
}

struct BatteryAlertConfig: Codable, Equatable, Sendable {
    var enabled = true
    var low: [BatteryAlertThreshold] = [
        .init(value: 20, action: .init(presentation: .bubbleCenter, sound: "Glass")),
        .init(value: 10, action: .init(presentation: .edgeGlow, sound: "Sosumi", notification: true)),
        .init(value: 5, action: .init(presentation: .edgeGlow, sound: "Basso", notification: true)),
    ]
    var charged: [BatteryAlertThreshold] = [
        .init(value: 80, action: .init(enabled: false, presentation: .bubbleTop, sound: "Pop")),
        .init(value: 100, action: .init(presentation: .bubbleTop, sound: "Hero")),
    ]
    var pluggedIn = BatteryAlertAction(enabled: false, presentation: .bubbleTop, sound: "Pop")
    var unplugged = BatteryAlertAction(enabled: false, presentation: .bubbleTop, sound: "Pop")

    static let allowedRange = 1...100

    mutating func addLow(_ value: Int) {
        guard Self.allowedRange.contains(value), !low.contains(where: { $0.value == value }) else { return }
        low.append(.init(value: value, action: .init()))
        low.sort { $0.value > $1.value }
    }

    mutating func addCharged(_ value: Int) {
        guard Self.allowedRange.contains(value), !charged.contains(where: { $0.value == value }) else { return }
        charged.append(.init(value: value, action: .init(presentation: .bubbleTop, sound: "Hero")))
        charged.sort { $0.value < $1.value }
    }
}

struct BatteryAlertEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case low(Int)
        case charged(Int)
        case pluggedIn
        case unplugged
    }

    var kind: Kind
    var level: Int
    var minutes: Int?
    var action: BatteryAlertAction

    var title: String {
        switch kind {
        case .low: "Pil azaldı"
        case .charged(let t): t >= 100 ? "Pil doldu" : "Pil %\(t)'e ulaştı"
        case .pluggedIn: "Şarj aleti takıldı"
        case .unplugged: "Şarj aleti çıkarıldı"
        }
    }

    /// Balon metni: "%15 kaldı · 9 dk".
    var message: String {
        switch kind {
        case .low: BatteryFormat.lowMessage(level: level, minutes: minutes)
        case .charged(let t): t >= 100 ? "%100 · tam şarjlı" : "%\(level) · şarj oluyor"
        case .pluggedIn: "%\(level)" + (minutes.map { " · %100'e \(BatteryFormat.clock($0))" } ?? "")
        case .unplugged: "%\(level)" + (minutes.map { " · \(BatteryFormat.long($0)) kaldı" } ?? "")
        }
    }

    var isLow: Bool { if case .low = kind { true } else { false } }
    var isCritical: Bool { if case .low(let t) = kind { t <= 10 } else { false } }
}

/// Eşik geçişleri: histerezisli, tekrar spam yok; uyku sonrası birden çok eşik atlanırsa yalnız en şiddetlisi bildirilir.
struct BatteryAlertEngine: Sendable {
    static let hysteresis = 3

    private var firedLow: Set<Int> = []
    private var firedCharged: Set<Int> = []
    private var lastPlugged: Bool?

    init() {}

    mutating func evaluate(_ r: BatteryReading, config: BatteryAlertConfig) -> [BatteryAlertEvent] {
        let plugged = r.isPluggedIn
        defer { lastPlugged = plugged }
        guard config.enabled else {
            // Kapalıyken de durumu izle ki açılınca sahte uyarı gelmesin.
            absorb(r)
            return []
        }
        var events: [BatteryAlertEvent] = []

        if let last = lastPlugged, last != plugged {
            let action = plugged ? config.pluggedIn : config.unplugged
            if plugged { firedLow.removeAll() } else { firedCharged.removeAll() }
            if action.enabled {
                events.append(BatteryAlertEvent(kind: plugged ? .pluggedIn : .unplugged, level: r.level,
                                                minutes: plugged ? r.timeToFullMinutes : r.timeToEmptyMinutes, action: action))
            }
        }

        // Yeniden silahlanma.
        firedLow = firedLow.filter { r.level <= $0 + Self.hysteresis && !plugged }
        firedCharged = firedCharged.filter { r.level >= $0 - Self.hysteresis && plugged }

        if lastPlugged == nil { absorb(r); return events }  // açılışta zaten eşik altındaysa susturulur

        if !plugged {
            let crossed = config.low.filter { r.level <= $0.value && !firedLow.contains($0.value) }
            firedLow.formUnion(crossed.map(\.value))
            if let worst = crossed.filter(\.action.enabled).min(by: { $0.value < $1.value }) {
                events.append(BatteryAlertEvent(kind: .low(worst.value), level: r.level, minutes: r.timeToEmptyMinutes, action: worst.action))
            }
        } else {
            let reached = config.charged.filter { (r.level >= $0.value || (r.isFullyCharged && $0.value >= 100)) && !firedCharged.contains($0.value) }
            firedCharged.formUnion(reached.map(\.value))
            if let top = reached.filter(\.action.enabled).max(by: { $0.value < $1.value }) {
                events.append(BatteryAlertEvent(kind: .charged(top.value), level: r.level, minutes: nil, action: top.action))
            }
        }
        return events
    }

    /// Eşiklerin altındaki/üstündeki mevcut durumu "ateşlenmiş" sayar (olay üretmez).
    private mutating func absorb(_ r: BatteryReading) {
        // Eşik değerleri bilinmediği için 1...100 aralığı işaretlenir; histerezis kendiliğinden temizler.
        if r.isPluggedIn {
            firedLow = []
            firedCharged = Set((1...100).filter { r.level >= $0 || (r.isFullyCharged && $0 >= 100) })
        } else {
            firedCharged = []
            firedLow = Set((1...100).filter { r.level <= $0 })
        }
    }
}
