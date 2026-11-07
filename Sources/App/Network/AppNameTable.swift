/// Bilinen süreçlerin Türkçe/insan dostu adları. Anahtarlar küçük harfli, uzantısız dosya adıdır
/// (`.xpc`/`.app` atılmış). Bulunamayan sistem süreçleri `AppNaming` tarafından "<ad> (sistem)" biçimine getirilir.
enum AppNameTable {
    struct Entry: Sendable {
        var name: String
        var iconBundleID: String?
        init(_ name: String, icon: String? = nil) { self.name = name; iconBundleID = icon }
    }

    /// macOS arka plan süreçleri ve XPC servisleri.
    static let systemServices: [String: Entry] = [
        "nsurlsessiond": .init("Arka plan indirmeleri (nsurlsessiond)"),
        "mdnsresponder": .init("DNS (sistem)"),
        "softwareupdated": .init("Yazılım güncelleme", icon: "com.apple.Preferences"),
        "cloudd": .init("iCloud"),
        "bird": .init("iCloud"),
        "photolibraryd": .init("Fotoğraflar (iCloud)", icon: "com.apple.Photos"),
        "apsd": .init("Apple Push"),
        "rapportd": .init("Yakındaki aygıtlar"),
        "trustd": .init("Sertifika denetimi"),
        "com.apple.geod": .init("Haritalar / konum", icon: "com.apple.Maps"),
        "commerce": .init("App Store", icon: "com.apple.AppStore"),
        "appstoreagent": .init("App Store", icon: "com.apple.AppStore"),
        "dataaccessd": .init("Takvim/Kişiler eşitleme"),
        "helpd": .init("Yardım (sistem)"),
        "nesessionmanager": .init("VPN ve ağ filtreleri (sistem)"),
        "syspolicyd": .init("Güvenlik ilkesi (Gatekeeper)"),
        "mobileassetd": .init("Sistem varlıkları (MobileAsset)"),
        "networkserviceproxy": .init("Ağ hizmet proxy'si (sistem)"),
        "searchpartyd": .init("Bul (Find My)"),
        "usbmuxd": .init("USB aygıt bağlantısı (usbmuxd)"),
        "ampdevicediscoveryagent": .init("Müzik · aygıt keşfi", icon: "com.apple.Music"),
        "amplibraryagent": .init("Müzik · kitaplık", icon: "com.apple.Music"),
        "ampartworkagent": .init("Müzik · kapak görselleri", icon: "com.apple.Music"),
        "itunescloudd": .init("Müzik · iCloud kitaplığı", icon: "com.apple.Music"),
        "amsengagementd": .init("App Store / Müzik tanıtımları"),
        "replicatord": .init("Çoğaltma servisi (sistem)"),
        "parsecd": .init("Spotlight önerileri"),
        "weatherd": .init("Hava durumu (sistem)", icon: "com.apple.weather"),
        "jetpackassetd": .init("Uygulama varlıkları (sistem)"),
        "submitdiaginfo": .init("Tanılama raporu gönderme"),
        "sharingd": .init("AirDrop / Paylaşım"),
        "identityservicesd": .init("Apple kimlik hizmetleri"),
        "imagent": .init("iMessage", icon: "com.apple.MobileSMS"),
        "akd": .init("Apple Hesabı"),
        "assistantd": .init("Siri"),
        "xprotectd": .init("Kötü amaçlı yazılım koruması (XProtect)"),
        "mdmclient": .init("Cihaz yönetimi (MDM)"),
        "timed": .init("Saat eşitleme"),
        "analyticsd": .init("Analiz (sistem)"),
        "com.apple.safari.safebrowsing.service": .init("Safari güvenli tarama", icon: "com.apple.Safari"),
        // WebKit ağ süreci Safari'nin ve tüm WKWebView uygulamalarının trafiğini taşır; sahibi veriden çözülemez.
        "com.apple.webkit.networking": .init(AppNaming.webKitName, icon: "com.apple.Safari"),
        "com.apple.webkit.webcontent": .init(AppNaming.webKitName, icon: "com.apple.Safari"),
        "com.apple.webkit.gpu": .init(AppNaming.webKitName, icon: "com.apple.Safari"),
    ]

    /// Sistem içindeki yardımcı `.app` paketlerinin Info.plist adı yerine kullanılacak adlar.
    static let appOverrides: [String: Entry] = [
        "addressbooksourcesync": .init("Kişiler eşitleme"),
        "imtransferagent": .init("iMessage dosya aktarımı"),
        "setappupdater": .init("Setapp Güncelleyici"),
    ]

    /// Komut satırı araçları (küçük harfli dosya adı).
    static let tools: [String: String] = [
        "curl": "curl", "wget": "wget", "gh": "GitHub CLI", "git": "Git", "git-remote-https": "Git", "git-remote-http": "Git",
        "ssh": "SSH", "scp": "SCP", "sftp": "SFTP", "rsync": "rsync", "node": "Node.js", "npm": "npm", "npx": "npx",
        "pnpm": "pnpm", "yarn": "Yarn", "bun": "Bun", "deno": "Deno", "ollama": "Ollama", "brew": "Homebrew",
        "ruby": "Ruby", "java": "Java", "go": "Go", "cargo": "Cargo", "rustup": "Rustup", "docker": "Docker", "kubectl": "kubectl",
        "claude": "Claude Code", "speedtest": "Speedtest", "nc": "netcat", "telnet": "telnet", "ftp": "FTP",
        "pod": "CocoaPods", "swift": "Swift", "xcodebuild": "xcodebuild", "flutter": "Flutter", "pip": "pip", "pip3": "pip",
        "dart": "Dart", "dartvm": "Dart VM",
        "swift-frontend": "Swift derleyici", "swiftc": "Swift derleyici", "swift-driver": "Swift derleyici",
        "clang": "Clang", "clang++": "Clang", "sourcekit-lsp": "SourceKit-LSP",
    ]
}
