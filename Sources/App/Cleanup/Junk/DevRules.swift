import Foundation

/// Geliştirici kuralları: global önbellekler ve proje klasörlerindeki yeniden üretilebilir artıklar.
/// Listeler bu projenin kendisine aittir; dış bir kural listesinden kopyalanmamıştır.
enum DevRules {
    /// Global geliştirici önbellekleri (`.pkgCaches`): hepsi aracın yeniden indirebildiği veridir.
    /// Docker.raw ASLA önerilmez: Docker alanı yalnızca aracın kendi komutuyla (ToolCommands) temizlenir.
    static func globalCacheRoots(home: String) -> [CleanupRoot] {
        [
            CleanupRoot(category: .pkgCaches, path: home + "/.gradle", onlyNames: ["caches"]),
            CleanupRoot(category: .pkgCaches, path: home + "/.cargo/registry", onlyNames: ["cache", "src"]),
            CleanupRoot(category: .pkgCaches, path: home + "/Library/Caches/CocoaPods"),
        ]
    }

    /// Bir proje artığı klasörünün tanınma kuralı: ad + (varsa) aynı klasörde bulunması gereken proje dosyası.
    struct ArtifactRule: Sendable, Equatable {
        let name: String
        /// Boşsa koşulsuz; doluysa kardeşlerden biri tam adla eşleşmeli.
        var siblingNames: Set<String> = []
        /// Kardeşlerden biri bu önekle başlamalı (ör. build.gradle, build.gradle.kts).
        var siblingPrefixes: [String] = []

        var isUnconditional: Bool { siblingNames.isEmpty && siblingPrefixes.isEmpty }

        func matches(siblings: Set<String>) -> Bool {
            if isUnconditional { return true }
            if !siblingNames.isDisjoint(with: siblings) { return true }
            return siblings.contains { name in siblingPrefixes.contains { name.hasPrefix($0) } }
        }
    }

    static let artifactRules: [ArtifactRule] = [
        ArtifactRule(name: "node_modules"),
        ArtifactRule(name: ".build"),
        ArtifactRule(name: "DerivedData"),
        ArtifactRule(name: "target", siblingNames: ["Cargo.toml"]),
        ArtifactRule(name: "Pods", siblingNames: ["Podfile"]),
        ArtifactRule(name: "build", siblingPrefixes: ["build.gradle"]),
    ]

    /// Silme kapsamındaki ad izin listesi.
    static let artifactNames: Set<String> = Set(artifactRules.map(\.name))

    static func rule(named name: String) -> ArtifactRule? { artifactRules.first { $0.name == name } }

    /// Tarayıcı derinlik sınırı: kökten en çok bu kadar alt düzeydeki artıklar bulunur.
    static let maxProjectDepth = 6
}
