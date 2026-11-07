import Foundation

/// Oynatıcıya verilen kaynak: dosya + (biliniyorsa) süre. Süre yoksa motor dosyadan okur.
struct LoopSource: Equatable, Sendable {
    var url: URL
    var duration: Double?
}

/// Süresi çözülmüş, kırpılmış aralığı hesaplanmış klip.
struct LoopClip: Equatable, Sendable {
    var url: URL
    var range: LoopTiming.Range
}
