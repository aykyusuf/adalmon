import Foundation
import Security
import os

private let log = Logger(subsystem: "com.yusufayik.adalmon", category: "identity")

/// Audit token → uygulama kimliği. (pid, pidversion) ile önbelleklenir; PID yeniden kullanımı yanlış eşleşme üretmez.
final class IdentityResolver: @unchecked Sendable {
    struct Identity: Sendable {
        /// En dıştaki .app yolu ya da çalıştırılabilir yol. Chrome Helper → /Applications/Google Chrome.app
        let app: String
        let signingID: String
        let executablePath: String
    }

    private struct CacheKey: Hashable { let pid: Int32; let version: Int32 }
    private var cache: [CacheKey: Identity] = [:]
    private let lock = NSLock()

    func identity(for token: Data?) -> Identity {
        guard let token, token.count == MemoryLayout<audit_token_t>.size else {
            return Identity(app: "unknown", signingID: "", executablePath: "")
        }
        let (pid, version) = token.withUnsafeBytes { raw in
            (raw.load(fromByteOffset: 5 * 4, as: Int32.self), raw.load(fromByteOffset: 7 * 4, as: Int32.self))
        }
        let key = CacheKey(pid: pid, version: version)
        if let hit = lock.withLock({ cache[key] }) { return hit }

        let resolved = resolve(token: token, pid: pid)
        lock.withLock {
            if cache.count > 4096 { cache.removeAll(keepingCapacity: true) }
            cache[key] = resolved
        }
        return resolved
    }

    private func resolve(token: Data, pid: Int32) -> Identity {
        let attrs = [kSecGuestAttributeAudit: token] as CFDictionary
        let (signingID, path) = Self.codeInfo(attrs: attrs, pid: pid)
        var app = Self.rollUp(path: path, fallback: signingID.isEmpty ? "pid:\(pid)" : signingID)

        // WebKit ağ süreci (Safari, Mail, Raycast… adına bağlanır): `sourceAppAuditToken` süreçin kendisini verir.
        // Süreçten sorumlu uygulamayı (launchd sorumluluk bilgisi) asıl uygulama say. Yalnız `app` değişir;
        // yol/imza kimliği gerçek süreçte kalır (proxy sahibi ve kendi-akış kontrolleri bunlara bakar).
        if Self.isWebKitNetworking(signingID: signingID, path: path),
           let rpid = Self.responsiblePID(for: pid), rpid > 1, rpid != pid {
            let (rSigning, rPath) = Self.codeInfo(attrs: [kSecGuestAttributePid: rpid] as CFDictionary, pid: rpid)
            if !rPath.isEmpty {
                let attributed = Self.rollUp(path: rPath, fallback: rSigning.isEmpty ? "pid:\(rpid)" : rSigning)
                log.notice("attributed WebKit.Networking pid=\(pid, privacy: .public) -> \(attributed, privacy: .public) (responsible pid=\(rpid, privacy: .public))")
                app = attributed
            } else {
                log.notice("WebKit.Networking pid=\(pid, privacy: .public): responsible pid=\(rpid, privacy: .public) unresolved, keeping process identity")
            }
        } else if Self.isWebKitNetworking(signingID: signingID, path: path) {
            log.notice("WebKit.Networking pid=\(pid, privacy: .public): no responsible pid, keeping process identity")
        }
        return Identity(app: app, signingID: signingID, executablePath: path)
    }

    /// İmza kimliği + paket/çalıştırılabilir yolu. Önce kod imzası, yoksa `proc_pidpath`.
    private static func codeInfo(attrs: CFDictionary, pid: Int32) -> (signingID: String, path: String) {
        var signingID = ""
        var path = ""
        var code: SecCode?
        if SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess, let code {
            var staticCode: SecStaticCode?
            if SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode {
                var info: CFDictionary?
                if SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
                   let dict = info as? [String: Any] {
                    signingID = dict[kSecCodeInfoIdentifier as String] as? String ?? ""
                }
                var url: CFURL?
                if SecCodeCopyPath(staticCode, [], &url) == errSecSuccess, let url {
                    path = (url as URL).path
                }
            }
        }
        if path.isEmpty { path = procPath(pid) }
        return (signingID, path)
    }

    static func isWebKitNetworking(signingID: String, path: String) -> Bool {
        signingID == "com.apple.WebKit.Networking" || path.hasSuffix("/com.apple.WebKit.Networking.xpc")
    }

    /// `responsibility_get_pid_responsible_for_pid` (libsystem, özel): XPC servisini başlatan/sorumlu uygulamanın pid'i.
    /// Sembol yoksa `dlsym` nil döner ve atıf sessizce devre dışı kalır (eklenti yüklemesi bozulmaz).
    private static let responsibilityFn: (@convention(c) (pid_t) -> pid_t)? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    static func responsiblePID(for pid: Int32) -> Int32? {
        guard let fn = responsibilityFn else { return nil }
        let r = fn(pid)
        return r > 0 ? r : nil
    }

    /// "/Applications/Google Chrome.app/Contents/Frameworks/…/Google Chrome Helper.app/…" → "/Applications/Google Chrome.app"
    static func rollUp(path: String, fallback: String) -> String {
        guard !path.isEmpty else { return fallback }
        if let r = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app", options: .backwards) : nil) {
            return String(path[..<r.lowerBound]) + ".app"
        }
        return path
    }

    fileprivate static func procPath(_ pid: Int32) -> String {
        guard pid > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard n > 0 else { return "" }
        return String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
