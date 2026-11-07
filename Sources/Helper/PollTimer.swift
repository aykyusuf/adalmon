import Foundation

/// 60 sn'lik düşük öncelikli zamanlayıcı; yalnızca `setPolling(true)` iken çalışır (boştayken sıfır uyanma).
final class PollTimer: PollScheduling, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.example.adalmon.helper.poll", qos: .utility)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private let onTick: @Sendable () -> Void

    init(onTick: @escaping @Sendable () -> Void) { self.onTick = onTick }

    func setPolling(_ active: Bool) {
        lock.lock(); defer { lock.unlock() }
        timer?.cancel()
        timer = nil
        guard active else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + HelperConstants.pollInterval, repeating: HelperConstants.pollInterval,
                   leeway: .seconds(Int(HelperConstants.pollLeeway)))
        let tick = onTick
        t.setEventHandler { tick() }
        t.resume()
        timer = t
    }
}
