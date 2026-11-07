import SwiftUI

/// Metriğin kendi paneli: modeli kurar ve ilgili görünümü çizer.
struct PanelKindView: View {
    let kind: PanelKind
    let data: PanelData
    let live: PanelLiveSources
    @Binding var config: PanelConfig
    let actions: PanelActions
    let battery: BatteryPanelSource
    var maxHeight: CGFloat?
    var previewHover: Double?

    var body: some View {
        let opens = data.opensMainWindow
        switch kind {
        case .cpu:
            CPUPanelView(model: .make(data, processes: live.processes), isMeasuringProcesses: live.isMeasuring,
                         actions: actions, opensMainWindow: opens, maxHeight: maxHeight, previewHover: previewHover)
        case .gpu:
            GPUPanelView(model: .make(data, processes: live.processes), isMeasuringProcesses: live.isMeasuring,
                         actions: actions, opensMainWindow: opens, maxHeight: maxHeight, previewHover: previewHover)
        case .memory:
            MemoryPanelView(model: .make(data, processes: live.processes), isMeasuringProcesses: live.isMeasuring,
                            actions: actions, opensMainWindow: opens, maxHeight: maxHeight, previewHover: previewHover)
        case .disk:
            DiskPanelView(model: .make(data, writers: live.writers), actions: actions, opensMainWindow: opens,
                          maxHeight: maxHeight, previewHover: previewHover)
        case .network:
            NetworkPanelView(model: .make(data), data: data, config: $config, actions: actions, maxHeight: maxHeight, previewHover: previewHover)
        case .temperature:
            TemperaturePanelView(model: .make(data), config: $config, actions: actions, opensMainWindow: opens,
                                 maxHeight: maxHeight, previewHover: previewHover)
        case .battery:
            if let reading = battery.reading {
                BatteryPanelView(model: .make(reading, lastRefresh: battery.lastRefresh), apps: battery.apps, devices: battery.devices,
                                 lowPowerControl: battery.lowPowerControl, config: $config, actions: actions,
                                 opensMainWindow: opens, maxHeight: maxHeight)
            } else {
                PanelScaffold(kind: .battery, actions: actions, opensMainWindow: opens, maxHeight: maxHeight) {
                    PanelCard {
                        Label("Bu Mac'te dahili pil yok", systemImage: "battery.0percent").foregroundStyle(.secondary)
                    }
                    if !battery.devices.isEmpty {
                        PanelCard {
                            VStack(alignment: .leading, spacing: 8) {
                                PanelGroupTitle(title: "Cihazlar")
                                ForEach(battery.devices.prefix(8)) { DevicePanelRow(device: $0) }
                            }
                        }
                    }
                } footer: { EmptyView() }
            }
        case .combined:
            EmptyView()
        }
    }
}
