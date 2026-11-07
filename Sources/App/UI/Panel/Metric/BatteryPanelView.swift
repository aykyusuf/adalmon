import SwiftUI

/// Pil paneli: üstte kahraman kart; altında açılıp kapanan kartlar (Pil bilgisi, enerji kullanan uygulamalar, bağlı cihazlar)
/// ve eylem kartı (Ayarlar, Pil ayarları, Düşük Güç Modu, Çık).
struct BatteryPanelView: View {
    /// Düşük güç modu: yardımcı kuruluysa değiştirilebilir, değilse yalnızca durum gösterilir.
    enum LowPowerControl: Equatable { case readOnly, toggle }

    let model: BatteryPanelModel
    let apps: [BatteryEnergyApp]
    let devices: [DeviceBattery]
    let lowPowerControl: LowPowerControl
    @Binding var config: PanelConfig
    let actions: PanelActions
    let opensMainWindow: Bool
    var maxHeight: CGFloat?
    var pinnedDeviceIDs: Set<String> = []
    var appsLoading = false
    var devicesLoading = false
    /// Menü çubuğundaki cihaz öğesinden açıldıysa o cihaz: bölüm açılır, satır ortalanıp vurgulanır.
    var focusDeviceID: String?

    var body: some View {
        PanelScaffold(kind: .battery, actions: actions, opensMainWindow: opensMainWindow, subtitle: model.statusTitle, spacing: 8,
                      scrollTarget: focusDeviceID.map { "device.\($0)" }, maxHeight: maxHeight) {
            BatteryHeroCard(model: model)
            PanelCollapsibleCard(id: "battery.info", title: "Pil bilgisi", symbol: "info", tint: .cyan, config: $config,
                                 defaultCollapsed: true) { EmptyView() } content: {
                BatteryInfoBlocks(model: model, actions: actions)
            }
            BatteryEnergyAppsCard(apps: apps, isLoading: appsLoading, config: $config, actions: actions)
            BatteryDevicesCard(devices: devices, pinnedIDs: pinnedDeviceIDs, isLoading: devicesLoading, focusID: focusDeviceID,
                               config: $config, actions: actions)
            BatteryActionsCard(lowPowerControl: lowPowerControl, lowPowerOn: model.lowPowerMode, actions: actions)
        } footer: { EmptyView() }
    }
}
