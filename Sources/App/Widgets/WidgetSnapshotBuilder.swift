import Foundation

/// Uygulama durumundan widget özetini kurar (saf; testlenir). Değerler yuvarlanır: gereksiz değişim olmasın.
enum WidgetSnapshotBuilder {
    static func make(now: Date, battery: BatteryReading?, devices: [DeviceBattery], hiddenDeviceIDs: Set<String>,
                     pinnedDeviceIDs: [String], system: SystemSnapshot?, mobileToday: UInt64, dailyCap: UInt64,
                     cycleUsed: UInt64?, monthlyCap: UInt64?, isOnMobile: Bool) -> WidgetSnapshot {
        let mac = battery.map { r in
            WidgetSnapshot.MacEntry(
                level: r.level, state: state(r.state), minutesToEmpty: r.timeToEmptyMinutes, minutesToFull: r.timeToFullMinutes,
                healthPercent: r.primaryHealthPercent, cycles: r.cycles, cycleLimit: r.cycleLimit,
                temperatureC: r.temperatureC.map { ($0 * 10).rounded() / 10 }, adapterWatts: r.adapterLabelWatts,
                powerW: r.systemPowerW.map { ($0 * 10).rounded() / 10 }, lowPowerMode: r.lowPowerMode)
        }
        let entries = devices.filter { !hiddenDeviceIDs.contains($0.id) }.map { d in
            WidgetSnapshot.DeviceEntry(id: d.id, name: d.name, symbol: d.kind.symbol, level: d.summaryLevel, isCharging: d.isCharging,
                                       isApproximate: d.isApproximate, isConnected: d.isConnected && !d.isStale, lastSeen: d.lastSeen)
        }
        let sys = system.map { s in
            WidgetSnapshot.SystemEntry(
                cpuPercent: (s.cpu.total * 100).rounded(), ramPercent: (s.memory.usedFraction * 100).rounded(),
                downBytesPerSec: (s.network.downloadBytesPerSecond / 1000).rounded() * 1000,
                upBytesPerSec: (s.network.uploadBytesPerSecond / 1000).rounded() * 1000,
                mobileTodayBytes: mobileToday, dailyCapBytes: dailyCap, cycleUsedBytes: cycleUsed, monthlyCapBytes: monthly(monthlyCap),
                isOnMobile: isOnMobile)
        }
        return WidgetSnapshot(generatedAt: now, mac: mac, devices: entries, pinnedDeviceIDs: pinnedDeviceIDs, system: sys)
    }

    private static func monthly(_ cap: UInt64?) -> UInt64? { cap.flatMap { $0 > 0 ? $0 : nil } }

    static func state(_ s: BatteryReading.State) -> WidgetSnapshot.MacState {
        switch s {
        case .charging: .charging
        case .onBattery: .onBattery
        case .full: .full
        case .pluggedNotCharging: .pluggedNotCharging
        }
    }
}
