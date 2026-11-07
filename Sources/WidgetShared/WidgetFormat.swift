import SwiftUI

enum WidgetFormat {
    private static let locale = Locale(identifier: "tr_TR")

    static func number(_ v: Double, digits: Int) -> String {
        v.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    /// Ondalık (SI) birimler: KB / MB / GB.
    static func bytes(_ b: UInt64) -> String {
        let v = Double(b)
        if v >= 1_000_000_000 { return number(v / 1_000_000_000, digits: v >= 10_000_000_000 ? 0 : 1) + " GB" }
        if v >= 1_000_000 { return number(v / 1_000_000, digits: v >= 100_000_000 ? 0 : 1) + " MB" }
        if v >= 1_000 { return number(v / 1_000, digits: 0) + " KB" }
        return "\(b) B"
    }

    static func rate(_ bytesPerSec: Double) -> String {
        let v = max(0, bytesPerSec)
        if v >= 1_000_000 { return number(v / 1_000_000, digits: v >= 10_000_000 ? 0 : 1) + " MB/sn" }
        if v >= 1_000 { return number(v / 1_000, digits: 0) + " KB/sn" }
        return number(v, digits: 0) + " B/sn"
    }

    static func percent(_ v: Double) -> String { "%" + number(v.rounded(), digits: 0) }

    static func duration(minutes: Int) -> String {
        let m = max(0, minutes)
        let h = m / 60, r = m % 60
        if h == 0 { return "\(r) dk" }
        return r == 0 ? "\(h) sa" : "\(h) sa \(r) dk"
    }

    /// Mac pili durum satırı: "3 sa 12 dk kaldı", "%100'e 40 dk", "Tam şarjlı".
    static func macStatus(_ mac: WidgetSnapshot.MacEntry) -> String {
        switch mac.state {
        case .full: "Tam şarjlı"
        case .charging: mac.minutesToFull.map { "%100'e \(duration(minutes: $0))" } ?? "Şarj oluyor"
        case .pluggedNotCharging: "Takılı · şarj olmuyor"
        case .onBattery: mac.minutesToEmpty.map { "\(duration(minutes: $0)) kaldı" } ?? "Süre hesaplanıyor"
        }
    }

    static func macShortState(_ mac: WidgetSnapshot.MacEntry) -> String {
        switch mac.state {
        case .full: "Dolu"
        case .charging: "Şarjda"
        case .pluggedNotCharging: "Takılı"
        case .onBattery: "Pilde"
        }
    }

    static let staleText = "Adalmon'dan veri gelmedi"
}

/// Renkli / tek renk görünüm.
struct WidgetTint: Sendable {
    var appearance: WidgetAppearance

    func battery(level: Int?, charging: Bool) -> Color {
        guard appearance == .color else { return .primary }
        if charging { return .green }
        guard let level else { return .gray }
        if level <= 10 { return .red }
        if level <= 20 { return .orange }
        return .green
    }

    func tint(_ color: Color) -> Color { appearance == .color ? color : .primary }

    /// Kota doluluğu: 80 üstü turuncu, 100 üstü kırmızı.
    func quota(_ fraction: Double) -> Color {
        guard appearance == .color else { return .primary }
        if fraction >= 1 { return .red }
        if fraction >= 0.8 { return .orange }
        return .green
    }

    /// 0...100 yük göstergesi (CPU, RAM): 85 üstü kırmızı, 65 üstü turuncu.
    func load(_ percent: Double, base: Color) -> Color {
        guard appearance == .color else { return .primary }
        if percent >= 85 { return .red }
        if percent >= 65 { return .orange }
        return base
    }
}
