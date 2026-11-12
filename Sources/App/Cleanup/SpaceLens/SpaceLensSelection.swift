import Darwin
import Foundation

/// Yer kaplayanlar'da temizlik listesine eklenen bir öğe. Kimliği (dev/ino) seçildiği anda alınır; silerken
/// `CleanupDeleter` bunu yeniden denetler (arada değişmişse silmez).
struct SpaceMark: Identifiable, Equatable, Sendable {
    var id: String { path }
    let path: String
    let bytes: UInt64
    let isFolder: Bool
    let dev: Int32
    let ino: UInt64

    var name: String { (path as NSString).lastPathComponent }
}

/// Seçim kümesi (saf değer). İç içe seçimi önler: bir klasör seçilince altındaki seçimler düşer; seçili bir klasörün
/// altındaki öğe ayrıca seçilemez (boyut iki kez sayılmasın).
struct SpaceLensSelection: Equatable, Sendable {
    private(set) var marks: [String: SpaceMark] = [:]

    var isEmpty: Bool { marks.isEmpty }
    var count: Int { marks.count }
    var totalBytes: UInt64 { marks.values.reduce(0) { $0 + $1.bytes } }
    /// Büyükten küçüğe.
    var items: [SpaceMark] { marks.values.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.path < $1.path } }

    func contains(_ path: String) -> Bool { marks[path] != nil }

    /// `path`ın seçili bir üst klasörü var mı (kendisi hariç).
    func coveringAncestor(of path: String) -> String? {
        var current = (path as NSString).deletingLastPathComponent
        while current.count > 1 {
            if marks[current] != nil { return current }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Ekler; altındaki seçimler düşer. Üst klasör zaten seçiliyse eklemez ve false döner.
    @discardableResult
    mutating func add(_ mark: SpaceMark) -> Bool {
        guard coveringAncestor(of: mark.path) == nil else { return false }
        let prefix = mark.path.hasSuffix("/") ? mark.path : mark.path + "/"
        marks = marks.filter { !$0.key.hasPrefix(prefix) }
        marks[mark.path] = mark
        return true
    }

    mutating func remove(_ path: String) { marks[path] = nil }
    mutating func removeAll() { marks = [:] }
}

/// Seçilebilirlik kuralı: `CleanupDeleter`ın reddedeceği şeyler baştan seçilemez (silme yine de deleter'da yeniden doğrulanır).
/// Taramanın kökü, korunan konumlar (`~/Library` kökü ve doğrudan çocukları, Belgeler/Masaüstü gibi), sistem ağaçları seçilemez;
/// kök, ev klasörü / harici birim dışındaysa hiçbir şey seçilemez.
struct SpaceLensGuard: Sendable {
    let root: String
    private let rootParts: [String]
    private let homeParts: [String]
    private let rootAllowed: Bool

    init(root: String, home: String) {
        self.root = root
        rootParts = CleanupDeleter.components(CleanupDeleter.realPath(root) ?? root)
        homeParts = CleanupDeleter.components(CleanupDeleter.realPath(home) ?? home)
        rootAllowed = CleanupDeleter.isAllowedDescendantRoot(rootParts, homeParts: homeParts)
    }

    /// Seçilemiyorsa kullanıcıya gösterilecek kısa neden.
    func refusal(for path: String) -> String? {
        if path == root { return "Tarama kökünün kendisi seçilemez" }
        guard rootAllowed else { return "Bu konumda silme yapılamaz (yalnızca ev klasörü ve harici diskler)" }
        let base = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(base) else { return "Tarama kökünün dışında" }
        let relative = path.dropFirst(base.count).split(separator: "/").map(String.init)
        guard !relative.isEmpty, !relative.contains(where: { $0 == "." || $0 == ".." }) else { return "Geçersiz yol" }
        let canonical = rootParts + relative
        if CleanupDeleter.isUnderSystemTree(canonical) { return "Sistem klasörü" }
        if CleanupDeleter.isProtected(canonical, homeParts: homeParts) { return "Korunan konum" }
        return nil
    }
}

/// `toggleMark` sonucu.
enum SpaceMarkOutcome: Equatable {
    case marked, unmarked
    case blocked(String)
}

enum SpaceLensIdentity {
    /// Yolun dosya kimliği (sembolik bağı izlemez); yoksa nil.
    static func live(_ path: String) -> (dev: Int32, ino: UInt64)? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return (st.st_dev, UInt64(st.st_ino))
    }
}
