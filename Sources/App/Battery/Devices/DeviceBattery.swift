import Foundation

/// Birleştirilmiş cihaz pili (arayüz, menü çubuğu ve uyarılar bunu kullanır).
struct DeviceBattery: Identifiable, Equatable, Sendable, Codable {
    /// Kalıcı kimlik: normalize edilmiş ad (`DeviceMerger.identity`).
    var id: String
    var name: String
    var kind: DeviceKind
    var level: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var leftCharging = false
    var rightCharging = false
    var caseCharging = false
    var isCharging = false
    /// "~": değer yaklaşık (reklam adımı, sistem önbelleği) ya da bayat.
    var isApproximate = false
    var isStale = false
    var isConnected = true
    var lastSeen: Date
    var sources: [DeviceSource] = []

    /// Sıralama ve uyarı için tek yüzde: kulaklıkta düşük olan kulak, diğerlerinde ana değer.
    var summaryLevel: Int? {
        if kind.hasPods, let low = [left, right].compactMap(\.self).min() { return low }
        return level ?? [left, right].compactMap(\.self).min() ?? caseLevel
    }

    var hasPodBreakdown: Bool { kind.hasPods && (left != nil || right != nil || caseLevel != nil) }

    /// "~75%" gibi kısa metin.
    var levelText: String {
        guard let l = summaryLevel else { return "—" }
        return (isApproximate ? "~" : "") + "%\(l)"
    }

    /// "5 dk önce", "dün 14:20" benzeri son görülme.
    func lastSeenText(now: Date = .now) -> String {
        if now.timeIntervalSince(lastSeen) < 90 { return "şimdi" }
        if now.timeIntervalSince(lastSeen) < 3_600 { return "\(Int(now.timeIntervalSince(lastSeen) / 60)) dk önce" }
        return BatteryFormat.relativeDay(lastSeen, now: now)
    }

    static let samples: [DeviceBattery] = {
        let now = Date.now
        return [
            DeviceBattery(id: "yusuf iphone", name: "Yusuf iPhone", kind: .iPhone, level: 79, isConnected: true, lastSeen: now, sources: [.gatt, .lockdown]),
            DeviceBattery(id: "yusuf's airpods pro", name: "Yusuf’s AirPods Pro", kind: .airPodsPro, level: 70, left: 80, right: 70, caseLevel: 40,
                          rightCharging: false, caseCharging: true, isApproximate: true, lastSeen: now.addingTimeInterval(-120), sources: [.advertisement]),
            DeviceBattery(id: "magic keyboard", name: "Magic Keyboard", kind: .keyboard, level: 18, lastSeen: now, sources: [.hid]),
            DeviceBattery(id: "yusuf ipad", name: "Yusuf iPad", kind: .iPad, level: 56, isCharging: true, lastSeen: now, sources: [.gatt]),
            DeviceBattery(id: "orochi v2", name: "Orochi V2", kind: .mouse, level: 92, isApproximate: true, isStale: true, isConnected: false,
                          lastSeen: now.addingTimeInterval(-7_200), sources: [.systemCache]),
        ]
    }()
}
