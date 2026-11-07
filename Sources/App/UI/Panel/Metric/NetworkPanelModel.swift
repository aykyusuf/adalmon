import SwiftUI

struct NetworkPanelModel: Equatable {
    var downText: String
    var upText: String
    var downSeries: PanelSeries
    var upSeries: PanelSeries
    var todayDown: String
    var todayUp: String
    var interfaceName: String
    var connectionTitle: String

    static func make(_ data: PanelData) -> NetworkPanelModel {
        let n = data.snapshot?.network
        let times = data.samples.map(\.time)
        return NetworkPanelModel(
            downText: Format.rate(n?.downloadBytesPerSecond ?? 0),
            upText: Format.rate(n?.uploadBytesPerSecond ?? 0),
            downSeries: PanelSeries(values: data.samples.map(\.down), times: times, format: .rate),
            upSeries: PanelSeries(values: data.samples.map(\.up), times: times, format: .rate),
            todayDown: Format.bytes(data.downToday),
            todayUp: Format.bytes(data.upToday),
            interfaceName: data.interfaceName,
            connectionTitle: data.isMobile ? "Mobil veri" : (data.medium == .wifi ? "Wi-Fi" : "Kablolu"))
    }
}
