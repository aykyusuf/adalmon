import SwiftUI

/// Panel penceresindeki kök görünüm: `PanelSession.kind`'a göre birleşik panel ya da metriğin kendi paneli.
/// Yalnızca panel açıkken var olur. Veri her ölçüm adımında `PanelData(model:)` ile okunur.
struct PanelRootView: View {
    let model: AppModel
    let session: PanelSession
    let live: PanelLiveSources
    let actions: PanelActions
    var onSizeChange: (CGSize) -> Void = { _ in }

    var body: some View {
        @Bindable var store = model.prefs.panel
        let data = PanelData(model: model)
        Group {
            switch session.kind {
            case .combined:
                PanelContent(data: data, config: $store.config, actions: actions, maxHeight: session.maxHeight)
            case .agents:
                AgentsPanelView(monitor: model.agents.monitor, limits: model.agents.limits, actions: actions, opensMainWindow: data.opensMainWindow,
                                maxHeight: session.maxHeight)
            default:
                PanelKindView(kind: session.kind, data: data, live: live, config: $store.config, actions: actions,
                              battery: BatteryPanelSource(model: model), maxHeight: session.maxHeight,
                              focusDeviceID: session.focusDeviceID)
            }
        }
        .panelSurface(store.config.background)
        .id(session.kind)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
    }
}

/// Pil panelinin model dışı girdileri (okuma, uygulamalar, cihazlar, düşük güç modu denetimi).
struct BatteryPanelSource {
    var reading: BatteryReading?
    var lastRefresh: Date?
    var apps: [BatteryEnergyApp] = []
    var devices: [DeviceBattery] = []
    var lowPowerControl: BatteryPanelView.LowPowerControl = .readOnly
    /// Menü çubuğuna sabitlenmiş cihaz kimlikleri.
    var pinnedDeviceIDs: Set<String> = []
    /// Enerji kullanan uygulamalar / cihazlar ilk kez okunana kadar true (iskelet gösterilir).
    var appsLoading = false
    var devicesLoading = false

    @MainActor
    init(model: AppModel) {
        reading = model.battery.reading
        lastRefresh = model.battery.lastRefreshAt
        apps = model.battery.energyApps
        devices = model.devices.visibleDevices
        pinnedDeviceIDs = Set(model.prefs.menuBar.config.components.compactMap(\.deviceID))
        appsLoading = !model.battery.energyAppsLoaded
        devicesLoading = model.prefs.deviceMonitoring && model.devices.lastUpdated == nil
        lowPowerControl = .readOnly
    }

    init(reading: BatteryReading?, lastRefresh: Date? = nil, apps: [BatteryEnergyApp] = [], devices: [DeviceBattery] = [],
         lowPowerControl: BatteryPanelView.LowPowerControl = .readOnly, pinnedDeviceIDs: Set<String> = [],
         appsLoading: Bool = false, devicesLoading: Bool = false) {
        self.pinnedDeviceIDs = pinnedDeviceIDs
        self.appsLoading = appsLoading
        self.devicesLoading = devicesLoading
        self.reading = reading
        self.lastRefresh = lastRefresh
        self.apps = apps
        self.devices = devices
        self.lowPowerControl = lowPowerControl
    }
}
