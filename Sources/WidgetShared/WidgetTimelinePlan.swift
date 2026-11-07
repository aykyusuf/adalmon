import Foundation

/// Widget zaman çizelgesi planı (saf; testlenir). İlk giriş şimdi; veri eskiyecekse bir de eskime anı girişi eklenir,
/// böylece uygulama hiç yenilemese bile "Adalmon'dan veri gelmedi" zamanında görünür.
struct WidgetTimelinePlan: Equatable, Sendable {
    var dates: [Date]
    var refreshAt: Date

    static func make(snapshotDate: Date?, now: Date, refreshEvery: TimeInterval = 15 * 60) -> WidgetTimelinePlan {
        var dates = [now]
        if let snapshotDate {
            let staleMoment = snapshotDate.addingTimeInterval(WidgetShared.staleAfter + 1)
            if staleMoment > now { dates.append(staleMoment) }
        }
        let refresh = now.addingTimeInterval(refreshEvery)
        return WidgetTimelinePlan(dates: dates, refreshAt: refresh)
    }
}
