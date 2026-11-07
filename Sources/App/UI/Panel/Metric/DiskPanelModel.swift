import SwiftUI

struct DiskPanelModel: Equatable {
    var hasData: Bool
    var freeText: String
    var totalText: String
    var usedFraction: Double
    var usedText: String
    var readText: String
    var writeText: String
    var readSeries: PanelSeries
    var writeSeries: PanelSeries
    var writers: [TopProcess]

    static func make(_ data: PanelData, writers: [TopProcess]) -> DiskPanelModel {
        let d = data.snapshot?.disk
        let read = PanelSeries(values: data.samples.map(\.diskRead), times: data.samples.map(\.time), format: .rate)
        let write = PanelSeries(values: data.samples.map(\.diskWrite), times: data.samples.map(\.time), format: .rate)
        let used = d.map { $0.totalBytes >= $0.availableBytes ? $0.totalBytes - $0.availableBytes : 0 }
        return DiskPanelModel(
            hasData: d != nil,
            freeText: d.map { Format.gigabytes($0.availableBytes) } ?? "—",
            totalText: d.map { Format.gigabytes($0.totalBytes) } ?? "—",
            usedFraction: d?.usedFraction ?? 0,
            usedText: used.map { Format.gigabytes($0) } ?? "—",
            readText: Format.rate(d?.readBytesPerSecond ?? 0),
            writeText: Format.rate(d?.writeBytesPerSecond ?? 0),
            readSeries: read, writeSeries: write, writers: writers)
    }
}
