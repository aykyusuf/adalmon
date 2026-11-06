import Foundation

/// Filtrenin yeni-akış kararlarının saf hali (unit test edilir; `FilterDataProvider` yalnızca bunları çağırır).
///
/// Akış türleri ve kararları (sıra `FilterDataProvider.handleNewFlow` ile aynı):
/// - loopback, proxy portu değil / giden değil / sahibi proxy süreci → `classify` = `nil` → olduğu gibi `.allow()`.
/// - uygulama → loopback:proxyPort → `.proxied`; proxy sürecinin dış akışı → `.proxyEgress`; geri kalan → `.direct`.
/// - `shouldBlock` (blockedAlways / mobilde blockedOnMobile) → `.drop()`; `.proxyEgress` asla engellenmez.
/// - `shouldDropForDataSaver` → `.drop()`; `.proxyEgress`, Adalmon, DNS, proxy sahibi, sistem daemon'ları asla.
/// - `dataTap` → hangi veri gözetimi (yalnız `.proxied` için ilk giden baytlar; mobil `.direct` için gelen veri).
enum FlowPolicy {

    // MARK: Sınıflandırma

    /// `nil` = ilgisiz loopback akışı (yerel IPC): sayılmaz, verisine dokunulmaz.
    static func classify(isLoopback: Bool, isOutbound: Bool, remotePort: Int, executablePath: String,
                         config: FilterConfig) -> FlowKind? {
        let isOwner = !executablePath.isEmpty && config.proxyOwnerPaths.contains(executablePath)
        if isLoopback {
            guard isOutbound, config.proxyPorts.contains(remotePort), !isOwner else { return nil }
            return .proxied
        }
        return isOwner ? .proxyEgress : .direct
    }

    // MARK: Engelleme

    /// Uygulama bu akışta engellenmeli mi? `blockedAlways` her ağda, `blockedOnMobile` yalnız mobilde.
    /// Karar orijin uygulamanın akışına (direct / proxied) uygulanır; proxy egress asla.
    /// Proxy portu var ama sahibi henüz bilinmiyorsa SpoofDPI'ın kendi akışları `.direct` görünür;
    /// bu durumda engelleme/Veri Tasarrufu kararları güvenli tarafta kalır (fail-open).
    static func proxyOwnerUnknown(_ config: FilterConfig) -> Bool {
        !config.proxyPorts.isEmpty && config.proxyOwnerPaths.isEmpty
    }

    static func shouldBlock(app: String, kind: FlowKind, expensive: Bool, config: FilterConfig,
                            signingID: String = "") -> Bool {
        guard kind != .proxyEgress else { return false }
        if signingID == IPC.appBundleID || signingID == IPC.filterBundleID { return false }
        if kind == .direct && proxyOwnerUnknown(config) { return false }
        if config.blockedAlways.contains(app) { return true }
        return expensive && config.blockedOnMobile.contains(app)
    }

    // MARK: Veri Tasarrufu

    /// Port 53 (DNS) ve 853 (DNS-over-TLS) asla düşürülmez.
    static let dnsPorts: Set<Int> = [53, 853]

    /// Veri Tasarrufu açıkken (ve yalnız mobil/pahalı yolda) izin listesinde olmayan uygulamanın YENİ giden akışını düşür.
    ///
    /// Asla düşürülmeyenler: `.proxyEgress` (SpoofDPI'ın dış akışı — engel orijin uygulamanın loopback akışındadır),
    /// Adalmon uygulaması/filtresi (watchdog sondası), proxy sahibi süreç, DNS portları, kimliği çözülemeyen akış
    /// (fail-open), izin listesindeki uygulamalar ve `isEssentialSystem` süreçleri.
    static func shouldDropForDataSaver(app: String, signingID: String, executablePath: String, kind: FlowKind,
                                       isOutbound: Bool, remotePort: Int, expensive: Bool, config: FilterConfig) -> Bool {
        guard config.dataSaverActive, expensive, isOutbound, kind != .proxyEgress else { return false }
        if proxyOwnerUnknown(config) { return false }
        if dnsPorts.contains(remotePort) { return false }
        // Kimlik çözülemediyse (boş yol / unknown / pid:N) karar verme: izin ver.
        if executablePath.isEmpty || app == "unknown" || app.hasPrefix("pid:") { return false }
        if signingID == IPC.appBundleID || signingID == IPC.filterBundleID { return false }
        if config.proxyOwnerPaths.contains(executablePath) { return false }
        if config.dataSaverAllow.contains(app) || config.dataSaverAllow.contains(executablePath) { return false }
        if isEssentialSystem(executablePath: executablePath, signingID: signingID) { return false }
        return true
    }

    // MARK: Sistem daemon'ları

    /// Sistem daemon'ı sayılan yol önekleri (Veri Tasarrufu'nda hep izinli). Bilinçli olarak dar:
    /// `/System/Applications` ve Cryptex'teki Safari/Mail gibi KULLANICI uygulamaları dahil DEĞİL.
    /// configd, nesessionmanager, trustd, apsd, mDNSResponder, networkserviceproxy, symptomsd, identityservicesd… hepsi buradan geçer.
    static let essentialPrefixes = ["/System/Library/", "/usr/libexec/", "/usr/sbin/", "/sbin/"]

    /// Önek eşleşse bile izinli SAYILMAYAN bant genişliği tüketicileri (çalıştırılabilir/paket adı, küçük harf, uzantısız).
    /// Bunlar yalnızca izin listesine eklenirse geçer. Gerekçe: arka planda toplu indirme/yükleme yapar.
    static let bandwidthHogs: Set<String> = [
        "nsurlsessiond",        // arka plan indirmeleri (asıl uygulama atanamazsa)
        "softwareupdated", "softwareupdate", "software update", "mobileassetd", // OS / varlık güncellemeleri
        "appstored", "storedownloadd", "storeassetd", "storeinstalld",           // App Store indirmeleri
        "cloudd", "bird", "fileproviderd", "cloudphotod", "itunescloudd",       // iCloud Drive / Fotoğraflar eşitleme
        "photoanalysisd", "photolibraryd", "mediaanalysisd", "assetsd",         // Fotoğraf analizi / medya
        "backupd", "tmutil",                                                    // Time Machine
    ]

    /// Önek WebKit çerçevesi altındaki süreçler (Networking/WebContent/GPU): hosting uygulama çözülemediğinde
    /// Safari/web görünümü trafiği "sistem" sayılıp Veri Tasarrufu'nu atlamasın diye muaf DEĞİL.
    static func isWebKitHelper(executablePath: String, signingID: String) -> Bool {
        signingID.hasPrefix("com.apple.WebKit.") || executablePath.contains("/WebKit.framework/")
    }

    static func isEssentialSystem(executablePath: String, signingID: String) -> Bool {
        let path = canonicalSystemPath(executablePath)
        guard essentialPrefixes.contains(where: { path.hasPrefix($0) }) else { return false }
        if isWebKitHelper(executablePath: path, signingID: signingID) { return false }
        return !bandwidthHogs.contains(baseName(path))
    }

    /// `/System/Volumes/Preboot/Cryptexes/(Incoming/)OS/System/Library/…` → `/System/Library/…`
    /// (OS Cryptex'indeki sistem ikilileri; Cryptex'teki UYGULAMALAR — `…/Cryptexes/App/…` Safari — olduğu gibi kalır.)
    static func canonicalSystemPath(_ path: String) -> String {
        for marker in ["/Cryptexes/Incoming/OS/", "/Cryptexes/OS/"] {
            if let r = path.range(of: marker) { return "/" + path[r.upperBound...] }
        }
        return path
    }

    /// Yolun son bileşeni, küçük harf, .app/.xpc/.appex uzantısı atılmış.
    static func baseName(_ path: String) -> String {
        var name = (path as NSString).lastPathComponent.lowercased()
        for ext in [".app", ".xpc", ".appex"] where name.hasSuffix(ext) { name = String(name.dropLast(ext.count)) }
        return name
    }

    // MARK: Veri gözetimi

    enum DataTap: Equatable, Sendable {
        /// Akışa dokunma: `.allow()`.
        case none
        /// Yalnız `.proxied`: ilk giden `bytes` baytını (CONNECT satırı) göster; gelen taraf izlenmez.
        /// `handleOutboundData` ayrıştırır ve HEMEN `.allow()` döner (tutma yok, pass+peek döngüsü yok).
        case peekOutboundForTarget(bytes: Int)
        /// Mobilde doğrudan akış: gelen veriyi engelleme için izle (Faz A'dan beri var; değişmedi).
        case mobileInbound
    }

    static let targetPeekBytes = 1024

    static func dataTap(kind: FlowKind, expensive: Bool) -> DataTap {
        switch kind {
        case .proxied: return .peekOutboundForTarget(bytes: targetPeekBytes)
        case .direct: return expensive ? .mobileInbound : .none
        case .proxyEgress: return .none
        }
    }
}
