import Foundation

/// Kaynaklardan gelen gözlemleri cihaz başına tek `DeviceBattery`'ye indirir.
/// Kimlik: normalize edilmiş ad (GATT UUID, HID adresi ve lockdown UDID birbirine eşlenemediği için ortak alan ad).
enum DeviceMerger {
    /// Bu süreden eski gözlem "bayat" sayılır ve "~" ile gösterilir.
    static let staleAfter: TimeInterval = 15 * 60
    /// Bu süreden eski, bağlı olmayan cihaz listeden düşer.
    static let forgetAfter: TimeInterval = 7 * 86_400

    static func identity(_ name: String) -> String {
        name.replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func merge(_ readings: [DeviceReading], now: Date = .now) -> [DeviceBattery] {
        var groups: [String: [DeviceReading]] = [:]
        for r in readings where r.hasAnyLevel && !r.name.trimmingCharacters(in: .whitespaces).isEmpty {
            groups[identity(r.name), default: []].append(r)
        }
        var out: [DeviceBattery] = []
        for (id, list) in groups {
            func isFresh(_ r: DeviceReading) -> Bool { now.timeIntervalSince(r.observedAt) <= staleAfter }
            // Kazanan: taze olanlar içinde en yüksek öncelik (eşitse yeni), taze yoksa en yeni.
            let sorted = list.sorted { a, b in
                let fa = isFresh(a), fb = isFresh(b)
                if fa != fb { return fa }
                if fa && a.source.priority != b.source.priority { return a.source.priority > b.source.priority }
                return a.observedAt > b.observedAt
            }
            guard let win = sorted.first else { continue }
            var d = DeviceBattery(id: id, name: win.name.trimmingCharacters(in: .whitespaces), kind: win.kind, level: win.level, left: win.left,
                                  right: win.right, caseLevel: win.caseLevel, leftCharging: win.leftCharging, rightCharging: win.rightCharging,
                                  caseCharging: win.caseCharging, isCharging: win.isCharging, isConnected: win.isConnected,
                                  lastSeen: win.observedAt, sources: [])
            // Eksik alanları diğer gözlemlerden tamamla (ör. yayından kulaklar, önbellekten kutu).
            var filledFromLowerSource = false
            for other in sorted.dropFirst() {
                if d.kind == .other, other.kind != .other { d.kind = other.kind }
                if d.level == nil, let v = other.level { d.level = v; filledFromLowerSource = filledFromLowerSource || other.source.isApproximate }
                if d.left == nil, let v = other.left { d.left = v; d.leftCharging = other.leftCharging; filledFromLowerSource = filledFromLowerSource || other.source.isApproximate }
                if d.right == nil, let v = other.right { d.right = v; d.rightCharging = other.rightCharging; filledFromLowerSource = filledFromLowerSource || other.source.isApproximate }
                if d.caseLevel == nil, let v = other.caseLevel { d.caseLevel = v; d.caseCharging = other.caseCharging; filledFromLowerSource = filledFromLowerSource || other.source.isApproximate }
            }
            d.isStale = !isFresh(win)
            d.isApproximate = win.source.isApproximate || d.isStale || filledFromLowerSource
            d.sources = Array(Set(list.map(\.source))).sorted { $0.priority > $1.priority }
            // Bağlı sayılması: taze, bağlı bir gözlem var.
            d.isConnected = list.contains { isFresh($0) && $0.isConnected && $0.source != .systemCache }
            d.lastSeen = list.filter { $0.source != .systemCache || !isFresh(win) }.map(\.observedAt).max() ?? win.observedAt
            if now.timeIntervalSince(d.lastSeen) > forgetAfter, !d.isConnected { continue }
            out.append(d)
        }
        return sort(out)
    }

    /// En düşük pil üstte; bilinmeyen en altta; eşitlikte ada göre.
    static func sort(_ devices: [DeviceBattery]) -> [DeviceBattery] {
        devices.sorted { a, b in
            switch (a.summaryLevel, b.summaryLevel) {
            case let (x?, y?) where x != y: return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }
}
