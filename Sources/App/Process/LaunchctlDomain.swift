import Foundation

/// launchd alan hedefi: kullanıcının grafik oturumu (`gui/<uid>`) ya da sistem.
enum LaunchctlDomain: Sendable, Hashable {
    case gui(uid: uid_t)
    case system

    var target: String {
        switch self {
        case .gui(let uid): "gui/\(uid)"
        case .system: "system"
        }
    }
}
