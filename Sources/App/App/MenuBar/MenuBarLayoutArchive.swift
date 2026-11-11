import Foundation
import Observation

/// Kaydedilmiş bir menü çubuğu düzeni (sıra + bileşen tasarımları + gösterim ayarları).
struct MenuBarLayoutEntry: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var date: Date
    /// true: Adalmon'un aldığı otomatik yedek (sıfırlama/geri yükleme öncesi, açılışta, saatlik).
    var isAutomatic = false
    var config: MenuBarConfig

    static let anonymousID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// Satırda gösterilen kısa özet ("5 öğe: CPU, Bellek, …").
    var summary: String {
        let titles = config.components.filter(\.enabled).map(\.shortTitle)
        let head = titles.prefix(4).joined(separator: ", ")
        let tail = titles.count > 4 ? ", …" : ""
        return "\(config.components.count) öğe" + (titles.isEmpty ? "" : ": " + head + tail)
    }
}

extension MenuBarConfig {
    /// Bileşen kimlikleri dışında aynı mı (hazır düzenler her uygulamada yeni kimlik üretir).
    func isSameLayout(as other: MenuBarConfig) -> Bool {
        func anonymized(_ c: MenuBarConfig) -> MenuBarConfig {
            var c = c
            for i in c.components.indices { c.components[i].id = MenuBarLayoutEntry.anonymousID }
            return c
        }
        return anonymized(self) == anonymized(other)
    }
}

/// Dışa aktarılan tek düzen dosyasının biçimi.
struct MenuBarLayoutFile: Codable, Sendable {
    static let formatID = "adalmon.menubar-layout"
    var format = Self.formatID
    var version = 1
    var name: String
    var date: Date
    var config: MenuBarConfig
}

enum MenuBarLayoutImportError: LocalizedError {
    case notALayout

    var errorDescription: String? { "Bu dosya bir Adalmon menü çubuğu düzeni değil." }
}

/// Kayıtlı düzenler ve otomatik yedekler. Dosya: `Application Support/Adalmon/MenuBarLayouts.json`
/// (testlerde geçici dizin). Repoya ya da kimliğe hiçbir şey yazmaz.
@MainActor @Observable
final class MenuBarLayoutArchive {
    static let maxAutomatic = 20
    static let fileName = "MenuBarLayouts.json"

    private(set) var entries: [MenuBarLayoutEntry] = []
    /// Son dosya yazması başarısız mı (arayüz uyarı gösterir).
    private(set) var lastWriteFailed = false
    @ObservationIgnored let fileURL: URL
    @ObservationIgnored private let now: () -> Date

    init(fileURL: URL = AppEnvironment.supportDirectory.appending(path: MenuBarLayoutArchive.fileName),
         now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
        load()
    }

    /// Kullanıcının adlandırdığı düzenler, yeniden eskiye.
    var saved: [MenuBarLayoutEntry] { newestFirst(entries.filter { !$0.isAutomatic }) }
    /// Otomatik yedekler, yeniden eskiye.
    var automatic: [MenuBarLayoutEntry] { newestFirst(entries.filter(\.isAutomatic)) }

    /// Tarihe göre yeniden eskiye; aynı tarihte sonra ekleneni öne alır.
    private func newestFirst(_ list: [MenuBarLayoutEntry]) -> [MenuBarLayoutEntry] {
        list.enumerated()
            .sorted { $0.element.date != $1.element.date ? $0.element.date > $1.element.date : $0.offset > $1.offset }
            .map(\.element)
    }

    /// Düzeni adıyla kaydeder; aynı adda kayıtlı düzen varsa onun üzerine yazar (eski hâli otomatik yedeğe düşer).
    @discardableResult
    func save(_ config: MenuBarConfig, name rawName: String) -> MenuBarLayoutEntry {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = name.isEmpty ? "Düzen \(saved.count + 1)" : name
        if let i = entries.firstIndex(where: { !$0.isAutomatic && $0.name == finalName }) {
            if entries[i].config != config {
                appendAutomatic(entries[i].config, name: "“\(finalName)” üzerine yazılmadan önce")
            }
            entries[i].config = config
            entries[i].date = now()
            persist()
            return entries[i]
        }
        let entry = MenuBarLayoutEntry(name: finalName, date: now(), config: config)
        entries.append(entry)
        persist()
        return entry
    }

    /// Otomatik yedek. Aynı düzen herhangi bir otomatik yedekte zaten varsa yeni kayıt açmaz, onu en öne taşır
    /// (hazır düzenler arasında ileri geri tıklamak sınırı doldurup özgün tasarımı düşürmesin). En fazla `maxAutomatic`.
    func autoBackup(_ config: MenuBarConfig, reason: String) {
        if let i = entries.firstIndex(where: { $0.isAutomatic && $0.config.isSameLayout(as: config) }) {
            guard automatic.first?.id != entries[i].id else { return }
            var entry = entries.remove(at: i)
            entry.date = now()
            entries.append(entry)
        } else {
            appendAutomatic(config, name: reason)
        }
        persist()
    }

    /// Son otomatik yedek `interval`'dan eskiyse ve düzen değiştiyse yedek alır (düzenlerken periyodik koruma).
    func autoBackupIfStale(_ config: MenuBarConfig, interval: TimeInterval, reason: String) {
        if let last = automatic.first, now().timeIntervalSince(last.date) < interval { return }
        autoBackup(config, reason: reason)
    }

    func rename(_ id: MenuBarLayoutEntry.ID, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].name = name
        persist()
    }

    func delete(_ id: MenuBarLayoutEntry.ID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    /// Otomatik yedeği kalıcı (adlandırılmış) düzene çevirir.
    func keep(_ id: MenuBarLayoutEntry.ID, name: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].isAutomatic = false
        entries[i].name = name
        persist()
    }

    // MARK: Dışa / içe aktarma

    static func exportData(_ entry: MenuBarLayoutEntry) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(MenuBarLayoutFile(name: entry.name, date: entry.date, config: entry.config))
    }

    /// Dosyayı okuyup kayıtlı düzen olarak ekler (uygulamaz). Aynı adda varsa "(içe aktarıldı)" eki alır.
    @discardableResult
    func importLayout(_ data: Data) throws -> MenuBarLayoutEntry {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(MenuBarLayoutFile.self, from: data),
              file.format == MenuBarLayoutFile.formatID else { throw MenuBarLayoutImportError.notALayout }
        var name = file.name
        while saved.contains(where: { $0.name == name }) { name += " (içe aktarıldı)" }
        let entry = MenuBarLayoutEntry(name: name, date: now(), config: file.config)
        entries.append(entry)
        persist()
        return entry
    }

    // MARK: Dosya

    private func appendAutomatic(_ config: MenuBarConfig, name: String) {
        entries.append(MenuBarLayoutEntry(name: name, date: now(), isAutomatic: true, config: config))
        let auto = automatic
        if auto.count > Self.maxAutomatic {
            let drop = Set(auto.suffix(auto.count - Self.maxAutomatic).map(\.id))
            entries.removeAll { drop.contains($0.id) }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let lossy = try? decoder.decode([Lossy<MenuBarLayoutEntry>].self, from: data) {
            entries = lossy.compactMap(\.value)
            // Bazı kayıtlar (başka sürümden) çözülemediyse dosyanın aslını sakla; sonraki yazma onları silmesin.
            if entries.count < lossy.count { moveAside() }
        } else {
            // Okunamayan dosyayı ezme: kenara al, boş başla.
            moveAside()
        }
    }

    /// Dosyanın aslını `…unreadable-<zaman>.json` olarak kenara kopyalar.
    private func moveAside() {
        let aside = fileURL.deletingPathExtension()
            .appendingPathExtension("unreadable-\(Int(now().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: fileURL, to: aside)
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(entries)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            lastWriteFailed = false
        } catch {
            lastWriteFailed = true
        }
    }
}
