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
        if isShellComponent(key) {
            // Finder/Dock gibi: sonlandırılınca macOS yeniden açar ama askıya almak arayüzü dondurur.
            p.reason = "macOS arayüz bileşeni: askıya alma/sonlandırma ekranı dondurabilir; yalnızca yeniden başlatılabilir."
            p.canRestart = !isMember && ownedCount > 0
            return p
        }
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

    /// Oturumun arayüzünü taşıyan süreçler (yol sonekiyle). Bunlarda yalnızca "yeniden başlat" serbesttir.
    static let shellComponents = ["/Finder.app", "/Dock.app", "/SystemUIServer.app", "/ControlCenter.app",
                                  "/NotificationCenter.app", "/WindowManager.app", "/loginwindow.app", "/WindowServer",
                                  "/Spotlight.app", "/TextInputMenuAgent.app"]

    static func isShellComponent(_ key: String) -> Bool {
        shellComponents.contains { key.hasSuffix($0) || key.contains($0 + "/") }
    }
}
