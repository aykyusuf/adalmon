import CoreGraphics
import Foundation

/// `isPreview` Tahoe/27'de güvenilmez (Ayarlar önizlemesi 0x0 çerçeveli ikinci örnek açar). Bayrak ya da küçük çerçeve = önizleme.
enum SaverPreviewHeuristic {
    static let minimumFullSize = CGSize(width: 400, height: 250)

    static func isPreview(flag: Bool, size: CGSize) -> Bool {
        flag || size.width < minimumFullSize.width || size.height < minimumFullSize.height
    }
}

/// Ekran koruyucu örneklerinin saf kayıt mantığı (UI'sız, testli). macOS 26/27'de `stopAnimation` çağrılmayabiliyor ve her
/// başlatmada yeni örnek oluşuyor; burası "kim hâlâ yaşamalı" ve "süreç ne zaman kapanabilir" sorularını yanıtlar.
struct SaverLifecycleRegistry: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var token: Int
        /// Ekran kimliği; bilinmiyorsa her örnek için benzersiz (başka ekranın örneğini yanlışlıkla atmamak için).
        var screenKey: String
        var isPreview: Bool
        var running: Bool
    }

    private(set) var entries: [Int: Entry] = [:]
    /// Bu süreçte gerçek (önizleme olmayan) bir çalıştırma görüldü mü? Yalnızca öyleyse süreç kapatılır.
    private(set) var sawFullRun = false

    var runningCount: Int { entries.values.filter(\.running).count }
    var previewCount: Int { entries.values.filter(\.isPreview).count }

    /// Örneği kaydeder ve YERİNE GEÇTİĞİ (şimdi durdurulması gereken) örneklerin belirteçlerini döndürür:
    /// aynı ekranda başka tam örnek, ya da başka bir önizleme örneği.
    mutating func register(token: Int, screenKey: String, isPreview: Bool) -> [Int] {
        let evicted = entries.values
            .filter { $0.token != token && $0.isPreview == isPreview && (isPreview || $0.screenKey == screenKey) }
            .map(\.token)
            .sorted()
        for t in evicted { entries[t] = nil }
        entries[token] = Entry(token: token, screenKey: screenKey, isPreview: isPreview, running: true)
        if !isPreview { sawFullRun = true }
        return evicted
    }

    /// Çerçeve değişince önizleme/tam sınıfı yeniden belirlenir.
    mutating func reclassify(token: Int, isPreview: Bool) {
        guard var e = entries[token] else { return }
        e.isPreview = isPreview
        entries[token] = e
        if !isPreview, e.running { sawFullRun = true }
    }

    mutating func markStopped(token: Int) {
        entries[token]?.running = false
    }

    mutating func remove(token: Int) {
        entries[token] = nil
    }

    /// `willstop`: çalışan TAM örnekler durdurulur (Ayarlar önizlemesi açıksa o yerinde kalır). Durdurulacak belirteçleri döndürür.
    mutating func hostWillStop() -> [Int] {
        let running = entries.values.filter { $0.running && !$0.isPreview }.map(\.token).sorted()
        for t in running { entries[t]?.running = false }
        return running
    }

    /// Ana süreç `exit(0)` ile kapatılabilir mi? Yalnızca: gerçek çalıştırma görüldü, hiçbir örnek çalışmıyor ve
    /// Ayarlar önizlemesi (önizleme örneği) açık değil. Aksi halde Ayarlar'daki önizleme kararırdı.
    func canExitHost(enabled: Bool) -> Bool {
        enabled && sawFullRun && runningCount == 0 && previewCount == 0
    }
}
