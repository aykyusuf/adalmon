import Foundation

/// Tek bir kaynaktan, tek bir andaki gözlem. `DeviceMerger` bunları cihaz başına tek kayda indirir.
struct DeviceReading: Equatable, Sendable {
    var name: String
    var kind: DeviceKind
    var source: DeviceSource
    var observedAt: Date
    var level: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var leftCharging = false
    var rightCharging = false
    var caseCharging = false
    var isCharging = false
    var isConnected = true

    var hasAnyLevel: Bool { level != nil || left != nil || right != nil || caseLevel != nil }
}
