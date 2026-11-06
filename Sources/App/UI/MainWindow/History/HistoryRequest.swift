import Foundation

/// `.task(id:)` anahtarı: aralık, sayfa ve yenileme sayacı değişince grafik yeniden okunur.
struct HistoryRequest: Equatable {
    var range: HistoryRange
    var offset: Int
    var reload: Int
}
