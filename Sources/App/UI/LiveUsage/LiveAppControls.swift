import Foundation

/// Canlı listede bir satırdan verilen komut.
enum LiveAppCommand: Equatable, Sendable {
    /// İki yönde de aynı hız sınırı (byte/sn).
    case limit(bytesPerSec: Int)
    /// Yalnızca bir yönü değiştirir (diğer yönün mevcut sınırı korunur).
    case limitDown(bytesPerSec: Int)
    case limitUp(bytesPerSec: Int)
    case clearLimit
    /// Seçilen ağda engelle (mevcut `blockedOnMobile` + `blockedOnWiFi`; filtrede `blockedOnMobile` / `blockedAlways`).
    case block(BlockScope)
    case unblock
}

/// Var olan hız sınırı / engel altyapısına (AppModel) giden tek yüz. Testte sahte kapanışlarla kurulur.
@MainActor
struct LiveAppControls {
    var limit: (String) -> AppLimit?
    /// Elle engel kapsamı (`nil` = engel yok).
    var blockScope: (String) -> BlockScope?
    var setLimit: (String, AppLimit?) -> Void
    var setBlockScope: (String, BlockScope?) -> Void
    /// Ağ filtresi kurulu ve etkin mi (değilse sınır/engel uygulanamaz; uyarı gösterilir).
    var filterReady: () -> Bool = { true }
    /// Şu an mobil veride mi (engel kapsamı şu anki ağı etkilemiyorsa geri alma şeridinde not düşülür).
    var isMobile: () -> Bool = { false }

    static func live(_ model: AppModel) -> LiveAppControls {
        LiveAppControls(
            limit: { [weak model] in model?.limit(for: $0) },
            blockScope: { [weak model] in model?.blockScope(for: $0) },
            setLimit: { [weak model] in model?.setLimit($0, $1) },
            setBlockScope: { [weak model] in model?.setBlockScope($0, $1) },
            filterReady: { [weak model] in model?.installer.state == .active },
            isMobile: { [weak model] in model?.isMobile ?? false }
        )
    }

    /// Önizleme: hiçbir şey uygulamaz.
    static var inert: LiveAppControls {
        LiveAppControls(limit: { _ in nil }, blockScope: { _ in nil }, setLimit: { _, _ in }, setBlockScope: { _, _ in })
    }
}

/// Bir komuttan önceki durum; "Geri al" bunu geri yükler.
struct LiveAppUndo: Equatable, Sendable {
    var app: String
    var previousLimit: AppLimit?
    var previousBlock: BlockScope?
    /// Kullanıcıya gösterilen sonuç ("Chrome: 1 MB/s sınır").
    var message: String
}

/// Komut → mevcut kural/hız sınırı çağrısı eşlemesi (saf karar + uygulama). Ağ kuralını yalnızca `controls` uygular.
enum LiveAppActionMapper {
    /// Hızlı seçenekler (byte/sn).
    static let presets: [Int] = [100 * 1024, 500 * 1024, 1024 * 1024, 5 * 1024 * 1024]

    /// Hız sınırı: iki yön, kapsam sayfaya göre (Mobil sayfası yalnız mobilde).
    static func limit(bytesPerSec: Int, onlyOnMobile: Bool) -> AppLimit? {
        guard bytesPerSec >= 1024 else { return nil }
        return AppLimit(downBytesPerSec: bytesPerSec, upBytesPerSec: bytesPerSec, onlyOnMobile: onlyOnMobile)
    }

    /// Özel değer (KB/s metni) → byte/sn; geçersizse nil. Kestirmelerle aynı üst sınır.
    static func customBytesPerSec(kilobytesText text: String) -> Int? {
        let digits = text.trimmingCharacters(in: .whitespaces)
        guard let kb = Int(digits), let limit = IntentMapping.limit(kilobytesPerSecond: kb, onlyOnMobile: false) else { return nil }
        return limit.downBytesPerSec
    }

    /// Bir uygulama için seçilebilen engel kapsamları. Sistem daemon'ları (/System/Library, /usr/libexec, /usr/sbin, /sbin;
    /// filtrenin Veri Tasarrufu'nda da dokunmadığı küme) yalnızca mobilde engellenebilir: Wi-Fi/kablolu ağda DNS
    /// (mDNSResponder), configd ya da trustd engellenirse tüm internet kesilir. Terminal, Mail, Safari gibi
    /// /System altındaki kullanıcı uygulamaları her kapsamda engellenebilir.
    static func allowedScopes(app: String) -> [BlockScope] {
        FlowPolicy.isEssentialSystem(executablePath: app, signingID: "") ? [.mobile] : BlockScope.allCases
    }

    /// Onay iste: sistem süreci engeli ve "her yerde" engel (uygulama hiçbir ağda internete çıkamaz).
    static func needsConfirmation(_ command: LiveAppCommand, app: String) -> Bool {
        guard case .block(let scope) = command else { return false }
        return scope == .everywhere || ProtectedApps.isSystem(app)
    }

    /// Onay penceresinin başlığı ve açıklaması.
    @MainActor
    static func confirmation(scope: BlockScope, app: String) -> (title: String, message: String) {
        let name = AppCatalog.shared.name(for: app)
        let system = FlowPolicy.isEssentialSystem(executablePath: app, signingID: "")
        let title = "\(name) \(scope.phrase) engellensin mi?"
        var message: String
        switch scope {
        case .everywhere: message = "\(name) hiçbir ağda (mobil veri ve Wi-Fi/kablolu) internete çıkamayacak."
        case .wifi: message = "\(name) Wi-Fi/kablolu ağda internete çıkamayacak; mobil veride çalışmaya devam eder."
        case .mobile: message = "\(name) mobil veride internete çıkamayacak; Wi-Fi/kablolu ağda çalışmaya devam eder."
        }
        if system { message += " Bu bir sistem süreci; engellemek bazı sistem hizmetlerinin çalışmamasına yol açabilir." }
        return (title, message)
    }

    /// Komutu uygular; değişiklik olmadıysa nil, olduysa geri alma kaydı döner.
    @MainActor
    @discardableResult
    static func apply(_ command: LiveAppCommand, app: String, onlyOnMobile: Bool, controls: LiveAppControls) -> LiveAppUndo? {
        let previousLimit = controls.limit(app)
        let previousBlock = controls.blockScope(app)
        let name = AppCatalog.shared.name(for: app)
        let message: String
        switch command {
        case .limit(let bytes):
            guard let new = limit(bytesPerSec: bytes, onlyOnMobile: onlyOnMobile), new != previousLimit else { return nil }
            controls.setLimit(app, new)
            message = "\(name): \(AppModel.rateText(bytes)) hız sınırı" + (onlyOnMobile ? " (mobilde)" : "")
        case .limitDown(let bytes), .limitUp(let bytes):
            guard bytes >= 1024 else { return nil }
            let isDown = if case .limitDown = command { true } else { false }
            var new = previousLimit ?? AppLimit(onlyOnMobile: onlyOnMobile)
            if isDown { new.downBytesPerSec = bytes } else { new.upBytesPerSec = bytes }
            guard new != previousLimit else { return nil }
            controls.setLimit(app, new)
            message = "\(name): \(isDown ? "indirme ↓" : "yükleme ↑") \(AppModel.rateText(bytes))" + (new.onlyOnMobile ? " (mobilde)" : "")
        case .clearLimit:
            guard previousLimit != nil else { return nil }
            controls.setLimit(app, nil)
            message = "\(name): hız sınırı kaldırıldı"
        case .block(let scope):
            guard scope != previousBlock, allowedScopes(app: app).contains(scope) else { return nil }
            controls.setBlockScope(app, scope)
            message = "\(name) \(scope.phrase) engellendi" + scope.note(onMobile: controls.isMobile())
        case .unblock:
            guard previousBlock != nil else { return nil }
            controls.setBlockScope(app, nil)
            message = "\(name): engel kaldırıldı"
        }
        return LiveAppUndo(app: app, previousLimit: previousLimit, previousBlock: previousBlock, message: message)
    }

    /// Komuttan önceki duruma döner (yalnızca değişen alanlara dokunur).
    @MainActor
    static func undo(_ record: LiveAppUndo, controls: LiveAppControls) {
        if controls.limit(record.app) != record.previousLimit { controls.setLimit(record.app, record.previousLimit) }
        if controls.blockScope(record.app) != record.previousBlock { controls.setBlockScope(record.app, record.previousBlock) }
    }

    /// Satır rozeti metni: sınır (yönler farklıysa ikisi ayrı: "↓ 500 KB/s ↑ 250 KB/s") ve/veya engel.
    static func badges(limit: AppLimit?, block: BlockScope?) -> [LiveAppBadge] {
        var out: [LiveAppBadge] = []
        if let block { out.append(LiveAppBadge(text: block.badge, isBlock: true)) }
        if let limit, limit.hasCap {
            out.append(LiveAppBadge(text: limitSummary(limit) + (limit.onlyOnMobile ? " mobilde" : ""), isBlock: false))
        }
        return out
    }
}

extension LiveAppActionMapper {
    /// "≤ 500 KB/s" (iki yön aynı) ya da "↓ 500 KB/s ↑ 250 KB/s"; tanımsız yön yazılmaz. 1024 tabanlı (menüyle aynı).
    static func limitSummary(_ limit: AppLimit) -> String {
        let d = limit.downBytesPerSec.flatMap { $0 > 0 ? $0 : nil }
        let u = limit.upBytesPerSec.flatMap { $0 > 0 ? $0 : nil }
        if let d, let u, d == u { return "≤ \(AppModel.rateText(d))" }
        return [d.map { "↓ \(AppModel.rateText($0))" }, u.map { "↑ \(AppModel.rateText($0))" }].compactMap { $0 }.joined(separator: " ")
    }
}

/// Satırdaki durum rozeti (engel kırmızı, sınır turuncu).
struct LiveAppBadge: Hashable, Sendable {
    var text: String
    var isBlock: Bool
}
