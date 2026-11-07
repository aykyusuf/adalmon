import Foundation
import Observation

/// Metrik panellerinin canlı kaynakları. Yalnızca ilgili panel AÇIKKEN çalışır; kapanınca görev iptal edilir ve veriler boşaltılır
/// (kapalıyken ek örnekleme yok). Kendi `LiveResourceSampler`ı vardır: Süreçler sayfasının taban çizgisiyle karışmaz.
@MainActor @Observable
final class PanelLiveSources {
    private(set) var processes: [TopProcess] = []
    private(set) var writers: [TopProcess] = []
    /// İlk iki örnek gelene kadar (taban çizgisi) true.
    private(set) var isMeasuring = true
    private(set) var activeKind: PanelKind?

    @ObservationIgnored private let sampler = LiveResourceSampler()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private let cores = ProcessInfo.processInfo.activeProcessorCount

    init(model: AppModel?) { self.model = model }

    /// `kind == nil`: panel kapalı. Aynı tür zaten çalışıyorsa hiçbir şey yapmaz.
    func activate(_ kind: PanelKind?) {
        guard kind != activeKind else { return }
        task?.cancel()
        task = nil
        activeKind = kind
        processes = []
        writers = []
        isMeasuring = true
        guard let kind else { return }
        if kind.needsLiveProcesses {
            let metric: TopProcessBuilder.Metric = kind == .cpu ? .cpu : (kind == .gpu ? .gpu : .memory)
            task = Task { [weak self] in await self?.processLoop(metric) }
        } else if kind == .disk {
            task = Task { [weak self] in await self?.writerLoop() }
        }
    }

    /// Önizleme/test: örnekleyici çalıştırmadan sabit veri.
    func setFixtures(processes: [TopProcess], writers: [TopProcess] = []) {
        self.processes = processes
        self.writers = writers
        isMeasuring = false
    }

    private func processLoop(_ metric: TopProcessBuilder.Metric) async {
        await sampler.reset()
        _ = await sampler.sample() // taban çizgisi
        try? await Task.sleep(for: .seconds(1))
        while !Task.isCancelled {
            let snap = await sampler.sample()
            guard !Task.isCancelled else { return }
            processes = TopProcessBuilder.top(snap, metric: metric, cores: cores) { ResourceDisplay.name($0) }
            isMeasuring = false
            try? await Task.sleep(for: .seconds(2), tolerance: .milliseconds(300))
        }
    }

    private func writerLoop() async {
        while !Task.isCancelled {
            if let store = model?.store {
                let ranks = await store.recentTop(metric: .diskWrite, minutes: 60, limit: 6)
                guard !Task.isCancelled else { return }
                writers = TopProcessBuilder.writers(ranks) { ResourceDisplay.name($0) }
            }
            isMeasuring = false
            try? await Task.sleep(for: .seconds(60), tolerance: .seconds(5))
        }
    }
}
