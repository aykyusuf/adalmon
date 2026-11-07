import Foundation
import Observation

/// Başlangıç sekmesinin durumu. Tarama ve `launchctl` çağrıları ana iş parçacığı dışında yapılır; eylemlerden sonra liste yenilenir.
@MainActor @Observable
final class StartupItemsModel {
    struct Notice: Equatable, Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    private(set) var items: [StartupItem] = []
    private(set) var backgroundItems: [BackgroundItem] = []
    private(set) var loaded = false
    private(set) var backgroundLoaded = false
    private(set) var busy: Set<String> = []
    var notice: Notice?
    var pendingRemoval: StartupItem?

    private let actions: StartupItemActions
    private let scan: @Sendable () async -> [StartupItem]
    private let scanBackground: @Sendable () async -> [BackgroundItem]

    init(actions: StartupItemActions = StartupItemActions(),
         scan: @escaping @Sendable () async -> [StartupItem] = { await StartupItemScanner.scan() },
         scanBackground: @escaping @Sendable () async -> [BackgroundItem] = { await BackgroundItemScanner.scan() }) {
        self.actions = actions
        self.scan = scan
        self.scanBackground = scanBackground
    }

    func load() async {
        async let background: Void = loadBackground()
        await reload()
        await background
    }

    func reload() async {
        items = await scan()
        loaded = true
    }

    private func loadBackground() async {
        backgroundItems = await scanBackground()
        backgroundLoaded = true
    }

    func setEnabled(_ enabled: Bool, for item: StartupItem) async {
        guard !busy.contains(item.id) else { return }
        busy.insert(item.id)
        let outcome = enabled ? await actions.enable(item) : await actions.disable(item)
        await finish(outcome, success: enabled ? "\(item.name) etkinleştirildi" : "\(item.name) devre dışı bırakıldı")
        busy.remove(item.id)
    }

    func remove(_ item: StartupItem) async {
        guard !busy.contains(item.id) else { return }
        busy.insert(item.id)
        let outcome = await actions.remove(item)
        await finish(outcome, success: "\(item.name) Çöp Kutusu'na taşındı")
        busy.remove(item.id)
    }

    private func finish(_ outcome: StartupItemActions.Outcome, success: String) async {
        switch outcome {
        case .success: notice = Notice(text: success, isError: false)
        case .denied(let reason): notice = Notice(text: reason, isError: true)
        case .failed(let message): notice = Notice(text: "İşlem başarısız: \(message)", isError: true)
        }
        await reload()
    }
}
