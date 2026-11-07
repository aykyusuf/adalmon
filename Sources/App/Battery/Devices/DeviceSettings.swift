import Foundation

/// Cihaz başına kullanıcı ayarı (gizle, düşük pil uyarısı).
struct DeviceSettings: Codable, Equatable, Sendable {
    var hidden = false
    var alertEnabled = true
    /// Düşük pil eşikleri (yüzde), büyükten küçüğe.
    var lowThresholds: [Int] = [20, 10]
    var action = BatteryAlertAction(enabled: true, presentation: .bubbleCenter, sound: "Glass", notification: false)

    static let thresholdRange = 3...50

    mutating func addThreshold(_ value: Int) {
        guard Self.thresholdRange.contains(value), !lowThresholds.contains(value) else { return }
        lowThresholds.append(value)
        lowThresholds.sort(by: >)
    }

    init() {}

    private enum CodingKeys: String, CodingKey { case hidden, alertEnabled, lowThresholds, action }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        alertEnabled = try c.decodeIfPresent(Bool.self, forKey: .alertEnabled) ?? true
        lowThresholds = try c.decodeIfPresent([Int].self, forKey: .lowThresholds) ?? [20, 10]
        action = try c.decodeIfPresent(BatteryAlertAction.self, forKey: .action) ?? DeviceSettings().action
    }
}
