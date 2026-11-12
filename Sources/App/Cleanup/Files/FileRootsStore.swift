import Foundation

/// Büyük & eski ile Kopyalar'ın taradığı klasörler. Varsayılan: İndirilenler, Belgeler, Masaüstü. Kullanıcı ekleyip çıkarabilir;
/// yalnızca `UserDefaults`ta saklanır (silme işlemleri bu köklerin altına sınırlıdır).
@MainActor @Observable
final class FileRootsStore {
    static let shared = FileRootsStore()
    static let defaultsKey = "cleanup.fileRoots"

    enum AddResult: Equatable {
        case added
        /// Zaten listede ya da bir kökün içinde.
        case covered
        case notDirectory
        /// Ev klasörü dışında (ya da ~/Library içinde).
        case notAllowed

        var message: String? {
            switch self {
            case .added: nil
            case .covered: "Bu klasör zaten taranan bir klasörün içinde."
            case .notDirectory: "Klasör bulunamadı."
            case .notAllowed: "Yalnızca ev klasörü ve harici disklerdeki klasörler eklenebilir (~/Library hariç)."
            }
        }
    }

    let home: String
    @ObservationIgnored private let defaults: UserDefaults
    private(set) var roots: [String]

    static func defaultRoots(home: String) -> [String] { ["Downloads", "Documents", "Desktop"].map { home + "/" + $0 } }

    init(home: String = NSHomeDirectory(), defaults: UserDefaults = .standard) {
        self.home = home
        self.defaults = defaults
        roots = defaults.stringArray(forKey: Self.defaultsKey) ?? Self.defaultRoots(home: home)
    }

    var isDefault: Bool { roots == Self.defaultRoots(home: home) }

    @discardableResult
    func add(_ path: String) -> AddResult {
        guard let canonical = CleanupDeleter.realPath(path) else { return .notDirectory }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical, isDirectory: &isDir), isDir.boolValue else { return .notDirectory }
        let parts = CleanupDeleter.components(canonical)
        let homeParts = CleanupDeleter.components(CleanupDeleter.realPath(home) ?? home)
        let library = homeParts + ["Library"]
        guard CleanupDeleter.isAllowedDescendantRoot(parts, homeParts: homeParts),
              parts != library, !CleanupDeleter.isStrictDescendant(parts, of: library) else { return .notAllowed }
        for existing in roots {
            let existingParts = CleanupDeleter.components(CleanupDeleter.realPath(existing) ?? existing)
            if parts == existingParts || CleanupDeleter.isStrictDescendant(parts, of: existingParts) { return .covered }
        }
        // Yeni kök mevcut köklerin atasıysa onların yerini alır.
        roots.removeAll { existing in
            CleanupDeleter.isStrictDescendant(CleanupDeleter.components(CleanupDeleter.realPath(existing) ?? existing), of: parts)
        }
        roots.append(canonical)
        persist()
        return .added
    }

    func remove(_ path: String) {
        roots.removeAll { $0 == path }
        persist()
    }

    func resetToDefaults() {
        roots = Self.defaultRoots(home: home)
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private func persist() { defaults.set(roots, forKey: Self.defaultsKey) }
}
