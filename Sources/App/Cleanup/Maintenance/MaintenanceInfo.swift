import Foundation

/// Kopyalanabilir bir Terminal komutu. Adalmon bunu ASLA çalıştırmaz; yalnızca metin olarak sunar.
struct MaintenanceCommand: Identifiable, Equatable, Sendable {
    let id: String
    /// Komutun ne yaptığını anlatan kısa etiket.
    let caption: String
    let text: String
    /// Yönetici parolası ister (komut yükseltilmiş yetkiyle başlıyor).
    let needsAdmin: Bool
}

/// Bakım bölümünde gösterilen bir bilgi kartı.
struct MaintenanceTopic: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let symbol: String
    let summary: String
    /// Ek açıklama maddeleri.
    let notes: [String]
    /// Dikkat edilmesi gereken uyarı (pil/CPU, gereksizlik vb.).
    let warning: String?
    let commands: [MaintenanceCommand]
}

/// Bakım bilgi içeriği (saf veri). Çalıştırıcı/süreç bağımlılığı yoktur: yönetici gerektiren komutlar yalnızca
/// kopyalanabilir metindir ("admin items: info + copy only" kararı).
enum MaintenanceInfo {
    static let terminalNote = "Terminal'de çalıştırman gerekir, yönetici parolası ister. Adalmon bu komutları çalıştırmaz."

    static let topics: [MaintenanceTopic] = [
        MaintenanceTopic(
            id: "tm-snapshots",
            title: "Yerel Time Machine anlık görüntüleri",
            symbol: "clock.arrow.circlepath",
            summary: "Time Machine, yedek diski takılı değilken de internal diskte yerel anlık görüntüler tutar. Disk dolarken macOS bunları kendisi siler; "
                + "yine de “Sistem Verileri” şişkinse ne kadar yer tuttuklarına bakabilir ve inceltebilirsin.",
            notes: ["Listeleme yalnızca okur, değişiklik yapmaz.",
                    "İnceltme en eski anlık görüntüleri siler; geri alınamaz. Yedek diskindeki yedeklere dokunmaz."],
            warning: nil,
            commands: [
                MaintenanceCommand(id: "tm-list", caption: "Yerel anlık görüntüleri listele", text: "tmutil listlocalsnapshots /", needsAdmin: false),
                MaintenanceCommand(id: "tm-thin", caption: "Anlık görüntüleri inceltip yer aç (en yüksek aciliyet)",
                                   text: "sudo tmutil thinlocalsnapshots / 999999999999 4", needsAdmin: true)
            ]),
        MaintenanceTopic(
            id: "dns-flush",
            title: "DNS önbelleğini temizle",
            symbol: "network",
            summary: "Bir sitenin adresi değiştiği için eski adrese gidiyorsan ya da ağ değişikliğinden sonra isim çözümlemesi takılıyorsa işe yarar. Disk açmaz.",
            notes: ["Önbellek kısa sürede kendiliğinden yeniden dolar; zararsızdır."],
            warning: nil,
            commands: [
                MaintenanceCommand(id: "dns-flush", caption: "DNS önbelleğini boşalt ve mDNSResponder'ı yenile",
                                   text: "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder", needsAdmin: true)
            ]),
        MaintenanceTopic(
            id: "purge",
            title: "purge (RAM'i boşalt)",
            symbol: "memorychip",
            summary: "RAM'i boşaltır, diski boşaltmaz, gereksiz. Dosya önbelleğini atar; macOS bellek baskısında bunu zaten kendisi yönetir.",
            notes: ["Boşalan önbellek hemen yeniden dolar; uygulamalar bir süre yavaş açılabilir.",
                    "Yalnızca geliştirici ölçümlerinde (soğuk önbellek testi) anlamlıdır."],
            warning: "Önerilmez: bellek sorunlarını çözmez, kısa süre yavaşlatır.",
            commands: [
                MaintenanceCommand(id: "purge", caption: "Disk önbelleğini boşalt", text: "sudo purge", needsAdmin: true)
            ]),
        MaintenanceTopic(
            id: "spotlight-reindex",
            title: "Spotlight'ı yeniden indeksle",
            symbol: "magnifyingglass",
            summary: "Arama sonuçları eksik ya da bozuksa dizini sıfırdan oluşturur. Başka bir çözüm işe yaramadıysa başvur.",
            notes: ["İndeksleme saatler sürebilir; bu sırada mds/mdworker CPU kullanır, fan çalışabilir.",
                    "Bittiğinde aramalar yeniden tam çalışır; o zamana kadar sonuçlar eksik kalır."],
            warning: "Pil ve CPU açısından ağırdır. Prize takılıyken ve acelen yokken çalıştır.",
            commands: [
                MaintenanceCommand(id: "mdutil-erase", caption: "Ana diskin Spotlight dizinini sil ve yeniden kur", text: "sudo mdutil -E /", needsAdmin: true)
            ]),
        MaintenanceTopic(
            id: "periodic",
            title: "Bakım betikleri (periodic)",
            symbol: "calendar.badge.clock",
            summary: "Günlük/haftalık/aylık bakım betikleri macOS'ta artık sistem tarafından otomatik çalıştırılır. Elle çalıştırmak gerekmez.",
            notes: ["Eski internet rehberlerindeki “sudo periodic daily weekly monthly” önerisi günümüzde fark yaratmaz."],
            warning: nil,
            commands: [])
    ]

    /// Yönetici parolası isteyen tüm komutlar.
    static var adminCommands: [MaintenanceCommand] { topics.flatMap(\.commands).filter(\.needsAdmin) }
}
