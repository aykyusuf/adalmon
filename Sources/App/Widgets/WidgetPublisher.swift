import Foundation
import WidgetKit

/// Widget özetini app group konteynerine yazar ve zaman çizelgelerini yeniler. Kendi zamanlayıcısı yoktur:
/// `AppModel.step()` her adımda `tick` çağırır; kapı çoğu adımda anında döner.
@MainActor
final class WidgetPublisher {
    private var gate = WidgetPublishGate()
    private let write: @Sendable (WidgetSnapshot) -> Void
    private let reload: @MainActor ([String]) -> Void
    private(set) var writeCount = 0
    private(set) var reloadCount = 0

    init(gate: WidgetPublishGate = WidgetPublishGate(), write: @escaping @Sendable (WidgetSnapshot) -> Void,
         reload: @escaping @MainActor ([String]) -> Void) {
        self.gate = gate
        self.write = write
        self.reload = reload
    }

    /// Gerçek yazma/yenileme; testlerde (XCTest host) hiçbir şey yapmaz.
    static func live() -> WidgetPublisher {
        if AppEnvironment.isRunningTests { return WidgetPublisher(write: { _ in }, reload: { _ in }) }
        return WidgetPublisher(
            write: { snapshot in Task.detached(priority: .utility) { WidgetSnapshotStore.write(snapshot) } },
            reload: { kinds in for kind in kinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) } })
    }

    func tick(now: Date = .now, forced: Bool = false, build: () -> WidgetSnapshot?) {
        guard let plan = gate.evaluate(now: now, forced: forced, build: build) else { return }
        if let snapshot = plan.snapshot { write(snapshot); writeCount += 1 }
        if plan.reload { reload(WidgetShared.Kind.all); reloadCount += 1 }
    }
}
