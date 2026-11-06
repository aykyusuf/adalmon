import Foundation

/// Bir aralık için yüklenmiş grafik verisi.
struct HistoryContent: Equatable, Sendable {
    var bars: [HistoryBar]
    /// Sayfa başlığı altındaki dönem adı: "Bugün", "30 Eki – 5 Kas" vb.
    var periodTitle: String

    var totalMobile: UInt64 { bars.reduce(0) { $0 + $1.mobile } }
    var totalOther: UInt64 { bars.reduce(0) { $0 + $1.other } }
    var isEmpty: Bool { bars.allSatisfy { $0.total == 0 } }

    /// Varsayılan seçim: verisi olan son çubuk.
    var defaultSelection: String? { bars.last { $0.total > 0 }?.id }

    static let empty = HistoryContent(bars: [], periodTitle: "")
}
