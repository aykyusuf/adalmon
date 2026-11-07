import Foundation

/// Apple Aerial manifest'ine (`entries.json`) yalnızca EKLEME / kendi eklediğimizi ÇIKARMA yapan saf düzenleyici.
/// `[String: Any]` üzerinde çalışır (Codable bilinmeyen alanları düşürür). Apple'ın kendi kayıtlarına dokunulmaz.
enum AerialManifest {
    /// Bizim kayıtlarımızın kimlik öneki (geçerli UUID biçimi: hex). Çıkarma bu önek + durum dosyasıyla yapılır.
    static let idPrefix = "ADA1A0A0-"
    static let categoryID = "ADA1A0A0-0000-4000-8000-000000000001"
    static let subcategoryID = "ADA1A0A0-0000-4000-8000-000000000002"
    static let requiredTopLevelKeys: Set<String> = ["assets", "categories", "version"]
    static let supportedVersion = 1
    /// Bir asset'te bulunması gereken alanlar (Apple kayıtlarından gözlenen ve şablon olarak kopyalananlar).
    static let requiredAssetKeys: Set<String> = ["id", "categories", "subcategories", "previewImage", "shotID", "url-4K-SDR-240FPS"]

    struct Entry: Equatable, Sendable {
        var assetID: String
        var name: String
        var videoURL: URL
        var thumbnailURL: URL
    }

    enum ManifestError: Error, Equatable, LocalizedError {
        case unreadable
        case unsupported(String)
        case invariantViolated(String)

        var errorDescription: String? {
            switch self {
            case .unreadable: "Sistem manifest dosyası okunamadı."
            case .unsupported(let why), .invariantViolated(let why): why
            }
        }
    }

    static func newAssetID() -> String {
        let u = UUID().uuidString   // 8-4-4-4-12
        return idPrefix + u.dropFirst(9)
    }

    /// Biçim doğrulaması. Boş dizi = bu macOS'ta güvenle yazılabilir görünüyor; doluysa YAZMA.
    static func problems(in root: [String: Any]) -> [String] {
        var out: [String] = []
        let missing = requiredTopLevelKeys.subtracting(root.keys)
        if !missing.isEmpty { out.append("Beklenen alanlar yok: \(missing.sorted().joined(separator: ", "))") }
        if let v = root["version"] as? Int, v != supportedVersion { out.append("Manifest sürümü \(v) (desteklenen: \(supportedVersion))") }
        else if root["version"] == nil { out.append("Manifest sürümü okunamadı") }
        guard let assets = root["assets"] as? [[String: Any]] else { out.append("assets bir dizi değil"); return out }
        guard root["categories"] is [[String: Any]] else { out.append("categories bir dizi değil"); return out }
        if assets.isEmpty { out.append("Şablon olacak Apple kaydı yok") }
        else if let template = assets.first(where: { requiredAssetKeys.isSubset(of: Set($0.keys)) }) { _ = template }
        else { out.append("Apple kayıtlarının alan düzeni değişmiş") }
        return out
    }

    /// Kayıtları ekler (önce varsa eskilerimizi çıkarır: idempotent). Apple kayıtları değişmez.
    static func inserting(_ entries: [Entry], into root: [String: Any], categoryName: String = "Adalmon") throws -> [String: Any] {
        let problems = problems(in: root)
        guard problems.isEmpty else { throw ManifestError.unsupported(problems.joined(separator: "; ")) }
        guard !entries.isEmpty else { return root }
        var out = removing(from: root)
        var assets = out["assets"] as! [[String: Any]]
        var categories = out["categories"] as! [[String: Any]]
        let template = assets.first(where: { requiredAssetKeys.isSubset(of: Set($0.keys)) })!
        let maxOrder = categories.compactMap { ($0["preferredOrder"] as? NSNumber)?.intValue }.max() ?? 0
        let first = entries[0]
        for (i, e) in entries.enumerated() {
            var asset = template
            asset["id"] = e.assetID
            asset["accessibilityLabel"] = e.name
            asset["localizedNameKey"] = e.name
            asset["categories"] = [categoryID]
            asset["subcategories"] = [subcategoryID]
            asset["shotID"] = "ADALMON_\(e.assetID.suffix(12))"
            asset["previewImage"] = e.thumbnailURL.absoluteString
            asset["url-4K-SDR-240FPS"] = e.videoURL.absoluteString
            // Ayarlar yalnız "showInTopLevel" olanları listeliyor (Apple'ın 165 öğesinin 125'i true); false iken video hiç görünmüyordu.
            asset["showInTopLevel"] = true
            asset["includeInShuffle"] = false
            asset["preferredOrder"] = i
            asset["pointsOfInterest"] = [String: Any]()
            asset.removeValue(forKey: "group")
            asset.removeValue(forKey: "variant")
            assets.append(asset)
        }
        let sub: [String: Any] = [
            "combineVariants": false, "id": subcategoryID, "localizedDescriptionKey": categoryName, "localizedNameKey": categoryName,
            "preferredOrder": 0, "previewImage": first.thumbnailURL.absoluteString, "representativeAssetID": first.assetID,
        ]
        categories.append([
            "id": categoryID, "localizedDescriptionKey": categoryName, "localizedNameKey": categoryName, "preferredOrder": maxOrder + 1,
            "previewImage": first.thumbnailURL.absoluteString, "representativeAssetID": first.assetID, "subcategories": [sub],
        ])
        out["assets"] = assets
        out["categories"] = categories
        try verifyApplePreserved(original: root, modified: out)
        return out
    }

    /// Yalnızca bizim kayıtlarımızı (önekli kimlik, bizim kategori) çıkarır.
    static func removing(from root: [String: Any]) -> [String: Any] {
        var out = root
        if let assets = root["assets"] as? [[String: Any]] {
            out["assets"] = assets.filter { !(($0["id"] as? String)?.hasPrefix(idPrefix) ?? false) }
        }
        if let cats = root["categories"] as? [[String: Any]] {
            out["categories"] = cats.filter { ($0["id"] as? String) != categoryID }
        }
        return out
    }

    /// Bizim eklediğimiz asset sayısı.
    static func ourAssetIDs(in root: [String: Any]) -> [String] {
        (root["assets"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }.filter { $0.hasPrefix(idPrefix) }
    }

    /// Değişmezler: Apple'ın hiçbir kaydı kaybolmadı / değişmedi; bizim kategorinin temsilci asset'i var.
    static func verifyApplePreserved(original: [String: Any], modified: [String: Any]) throws {
        let originalApple = (removing(from: original)["assets"] as? [[String: Any]] ?? [])
        let modifiedApple = (removing(from: modified)["assets"] as? [[String: Any]] ?? [])
        guard NSArray(array: originalApple).isEqual(to: modifiedApple) else {
            throw ManifestError.invariantViolated("Apple asset kayıtları değişecekti; iptal edildi.")
        }
        let originalCats = removing(from: original)["categories"] as? [[String: Any]] ?? []
        let modifiedCats = removing(from: modified)["categories"] as? [[String: Any]] ?? []
        guard NSArray(array: originalCats).isEqual(to: modifiedCats) else {
            throw ManifestError.invariantViolated("Apple kategorileri değişecekti; iptal edildi.")
        }
        let ids = Set((modified["assets"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        for cat in modified["categories"] as? [[String: Any]] ?? [] where (cat["id"] as? String) == categoryID {
            guard let rep = cat["representativeAssetID"] as? String, ids.contains(rep) else {
                throw ManifestError.invariantViolated("Kategori temsilci asset'i eksik; iptal edildi.")
            }
            for sub in cat["subcategories"] as? [[String: Any]] ?? [] {
                guard let r = sub["representativeAssetID"] as? String, ids.contains(r) else {
                    throw ManifestError.invariantViolated("Alt kategori temsilci asset'i eksik; iptal edildi.")
                }
            }
        }
    }

    static func serialize(_ root: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    static func parse(_ data: Data) throws -> [String: Any] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ManifestError.unreadable }
        return obj
    }
}
