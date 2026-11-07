import Foundation

/// `launchctl` çağrıları; yalnızca argüman dizisi üretir (saf, test edilebilir). Kabuk kullanılmaz.
enum LaunchctlCommand: Sendable, Hashable {
    case printDisabled(LaunchctlDomain)
    case bootout(LaunchctlDomain, label: String)
    case disable(LaunchctlDomain, label: String)
    case enable(LaunchctlDomain, label: String)
    case bootstrap(LaunchctlDomain, plistPath: String)

    var arguments: [String] {
        switch self {
        case .printDisabled(let domain): ["print-disabled", domain.target]
        case .bootout(let domain, let label): ["bootout", "\(domain.target)/\(label)"]
        case .disable(let domain, let label): ["disable", "\(domain.target)/\(label)"]
        case .enable(let domain, let label): ["enable", "\(domain.target)/\(label)"]
        case .bootstrap(let domain, let path): ["bootstrap", domain.target, path]
        }
    }

    /// Etiket hedef yoluna girdiği için boş olmamalı, `/` ya da boşluk/denetim karakteri içermemeli.
    static func isValidLabel(_ label: String) -> Bool {
        !label.isEmpty && !label.contains("/") && label.unicodeScalars.allSatisfy { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }
    }
}
