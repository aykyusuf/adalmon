import Foundation

/// Ağ widget'ının hangi yönü gösterdiği.
enum NetworkDirection: String, Codable, CaseIterable, Identifiable, Sendable {
    case both, download, upload

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .both: "İkisi"
        case .download: "İndirme"
        case .upload: "Yükleme"
        }
    }
}
