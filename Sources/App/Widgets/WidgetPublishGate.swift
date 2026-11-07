import Foundation

/// Yazma/yenileme kısıtlaması (saf; testlenir).
/// - Dosya en sık 60 sn'de bir yazılır (içerik değiştiyse); değişmediyse 10 dk'da bir "nabız" yazılır ki widget eskimiş görünmesin.
/// - Tak/çıkar gibi zorunlu durumlarda hemen yazılır.
/// - `reloadTimelines` en sık 5 dk'da bir (zorunlu durumda 30 sn); yazılmış ama henüz yenilenmemiş veri süre dolunca yenilenir.
struct WidgetPublishGate {
    var writeInterval: TimeInterval = 60
    var heartbeatInterval: TimeInterval = 600
    var reloadInterval: TimeInterval = 300
    var forcedReloadInterval: TimeInterval = 30

    struct Plan: Equatable {
        /// Yazılacak özet; `nil` = yalnızca yenile.
        var snapshot: WidgetSnapshot?
        var reload: Bool
    }

    private(set) var lastWrite: Date?
    private(set) var lastReload: Date?
    private var lastWritten: WidgetSnapshot?
    private var needsReload = false

    /// `build` yalnızca yazma zamanı geldiyse çağrılır (adım başına maliyet ~0).
    mutating func evaluate(now: Date, forced: Bool, build: () -> WidgetSnapshot?) -> Plan? {
        let sinceWrite = lastWrite.map { now.timeIntervalSince($0) } ?? .infinity
        let sinceReload = lastReload.map { now.timeIntervalSince($0) } ?? .infinity
        let reloadDue = needsReload && sinceReload >= reloadInterval
        guard forced || sinceWrite >= writeInterval || reloadDue else { return nil }

        var toWrite: WidgetSnapshot?
        if forced || sinceWrite >= writeInterval, let built = build() {
            let changed = lastWritten.map { !$0.hasSameContent(as: built) } ?? true
            if forced || changed || sinceWrite >= heartbeatInterval {
                toWrite = built
                lastWrite = now
                lastWritten = built
                needsReload = true
            }
        }
        var reload = false
        if needsReload, sinceReload >= (forced ? forcedReloadInterval : reloadInterval) {
            reload = true
            lastReload = now
            needsReload = false
        }
        guard toWrite != nil || reload else { return nil }
        return Plan(snapshot: toWrite, reload: reload)
    }
}
