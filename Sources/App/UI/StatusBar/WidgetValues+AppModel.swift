import Foundation

extension WidgetValues {
    /// Uygulama modelinin güncel durumundan değerleri toplar.
    @MainActor
    init(model: AppModel) {
        let s = model.snapshot
        let connection: ConnectionState = model.path.medium == .offline ? .offline : (model.isMobile ? .mobile : .online)
        self.init(cpu: s?.cpu.total ?? 0, gpu: s?.gpu?.displayLoad,
                  memory: s?.memory.usedFraction ?? 0, disk: s?.disk.usedFraction ?? 0,
                  up: s?.network.uploadBytesPerSecond ?? 0, down: s?.network.downloadBytesPerSecond ?? 0,
                  cpuHistory: model.cpuHistory, gpuHistory: model.gpuHistory, memHistory: model.memHistory,
                  upHistory: model.upHistory, downHistory: model.downHistory,
                  mobileUsed: model.mobileToday, mobileCap: model.prefs.dailyCapBytes, connection: connection,
                  downLast60: model.downLast60, upLast60: model.upLast60,
                  downToday: model.downToday, upToday: model.upToday,
                  temperature: s?.temperature,
                  temperatureHistory: TemperatureHistory.shared.record(s))
        battery = model.battery.reading.map(BatteryGlyphState.init)
        let pinned = Set(model.prefs.menuBar.config.components.compactMap(\.deviceID))
        if !pinned.isEmpty {
            devices = Dictionary(model.devices.devices.filter { pinned.contains($0.id) }.map { ($0.id, BatteryGlyphState(device: $0)) },
                                 uniquingKeysWith: { a, _ in a })
        }
        if let s {
            memTotal = s.memory.totalBytes
            memUsed = s.memory.usedBytes
            swapUsed = s.memory.swapUsedBytes
            swapTotal = s.memory.swapTotalBytes
            pressure = s.memory.pressure
            diskTotal = s.disk.totalBytes
            diskFree = s.disk.availableBytes
            diskRead = s.disk.readBytesPerSecond
            diskWrite = s.disk.writeBytesPerSecond
            gpuMemory = s.gpu?.memoryUsedBytes
        }
    }
}
