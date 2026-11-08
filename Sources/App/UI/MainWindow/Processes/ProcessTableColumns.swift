import CoreGraphics
import Foundation

/// Bir genişlik için hesaplanmış sütun yerleşimi: başlık ve satırlar aynı değerleri kullanır, böylece hizalı kalır.
struct ProcessTableColumns: Equatable {
    struct Entry: Equatable, Identifiable {
        var column: ProcessColumn
        var width: CGFloat
        var id: ProcessColumn { column }
    }

    var nameWidth: CGFloat
    /// Ad dışındaki sütunlar, soldan sağa.
    var entries: [Entry]

    /// Toplam genişlik (ad dahil); sütunların sağındaki boşluk hariç.
    var totalWidth: CGFloat { nameWidth + entries.reduce(0) { $0 + $1.width } }
}

/// Kullanıcının sütun düzeni (saf mantık, test edilir): Ad dışındaki sütunların sırası ve görünürlüğü.
/// Ad her zaman en solda ve gizlenemez. Bilgi sütunları (Süreç / Tür / PID) dokunulmadıkça pencere genişliğine göre
/// kendiliğinden gelir; kullanıcı açıkça açar ya da kapatırsa o karar genişlikten bağımsız uygulanır.
/// Genişlikler kullanıcıya göre değil sütuna göre hesaplanır (`ProcessTableLayout.baseWidth`), bu yüzden sütun taşınınca
/// genişliği de onunla gider. UserDefaults'ta JSON olarak saklanır; bozuk/eski kayıtta güvenli varsayılana düşülür,
/// kayıtta olmayan (yeni eklenmiş) sütunlar sona eklenir.
struct ProcessColumnLayout: Equatable, Sendable {
    /// Ad dışındaki sütunların soldan sağa sırası (her bilinen sütun tam bir kez).
    private(set) var order: [ProcessColumn]
    /// Kullanıcının gizlediği sütunlar.
    private(set) var hidden: Set<ProcessColumn>
    /// Kullanıcının açıkça açtığı bilgi sütunları (genişlik eşiğini beklemeden gösterilir).
    private(set) var shown: Set<ProcessColumn>

    static let defaultsKey = "processes.columnLayout.v1"
    /// Varsayılan sıra: ölçüt sütunları, sonra bilgi sütunları genişlik eşiği sırasıyla.
    static let defaultOrder: [ProcessColumn] = [.cpu, .memory, .disk, .network, .gpu, .energy, .processCount, .category, .pid]
    static let `default` = ProcessColumnLayout(order: defaultOrder, hidden: [], shown: [])

    init(order: [ProcessColumn], hidden: Set<ProcessColumn> = [], shown: Set<ProcessColumn> = []) {
        self.order = order
        self.hidden = hidden
        self.shown = shown
        normalize()
    }

    var isDefault: Bool { self == .default }

    // MARK: Görünürlük

    /// `width`: sütunlara ayrılabilen genişlik. Ad her zaman görünür.
    func isVisible(_ column: ProcessColumn, width: CGFloat) -> Bool {
        if column == .name { return true }
        if hidden.contains(column) { return false }
        if shown.contains(column) { return true }
        guard let threshold = ProcessTableLayout.autoMinWidth(column) else { return true }
        return width >= threshold
    }

    /// Bu genişlikte görünen sütunlar, soldan sağa (Ad hariç).
    func visibleColumns(width: CGFloat) -> [ProcessColumn] {
        order.filter { isVisible($0, width: width) }
    }

    /// Sütunu açıkça gösterir / gizler. Ad gizlenemez.
    mutating func setVisible(_ column: ProcessColumn, _ visible: Bool) {
        guard column != .name else { return }
        if visible {
            hidden.remove(column)
            if ProcessTableLayout.autoMinWidth(column) != nil { shown.insert(column) }
        } else {
            hidden.insert(column)
            shown.remove(column)
        }
    }

    // MARK: Sıra

    /// `column`'u `target`'ın önüne taşır (`target` nil ise en sona). Ad taşınamaz; Ad'ın önü = en baş.
    mutating func move(_ column: ProcessColumn, before target: ProcessColumn?) {
        guard column != .name, column != target, let from = order.firstIndex(of: column) else { return }
        order.remove(at: from)
        if target == .name {
            order.insert(column, at: 0)
        } else if let target, let to = order.firstIndex(of: target) {
            order.insert(column, at: to)
        } else {
            order.append(column)
        }
    }

    /// `column`'u `target`'ın arkasına taşır.
    mutating func move(_ column: ProcessColumn, after target: ProcessColumn) {
        if target == .name { move(column, before: .name); return }
        guard column != target, let i = order.firstIndex(of: target) else { return }
        let next = order[(i + 1)...].first { $0 != column }
        move(column, before: next)
    }

    /// Görünen sütunlar arasında bir sola (önceki görünen sütunun önüne).
    func canMoveLeft(_ column: ProcessColumn, width: CGFloat) -> Bool {
        let visible = visibleColumns(width: width)
        guard let i = visible.firstIndex(of: column) else { return false }
        return i > 0
    }

    func canMoveRight(_ column: ProcessColumn, width: CGFloat) -> Bool {
        let visible = visibleColumns(width: width)
        guard let i = visible.firstIndex(of: column) else { return false }
        return i < visible.count - 1
    }

    mutating func moveLeft(_ column: ProcessColumn, width: CGFloat) {
        let visible = visibleColumns(width: width)
        guard let i = visible.firstIndex(of: column), i > 0 else { return }
        move(column, before: visible[i - 1])
    }

    mutating func moveRight(_ column: ProcessColumn, width: CGFloat) {
        let visible = visibleColumns(width: width)
        guard let i = visible.firstIndex(of: column), i < visible.count - 1 else { return }
        move(column, after: visible[i + 1])
    }

    mutating func reset() { self = .default }

    /// Sıralama sütunu görünmez olduysa düşülecek sütun (CPU görünürse CPU, değilse Ad); görünürse nil.
    func sortFallback(for sortColumn: ProcessColumn, width: CGFloat) -> ProcessColumn? {
        guard !isVisible(sortColumn, width: width) else { return nil }
        return isVisible(.cpu, width: width) ? .cpu : .name
    }

    // MARK: Doğrulama

    /// Yinelenenleri ve Ad'ı atar, kayıtta olmayan sütunları varsayılan sırayla sona ekler.
    private mutating func normalize() {
        var seen = Set<ProcessColumn>()
        var clean: [ProcessColumn] = []
        for c in order where c != .name && seen.insert(c).inserted { clean.append(c) }
        for c in Self.allMovable where !seen.contains(c) { clean.append(c) }
        order = clean
        hidden.remove(.name)
        shown = shown.filter { ProcessTableLayout.autoMinWidth($0) != nil && !hidden.contains($0) }
    }

    /// Ad dışındaki tüm sütunlar: varsayılan sıradakiler, sonra (varsa) varsayılan sıraya henüz eklenmemiş yeni sütunlar.
    private static var allMovable: [ProcessColumn] {
        defaultOrder + ProcessColumn.allCases.filter { $0 != .name && !defaultOrder.contains($0) }
    }

    // MARK: Kalıcılık

    static func decode(_ data: Data?) -> ProcessColumnLayout {
        guard let data, let layout = try? JSONDecoder().decode(ProcessColumnLayout.self, from: data) else { return .default }
        return layout
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func load(from defaults: UserDefaults = .standard) -> ProcessColumnLayout {
        decode(defaults.data(forKey: defaultsKey))
    }

    func save(to defaults: UserDefaults = .standard) {
        if isDefault { defaults.removeObject(forKey: Self.defaultsKey); return }
        if let data = encoded() { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

extension ProcessColumnLayout: Codable {
    private enum CodingKeys: String, CodingKey { case version, order, hidden, shown }

    /// Sütunlar ham ad olarak saklanır; tanınmayan (kaldırılmış) adlar atlanır, böylece tek bir eski ad tüm düzeni bozmaz.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func columns(_ key: CodingKeys) throws -> [ProcessColumn] {
            (try c.decodeIfPresent([String].self, forKey: key) ?? []).compactMap(ProcessColumn.init(rawValue:))
        }
        let order = try columns(.order)
        guard !order.isEmpty else { throw DecodingError.dataCorruptedError(forKey: .order, in: c, debugDescription: "boş sıra") }
        self.init(order: order, hidden: Set(try columns(.hidden)), shown: Set(try columns(.shown)))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(1, forKey: .version)
        try c.encode(order.map(\.rawValue), forKey: .order)
        try c.encode(hidden.map(\.rawValue).sorted(), forKey: .hidden)
        try c.encode(shown.map(\.rawValue).sorted(), forKey: .shown)
    }
}
