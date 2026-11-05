# Adalmon — Araştırma Özeti (2026-11-05)

Detaylar: 01-rakipler, 02-ag-olcum, 03-metrik-api, 04-ui-ux.

## Karar özeti
- **Stack:** Swift 6 + SwiftUI (içerik) + AppKit `NSStatusItem` + kendi `NSPanel`. MenuBarExtra yok (programatik açma yok, macOS 27'de MenuBarExtraAccess kırık).
- **Min OS:** macOS 26 (Liquid Glass, `glassEffect`, `GlassEffectContainer`).
- **Dağıtım:** Developer ID, sandbox yok, kişisel kullanım.

## Hedefler
- **Metrikler (public API, sudo yok):**
  - CPU: `host_processor_info`
  - RAM: `host_statistics64`
  - Disk alanı: `statfs` ve `volumeAvailableCapacityForImportantUsage`
  - Disk IO: IOBlockStorageDriver Statistics
  - Ağ: `NET_RT_IFLIST2` / `if_data64`
  - GPU: IOAccelerator PerformanceStatistics
- **Opsiyonel (özel API, kırılgan):** Watt (IOReport/AppleCLPC; macOS 27'de Energy Model 0 W okuyor) ve sıcaklık (IOHID/SMC).

## App bazlı ağ (asıl fark)
Bu Mac'te doğrulandı:
- SpoofDPI, 127.0.0.1:8080'de sistem proxy'si olarak çalışıyor.
- `nettop -P` toplamları yanlış:
  - SpoofDPI'nin trafiği iki kez sayılıyor.
  - nsurlsessiond'un trafiği loopback'e yazılıyor.

**Kural:** Ölçüm akış düzeyinde yapılır.
- app → 127.0.0.1:8080 akışı o app'in internet kullanımıdır.
- SpoofDPI'nin kendi en0 trafiği app'lere eklenmez, sadece toplamın tutup tutmadığını kontrol etmek için kullanılır.
- Proxy'yi atlayan doğrudan akışlar normal sayılır.

**Katmanlar:**
0. **Mobil veri tespiti:** `NWPathMonitor` (`isExpensive` / `isConstrained`), iPhone USB arayüzü ve SSID listesi. Arayüz sayaçlarıyla günlük toplam ve limit tutulur.
1. **Hızlı başlangıç:** `nettop` akış modu ile app bazlı doğru bayt. Domain bilgisi yok.
2. **Hedef:** `NEFilterDataProvider` system extension.
   - Loopback dahil bütün TCP/UDP akışları filtreden geçer.
   - `CONNECT host` / SOCKS5 isteği ve SNI ile domain bulunur (YouTube/googlevideo ayrımı).
   - `sourceAppAuditToken` ile nsurlsessiond trafiği gerçek uygulamaya yazılır.
   - Saniyelik bayt raporu alınır.
3. **Yedek:** Doğrudan ntstat istemcisi (netpeek, MIT, referans).

**Chrome:** Sekmeler ve PWA'lar tek network process üzerinden çıkıyor, süreç düzeyinde ayrılamaz. Ayrım ancak domain ile yapılabilir.

## Açık riskler / doğrulanacaklar
- iPhone USB arayüz adı ve `isExpensive` değeri. Hotspot'a bağlanınca test edilecek.
- Yeni kural kurucusunun macOS 27'de loopback trafiğini filtreye getirip getirmediği.
- Makinedeki kurumsal VPN istemcisinin filtreyle etkileşimi.

## Lisans
- MIT, kod alınabilir (atıfla): Stats, eul, netpeek, SiliconScope.
- GPL, yalnızca fikir/referans: MenuMeters, iGlance, LuLu, netfluss.
