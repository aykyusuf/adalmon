import Foundation

/// Tarayıcı alt süreçlerinin okunur adları (Süreçler listesinde `com.apple.WebKit.WebContent` yerine "Web İçeriği (sekme)").
/// Saf adlandırma: süreç adı + grubun uygulama yolu girer, gösterim adı çıkar; tanınmayan ad nil döner (olduğu gibi kalır).
/// Not: Safari de Chrome de hangi sürecin hangi sekmeye ait olduğunu dışarı vermez; bu yüzden ad sekme başlığı taşımaz.
enum BrowserProcessNaming {
    enum Role: Equatable, Sendable { case main, tab, gpu, network, plugin, helper }

    struct Match: Equatable, Sendable {
        var name: String
        var role: Role
    }

    /// Chromium tabanlı tarayıcılar: ana süreç adı → yardımcı adı ön eki.
    private static let chromiumBases = ["Google Chrome", "Chromium", "Microsoft Edge", "Brave Browser", "Vivaldi", "Opera", "Arc"]

    static func match(rawName: String, groupKey: String) -> Match? {
        let group = ((groupKey as NSString).lastPathComponent as NSString).deletingPathExtension
        switch rawName {
        case "com.apple.WebKit.WebContent": return Match(name: "Web İçeriği (sekme)", role: .tab)
        case "com.apple.WebKit.GPU": return Match(name: "Grafik (GPU) süreci", role: .gpu)
        case "com.apple.WebKit.Networking": return Match(name: "Ağ süreci", role: .network)
        case "Safari" where group == "Safari": return Match(name: "Safari (ana süreç)", role: .main)
        default: break
        }
        for base in chromiumBases {
            if rawName == base, group == base { return Match(name: "\(base) (ana süreç)", role: .main) }
            guard rawName.hasPrefix(base + " Helper") else { continue }
            let rest = String(rawName.dropFirst((base + " Helper").count)).trimmingCharacters(in: .whitespaces)
            guard rest.hasPrefix("("), rest.hasSuffix(")") else { return Match(name: "Yardımcı süreç", role: .helper) }
            let kind = String(rest.dropFirst().dropLast())
            if kind.contains("Renderer") { return Match(name: "Sekme (renderer)", role: .tab) }
            if kind.contains("GPU") { return Match(name: "Grafik (GPU) süreci", role: .gpu) }
            if kind.contains("Plugin") { return Match(name: "Eklenti süreci", role: .plugin) }
            return Match(name: "Yardımcı (\(kind))", role: .helper)
        }
        return nil
    }

    static func display(rawName: String, groupKey: String) -> String {
        match(rawName: rawName, groupKey: groupKey)?.name ?? rawName
    }
}
