import Foundation

/// Oynatma listesindeki bir video. `file` / `poster` klasöre göre GÖRELİ düz dosya adıdır (yol ayırıcı içermez).
struct SaverPlaylistItem: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var file: String
    var poster: String?
    var width: Int
    var height: Int
    var duration: Double
}

/// Uygulamanın yazdığı, ekran koruyucunun okuduğu küçük JSON. Sürümlü: bilinmeyen yeni şema reddedilir.
///
/// Sürüm kuralı: `schema` yalnızca GERİ UYUMSUZ değişikliklerde artar. `trimStart` / `trimEnd` / `crossfade` EKLEMELİDİR:
/// eski ekran koruyucu bu anahtarları yok sayar (şema 1 kalır; yoksa kurulu eski paket listeyi okuyamazdı),
/// yeni ekran koruyucu eksik anahtarlarda varsayılanları kullanır (`LoopTiming.default`).
struct SaverPlaylist: Codable, Equatable, Sendable {
    static let currentSchema = 1

    enum PlaylistError: Error, Equatable {
        case unsupportedSchema(Int)
    }

    var schema = SaverPlaylist.currentSchema
    var appVersion: String
    var updatedAt: Date
    var shuffle: Bool
    /// Ekran koruyucu bitince ana süreci (legacyScreenSaver) kapat: sızıntı çaresi. Sorun çıkarsa uygulamadan kapatılabilir.
    var hostExitOnStop: Bool = true
    /// Baştan atlanacak saniye (siyah / soluk giriş).
    var trimStart: Double = LoopTiming.default.trimStart
    /// Sondan kesilecek saniye.
    var trimEnd: Double = LoopTiming.default.trimEnd
    /// Çapraz geçiş süresi (sn); 0 = kapalı.
    var crossfade: Double = LoopTiming.default.crossfade
    /// Doldur / Sığdır. EKLEMELİ anahtar: eski ekran koruyucu yok sayar, eksikse `.fill`.
    var videoFit: LoopFit = .fill
    var items: [SaverPlaylistItem]

    /// Üç alanın birleşik, düzeltilmiş görünümü.
    var timing: LoopTiming {
        get { LoopTiming(trimStart: trimStart, trimEnd: trimEnd, crossfade: crossfade).sanitized }
        set { trimStart = newValue.trimStart; trimEnd = newValue.trimEnd; crossfade = newValue.crossfade }
    }

    func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }

    static func decode(_ data: Data) throws -> SaverPlaylist {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let list = try dec.decode(SaverPlaylist.self, from: data)
        guard list.schema <= currentSchema else { throw PlaylistError.unsupportedSchema(list.schema) }
        return list
    }

    static func load(from directory: URL) -> SaverPlaylist? {
        guard let data = try? Data(contentsOf: SaverPaths.playlistURL(in: directory)) else { return nil }
        return try? decode(data)
    }

    /// Dosya adı klasör dışına çıkamaz ("../" ya da alt klasör reddedilir).
    static func resolve(_ name: String, in directory: URL) -> URL? {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else { return nil }
        return directory.appending(path: name, directoryHint: .notDirectory)
    }

    struct Resolved: Equatable, Sendable {
        var item: SaverPlaylistItem
        var videoURL: URL
        var posterURL: URL?
    }

    /// Diskte gerçekten var olan, güvenli adlı öğeler.
    func playable(in directory: URL, fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> [Resolved] {
        items.compactMap { item in
            guard let video = Self.resolve(item.file, in: directory), fileExists(video) else { return nil }
            let poster = item.poster.flatMap { Self.resolve($0, in: directory) }.flatMap { fileExists($0) ? $0 : nil }
            return Resolved(item: item, videoURL: video, posterURL: poster)
        }
    }

    /// Oynatma sırası. Karışıksa her turda yeniden sıralar ve bir önceki turun son öğesi yeni turun ilki olmaz.
    func order<G: RandomNumberGenerator>(_ resolved: [Resolved], avoidingFirst last: UUID? = nil, using generator: inout G) -> [Resolved] {
        guard shuffle, resolved.count > 1 else { return resolved }
        var list = resolved.shuffled(using: &generator)
        if let last, list.first?.item.id == last { list.swapAt(0, list.count - 1) }
        return list
    }
}

// MARK: Hoşgörülü kod çözme

extension SaverPlaylist {
    /// Eski dosyalarda olmayan alanlar varsayılana düşer; bozuk değerler düzeltilir. (Uzantıda: üye bazlı `init` korunur.)
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        appVersion = try c.decode(String.self, forKey: .appVersion)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        shuffle = try c.decode(Bool.self, forKey: .shuffle)
        hostExitOnStop = try c.decodeIfPresent(Bool.self, forKey: .hostExitOnStop) ?? true
        let fallback = LoopTiming.default
        let decoded = LoopTiming(trimStart: (try? c.decodeIfPresent(Double.self, forKey: .trimStart)) ?? fallback.trimStart,
                                 trimEnd: (try? c.decodeIfPresent(Double.self, forKey: .trimEnd)) ?? fallback.trimEnd,
                                 crossfade: (try? c.decodeIfPresent(Double.self, forKey: .crossfade)) ?? fallback.crossfade).sanitized
        trimStart = decoded.trimStart
        trimEnd = decoded.trimEnd
        crossfade = decoded.crossfade
        videoFit = (try? c.decodeIfPresent(LoopFit.self, forKey: .videoFit)) ?? .fill
        items = try c.decode([SaverPlaylistItem].self, forKey: .items)
    }
}
