import Foundation
import Security

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
        var signingID = ""
        var path = ""
        var code: SecCode?
        let attrs = [kSecGuestAttributeAudit: token] as CFDictionary
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
        if path.isEmpty { path = Self.procPath(pid) }
        let app = Self.rollUp(path: path, fallback: signingID.isEmpty ? "pid:\(pid)" : signingID)
        return Identity(app: app, signingID: signingID, executablePath: path)
    }

    /// "/Applications/Google Chrome.app/Contents/Frameworks/…/Google Chrome Helper.app/…" → "/Applications/Google Chrome.app"
    static func rollUp(path: String, fallback: String) -> String {
        guard !path.isEmpty else { return fallback }
        if let r = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app", options: .backwards) : nil) {
            return String(path[..<r.lowerBound]) + ".app"
        }
        return path
    }

    private static func procPath(_ pid: Int32) -> String {
        guard pid > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard n > 0 else { return "" }
        return String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
