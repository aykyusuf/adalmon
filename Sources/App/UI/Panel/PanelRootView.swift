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
            default:
                PanelKindView(kind: session.kind, data: data, live: live, config: $store.config, actions: actions,
                              battery: BatteryPanelSource(model: model), maxHeight: session.maxHeight)
            }
        }
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

    @MainActor
    init(model: AppModel) {
        reading = model.battery.reading
        lastRefresh = model.battery.lastRefreshAt
        apps = model.battery.energyApps
        devices = model.devices.visibleDevices
        let helper = ChargingModel.shared
        lowPowerControl = helper.featureEnabled && helper.installState.isEnabled && helper.status != nil ? .toggle : .readOnly
    }

    init(reading: BatteryReading?, lastRefresh: Date? = nil, apps: [BatteryEnergyApp] = [], devices: [DeviceBattery] = [],
         lowPowerControl: BatteryPanelView.LowPowerControl = .readOnly) {
        self.reading = reading
        self.lastRefresh = lastRefresh
        self.apps = apps
        self.devices = devices
        self.lowPowerControl = lowPowerControl
    }
}
