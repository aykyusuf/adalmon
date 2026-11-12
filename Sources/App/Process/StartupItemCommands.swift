import Foundation

/// Yönetici gerektiren başlangıç öğeleri için YALNIZCA kopyalanabilir Terminal komutu üretir (saf; hiçbir şey çalıştırmaz).
enum StartupItemCommands {
    /// Durdurur ve oturum/önyüklemede kapalı kalması için `disable` yazar. Değiştirilemeyen (Apple, geçersiz etiket)
    /// ya da yönetici gerektirmeyen öğeler için nil.
    static func adminCommand(for item: StartupItem, uid: uid_t = getuid()) -> String? {
        let permissions = StartupItemPermissions.evaluate(item)
        guard permissions.needsAdmin else { return nil }
        let domain: LaunchctlDomain = item.scope == .daemon ? .system : .gui(uid: uid)
        let steps = [LaunchctlCommand.bootout(domain, label: item.label), .disable(domain, label: item.label)]
        return steps.map { "sudo launchctl " + $0.arguments.map(shellQuoted).joined(separator: " ") }.joined(separator: "; ")
    }

    static func shellQuoted(_ text: String) -> String {
        if text.wholeMatch(of: /[A-Za-z0-9._@+:\/=_-]+/) != nil { return text }
        return "'" + text.replacing("'", with: "'\\''") + "'"
    }
}
