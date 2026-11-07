import Foundation

enum PlaylistMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Seçili tek içerik.
    case single
    /// Kütüphane sırasıyla.
    case sequence
    /// Karışık (aynı içerik arka arkaya gelmez).
    case shuffle

    var id: String { rawValue }
    var title: String {
        switch self {
        case .single: "Tek içerik"
        case .sequence: "Sırayla"
        case .shuffle: "Karışık"
        }
    }
}

/// Çalma listesi sırası: saf mantık. Zamanlayıcı denetleyicidedir; burası yalnızca "sıradaki kim" sorusunu yanıtlar.
struct PlaylistRotation<Generator: RandomNumberGenerator>: Sendable where Generator: Sendable {
    private(set) var ids: [UUID]
    private(set) var current: UUID?
    var mode: PlaylistMode
    private var rng: Generator
    private var shuffleBag: [UUID] = []

    init(ids: [UUID], mode: PlaylistMode, current: UUID? = nil, rng: Generator) {
        self.ids = ids
        self.mode = mode
        self.current = current.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
        self.rng = rng
    }

    /// Kütüphane değişti (içerik eklendi / silindi). Geçerli içerik silindiyse ilkine döner.
    mutating func update(ids newIDs: [UUID]) {
        ids = newIDs
        shuffleBag.removeAll { !newIDs.contains($0) }
        if let current, !newIDs.contains(current) { self.current = newIDs.first }
        if current == nil { current = newIDs.first }
    }

    /// Sıradaki içeriğe geçer ve döndürür. `single` modda ya da 0-1 içerikte hep geçerli içerik.
    @discardableResult
    mutating func advance() -> UUID? {
        guard !ids.isEmpty else { current = nil; return nil }
        guard ids.count > 1, mode != .single else { return current ?? ids.first }
        switch mode {
        case .single:
            break
        case .sequence:
            let i = current.flatMap { ids.firstIndex(of: $0) } ?? -1
            current = ids[(i + 1) % ids.count]
        case .shuffle:
            if shuffleBag.isEmpty {
                shuffleBag = ids.shuffled(using: &rng)
                // Yeni turun ilki, geçen turun sonuncusuyla aynı olmasın.
                if shuffleBag.first == current, let swap = shuffleBag.indices.last { shuffleBag.swapAt(0, swap) }
            }
            current = shuffleBag.removeFirst()
        }
        return current
    }
}

extension PlaylistRotation where Generator == SystemRandomNumberGenerator {
    init(ids: [UUID], mode: PlaylistMode, current: UUID? = nil) {
        self.init(ids: ids, mode: mode, current: current, rng: SystemRandomNumberGenerator())
    }
}
