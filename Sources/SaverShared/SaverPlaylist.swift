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
    var items: [SaverPlaylistItem]

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
