import Foundation
import Observation

/// Menü çubuğu öğesinin izlediği küçük özet: yalnızca değişince atanır (olay başına yeniden çizim yok).
struct AgentSummary: Equatable, Sendable {
    var working = 0
    var sessions = 0
}

/// Canlı Claude oturum ağacı. Olay gelince saf `AgentState` güncellenir; zamanlayıcı yalnızca oturum varken, bir sonraki
/// bayatlama anına kurulan tek seferlik bir uykudur (boşta sıfır CPU). Panel görünmüyorken hiçbir görünüm bunu okumaz.
@MainActor @Observable
final class AgentMonitorModel {
    private(set) var state = AgentState()
    private(set) var lastEventAt: Date?
    /// Menü çubuğu öğesi yalnızca bunu gözler.
    private(set) var summary = AgentSummary()

    @ObservationIgnored private var pruneTask: Task<Void, Never>?

    func ingest(_ event: AgentEvent, now: Date = .now) {
        lastEventAt = now
        var next = state
        guard next.apply(event, now: now) else { return }
        state = next
        refreshSummary()
        schedulePrune()
    }

    func prune(now: Date = .now) {
        var next = state
        guard !next.prune(now: now).isEmpty else { return }
        state = next
        refreshSummary()
    }

    /// Dinleyici kapanınca listeyi boşalt.
    func reset() {
        pruneTask?.cancel()
        pruneTask = nil
        state = AgentState()
        lastEventAt = nil
        refreshSummary()
    }

    private func refreshSummary() {
        let next = AgentSummary(working: state.workingAgentCount, sessions: state.sessions.count)
        if next != summary { summary = next }
    }

    private func schedulePrune() {
        pruneTask?.cancel()
        guard let due = state.nextPruneDate() else { pruneTask = nil; return }
        let delay = max(1, due.timeIntervalSinceNow)
        pruneTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.prune()
            self.schedulePrune()
        }
    }
}
