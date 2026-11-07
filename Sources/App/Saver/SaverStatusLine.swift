import Foundation

/// Kartın tek satırlık durumu (saf): metin, simge tonu ve "Ayarları aç" bağlantısı gerekip gerekmediği.
struct SaverStatusLine: Equatable, Sendable {
    enum Tone: Equatable, Sendable { case ok, warning, neutral, error }

    static let displayName = "Adalmon Video"

    var text: String
    var tone: Tone
    var systemImage: String
    /// "Ayarları aç" bağlantısı gösterilsin mi (kurulu ama seçili değil / bilinmiyor).
    var offersSettings: Bool
    /// "Listeden Adalmon Video'yu seç" ipucu gösterilsin mi.
    var showsPickHint: Bool

    static func make(status: SaverInstaller.Status, selectedInSystem: Bool?, videoCount: Int) -> SaverStatusLine {
        switch status {
        case .unavailable:
            return .init(text: "Bu derlemede ekran koruyucu yok", tone: .error, systemImage: "xmark.octagon.fill", offersSettings: false, showsPickHint: false)
        case .foreign:
            return .init(text: "Aynı adlı başka bir ekran koruyucu var; dokunulmadı", tone: .warning, systemImage: "exclamationmark.triangle.fill", offersSettings: false, showsPickHint: false)
        case .notInstalled:
            return .init(text: "Henüz etkin değil", tone: .neutral, systemImage: "circle.dashed", offersSettings: false, showsPickHint: false)
        case .installed, .updateNeeded:
            let videos = videoCount > 0 ? "\(videoCount) video" : "video yok"
            switch selectedInSystem {
            case true?:
                return .init(text: "Etkin · \(displayName) · \(videos)", tone: videoCount > 0 ? .ok : .warning,
                             systemImage: "checkmark.circle.fill", offersSettings: false, showsPickHint: false)
            case false?:
                return .init(text: "Kurulu ama seçili değil", tone: .warning, systemImage: "exclamationmark.circle.fill", offersSettings: true, showsPickHint: true)
            case nil:
                return .init(text: "Kurulu · \(displayName) · \(videos)", tone: .neutral, systemImage: "checkmark.circle", offersSettings: true, showsPickHint: true)
            }
        }
    }
}
