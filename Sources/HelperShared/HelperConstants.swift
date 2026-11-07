import Foundation

/// Ayrıcalıklı yardımcı (AdalmonHelper) ile uygulama arasındaki sabitler. Uygulama, yardımcı ve testlerde ortak.
enum HelperConstants {
    static let teamID = "YOUR_TEAM_ID"
    static let appIdentifier = "com.example.adalmon"
    static let helperIdentifier = "com.example.adalmon.helper"
    /// launchd etiketi = Mach servis adı = `Contents/Library/LaunchDaemons/<etiket>.plist`.
    static let machServiceName = "com.example.adalmon.helper"
    static let launchDaemonPlistName = "com.example.adalmon.helper.plist"
    static let helperExecutableName = "AdalmonHelper"
    /// Yardımcı ile uygulama aynı sürümde olmalı; uyuşmazlıkta UI "yeniden kur" der.
    static let protocolVersion = 1

    /// Yardımcıya yalnızca bu istemci bağlanabilir: Apple zinciri + takım + tanımlayıcı.
    /// `NSXPCConnection.setCodeSigningRequirement` çekirdek denetim belirteciyle (PID yarışı yok) doğrular.
    static var clientRequirement: String { requirement(identifier: appIdentifier) }
    /// Uygulama, konuştuğu servisin gerçekten bizim yardımcımız olduğunu aynı kuralla doğrular.
    static var helperRequirement: String { requirement(identifier: helperIdentifier) }

    static func requirement(identifier: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    // MARK: Güvenlik sınırları

    /// Pil bu yüzdenin altındaysa şarj HER ZAMAN serbesttir (bekçi).
    static let hardFloorPercent = 20
    static let limitRange = 50...100
    static let limitStep = 5
    /// Seyir aralığı (limit - alt sınır) en çok bu kadar olabilir.
    static let maxSailingGap = 30
    /// Elle şarj engelleme: kendiliğinden sona erer.
    static let manualInhibitTTL = 60...3600
    /// "Şarjı şimdi tamamla" en çok bu kadar sürer (sn).
    static let topUpMaxSeconds: TimeInterval = 12 * 3600
    static let pollInterval: TimeInterval = 60
    static let pollLeeway: TimeInterval = 15
}
