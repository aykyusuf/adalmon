import Foundation

/// Bir satır için hangi eylemlerin yapılabileceği (saf mantık, test edilir). İzin verilmeyenler arayüzde soluk gösterilir ve
/// `reason` ipucu olarak yazılır.
struct ProcessPermissions: Equatable, Sendable {
    /// Sonlandırma, askıya alma, öncelik ve verimlilik modu (kullanıcının kendi süreçleri; sistem kategorisi hariç).
    var canControl = false
    var canRestart = false
    /// Hız sınırı / engel / bağlantı yenileme (anahtar bir yol olmalı; sistem kovası değil).
    var canNetworkControl = false
    var canRevealFile = false
    var reason: String?

    /// - Parameters:
    ///   - ownedCount: satırdaki, aynı kullanıcıya ait (sinyal gönderilebilir) ve Adalmon'un kendisi olmayan süreç sayısı.
    static func evaluate(category: ProcessCategory, key: String, isMember: Bool, ownedCount: Int, totalCount: Int) -> ProcessPermissions {
        var p = ProcessPermissions()
        p.canRevealFile = key.hasPrefix("/")
        p.canNetworkControl = !isMember && key.hasPrefix("/") && category != .system && key != ResourceKeys.system
        if category == .system || key == ResourceKeys.system {
            p.reason = "macOS sistem süreci: oturumu veya sistemi bozabileceği için değiştirilemez."
        } else if ownedCount == 0 {
            p.reason = totalCount > 0 ? "Bu süreç başka bir kullanıcıya (root) ait; izniniz yok." : "Süreç artık çalışmıyor."
        } else {
            p.canControl = true
            p.canRestart = !isMember && category == .app && key.hasSuffix(".app")
        }
        return p
    }
}
