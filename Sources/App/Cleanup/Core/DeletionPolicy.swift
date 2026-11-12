import Foundation

/// Temizlik öğesinin türü: her faz kendi kimliğini ekler ("junk.appCaches", "dev.nodeModules", "apps.bundle"…),
/// tek bir enum'u büyütmeye gerek kalmaz. Günlükte `kind` alanı olarak yazılır.
struct CleanupKind: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }
    var description: String { rawValue }
}

/// Silme yöntemi. Varsayılan her zaman `.trash`; `.permanent` yalnızca tek işlem için seçilir, saklanmaz.
enum DeleteMode: String, Sendable, Codable, CaseIterable {
    case trash, permanent
}

/// Ad kuralı: köke göre izinli çocuk adları (yalnızca bu adlar / bu adlar hariç / bu önekler hariç).
struct NameRule: Sendable, Equatable {
    var only: Set<String>?
    var skip: Set<String> = []
    var skipPrefixes: [String] = []

    static let any = NameRule()

    func allows(_ name: String) -> Bool {
        if let only, !only.contains(name) { return false }
        if skip.contains(name) { return false }
        return !skipPrefixes.contains { name.hasPrefix($0) }
    }
}

/// Doğrudan-çocuk kapsamında bir kök ve o köke özel ad kuralı.
struct DeletionRoot: Sendable, Equatable {
    var path: String
    var names: NameRule = .any
}

/// Bir adayın silinebileceği yerin kuralı. `CleanupDeleter` her adayı kendi kapsamına göre ve ortak denetimlerle doğrular.
enum DeletionScope: Sendable, Equatable {
    /// Öğe, köklerden birinin doğrudan çocuğu olmalı; kök ev klasörünün altında olmalı (kökün kendisi değil).
    case directChild(roots: [DeletionRoot])
    /// Öğe, kullanıcının seçtiği köklerden birinin herhangi bir derinlikteki alt öğesi (kök kendisi değil).
    /// Kök ev klasörü (ya da altı) veya harici birim (`/Volumes/<ad>` ya da altı) olmalı. `nameAllowlist` verilirse öğenin adı içinde olmalı.
    case descendant(roots: [String], nameAllowlist: Set<String>?)
    /// `.app` paketi; üst klasör tam olarak `/Applications`, `/Applications/<tek alt klasör>` ya da `~/Applications`. `com.apple.*` asla.
    case appBundle
    /// Tam yol listesi (tarayıcı geçmişi/çerez dosyaları, tercih plist'leri); yalnızca normal dosya.
    case exactFile(allowed: Set<String>)
}

/// Silinecek tek aday: tarama sırasındaki kimliği (dev/ino) ile birlikte.
struct DeletionCandidate: Identifiable, Sendable, Equatable {
    var id: String { path }
    let path: String
    let dev: Int32
    let ino: UInt64
    let bytes: UInt64
    let kind: CleanupKind
    let scope: DeletionScope
    /// Bunlardan biri çalışıyorsa silinmez (silme anında yeniden okunur).
    var blockingBundleIDs: Set<String> = []
    var displayName: String

    var name: String { (path as NSString).lastPathComponent }
}

// MARK: - CLEAN-01 kategorileri için köprü

extension CleanupCategory {
    var kind: CleanupKind {
        switch self {
        case .appCaches: "junk.appCaches"
        case .derivedData: "dev.derivedData"
        case .archives: "dev.archives"
        case .deviceSupport: "dev.deviceSupport"
        case .simCaches: "dev.simCaches"
        case .pkgCaches: "dev.pkgCaches"
        case .iosBackups: "junk.iosBackups"
        case .downloads: "files.downloads"
        case .trash: "junk.trash"
        }
    }

    /// Bu kategorinin silinmesini engelleyen uygulamalar (öğe adına göre).
    func blockingBundleIDs(forName name: String) -> Set<String> {
        switch self {
        case .appCaches: [name]
        case .derivedData: [CleanupCatalog.xcodeBundleID]
        case .simCaches: [CleanupCatalog.simulatorBundleID, CleanupCatalog.xcodeBundleID]
        default: []
        }
    }
}

extension CleanupRoot {
    var deletionRoot: DeletionRoot {
        DeletionRoot(path: path, names: NameRule(only: onlyNames, skip: skipNames, skipPrefixes: skipPrefixes))
    }
}

extension DeletionCandidate {
    /// CLEAN-01 öğesi → aday: kategorinin kökleri doğrudan-çocuk kapsamı olur. Çöp Sepeti kategorisinin kökü yoktur (hiçbir şey silinmez).
    init(item: CleanupItem, roots: [CleanupRoot]) {
        let own = item.category == .trash ? [] : roots.filter { $0.category == item.category }.map(\.deletionRoot)
        self.init(
            path: item.path, dev: item.dev, ino: item.ino, bytes: item.bytes, kind: item.category.kind,
            scope: .directChild(roots: own), blockingBundleIDs: item.category.blockingBundleIDs(forName: item.name),
            displayName: item.name
        )
    }
}
