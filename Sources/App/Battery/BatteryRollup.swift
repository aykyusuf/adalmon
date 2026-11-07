import Foundation

/// Günlük enerji kullanımı: yüzde düşüşlerinin toplamı (şarj sırasındaki artışlar ayrı sayılır).
struct BatteryEnergyTracker: Sendable, Equatable {
    struct Delta: Equatable, Sendable {
        var day: String
        var consumedPercent: Double
        var chargedPercent: Double
    }

    private var lastLevel: Int?

    init() {}

    mutating func consume(level: Int, day: String) -> Delta? {
        defer { lastLevel = level }
        guard let last = lastLevel else { return nil }
        let diff = level - last
        guard diff != 0 else { return nil }
        return Delta(day: day, consumedPercent: diff < 0 ? Double(-diff) : 0, chargedPercent: diff > 0 ? Double(diff) : 0)
    }

    /// Ardışık okuma dizisinden günlük toplam (test ve yeniden hesaplama için).
    static func totals(levels: [(day: String, level: Int)]) -> [String: Double] {
        var t = BatteryEnergyTracker()
        var out: [String: Double] = [:]
        for l in levels {
            if let d = t.consume(level: l.level, day: l.day), d.consumedPercent > 0 { out[d.day, default: 0] += d.consumedPercent }
        }
        return out
    }
}

/// Ekran açık süresi durum makinesi: ekranlar uyanık VE oturum etkin iken sayar; gün sınırlarında böler.
struct ScreenOnClock: Sendable {
    struct DaySeconds: Equatable, Sendable {
        var day: String
        var seconds: Int
    }

    private(set) var screensAwake: Bool
    private(set) var sessionActive: Bool
    private var since: Date?
    private let calendar: Calendar

    var isOn: Bool { screensAwake && sessionActive }

    init(now: Date, screensAwake: Bool = true, sessionActive: Bool = true, calendar: Calendar = UsageStore.keyCalendar) {
        self.screensAwake = screensAwake
        self.sessionActive = sessionActive
        self.calendar = calendar
        since = (screensAwake && sessionActive) ? now : nil
    }

    @discardableResult
    mutating func update(screensAwake: Bool? = nil, sessionActive: Bool? = nil, at now: Date) -> [DaySeconds] {
        let closed = flush(at: now)
        if let screensAwake { self.screensAwake = screensAwake }
        if let sessionActive { self.sessionActive = sessionActive }
        since = isOn ? now : nil
        return closed
    }

    /// Şimdiye kadar birikeni verir ve sayaca devam eder (dakikalık yazımda).
    mutating func flush(at now: Date) -> [DaySeconds] {
        guard let start = since, now > start else { return [] }
        since = now
        return Self.split(from: start, to: now, calendar: calendar)
    }

    static func split(from start: Date, to end: Date, calendar: Calendar) -> [DaySeconds] {
        var out: [DaySeconds] = []
        var cursor = start
        while cursor < end {
            let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) ?? end
            let stop = min(end, nextMidnight)
            let secs = Int(stop.timeIntervalSince(cursor).rounded())
            if secs > 0 { out.append(DaySeconds(day: UsageStore.dayKey(cursor, calendar: calendar), seconds: secs)) }
            cursor = stop
        }
        return out
    }
}
