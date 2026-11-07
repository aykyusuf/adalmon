import Foundation

/// Veri bekleyen bir listenin durumu. Saf mantık (testli): satır varsa her zaman `loaded`; yoksa yüklenirken `loading`
/// (en çok `timeout` sn, sonra "boş" gösterilir ki iskelet sonsuza dek kalmasın), yüklenmiş ve boşsa `empty`.
enum ListLoadState: Equatable, Sendable {
    case loading, empty, loaded

    /// İskeletin en uzun görüneceği süre (sn).
    static let timeout: TimeInterval = 6

    static func resolve(isLoading: Bool, itemCount: Int, timedOut: Bool = false) -> ListLoadState {
        if itemCount > 0 { return .loaded }
        return isLoading && !timedOut ? .loading : .empty
    }
}
