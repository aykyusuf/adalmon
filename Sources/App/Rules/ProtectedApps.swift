import Foundation

/// Kural / merdiven tarafından asla engellenmeyen ya da sınırlanmayan uygulamalar.
enum ProtectedApps {
    private static let systemPrefixes = ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/", "/private/var/db/"]

    /// Adalmon'un kendisi, proxy (SpoofDPI) sahibi süreç yolları: kural bile bunları engelleyemez.
    static func isEssential(_ app: String, ownAppKey: String, proxyOwnerPaths: [String]) -> Bool {
        if app.isEmpty || app == ownAppKey { return true }
        if app.hasPrefix(ownAppKey + "/") { return true }
        return proxyOwnerPaths.contains(app)
    }

    static func isSystem(_ app: String) -> Bool {
        systemPrefixes.contains { app.hasPrefix($0) }
    }

    /// Kademeli limit için: temel korumalar + sistem yolları + kullanıcının korunan listesi.
    static func isProtectedFromLadder(_ app: String, ownAppKey: String, proxyOwnerPaths: [String], userList: [String]) -> Bool {
        isEssential(app, ownAppKey: ownAppKey, proxyOwnerPaths: proxyOwnerPaths) || isSystem(app) || userList.contains(app)
    }
}
