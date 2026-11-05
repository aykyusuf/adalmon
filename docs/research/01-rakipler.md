# macOS menü çubuğu sistem monitörleri: rakip taraması (2026-11-05)

Yöntem: GitHub API (repo metadata), README'ler, App Store sayfaları, web araması. DOĞRULANDI = çekilen sayfada görüldü; VARSAYIM/ÇIKARIM = görülmedi. Yıldız/tarih 2026-11-05 anlık görüntüsü.

## 1. Tablo

| Uygulama | Lisans | Yıldız | Son push | Stack | Ağ / app başına |
|---|---|---|---|---|---|
| exelban/Stats | MIT | 43.142 | 2026-11-04 | Swift | Genel ağ; README'de app başına yok |
| yujitach/MenuMeters | GPL-2.0 | 3.088 | 2026-10-28 | ObjC | belirtilmemiş |
| gao-sun/eul | MIT | 9.961 | 2024-05-25 | Swift | bakımsız |
| iGlance | GPL-3.0 | 2.490 | 2023-08-20 | Swift | bakımsız |
| iStat Menus 7 (Bjango) | Ticari | - | v7.5 | ? | top apps bant genişliği var |
| Usage (Oleh Stasula) | Ücretsiz+IAP | - | v2.7.19 | ? | ağ aktivitesi/veri kullanımı |
| rana-gmbh/netfluss | GPL-3.0 | 644 | 2026-11-04 | Swift (dil etiketi C#) | top apps, app başına |
| lucasdaddiego/netpeek | MIT | 4 | 2026-11-03 | Rust CLI | app/flow başına, sudo'suz |
| objective-see/LuLu | GPL-3.0 | 13.511 | 2026-11-02 | ObjC | güvenlik duvarı |
| objective-see/Netiquette | GPL-3.0 | 393 | 2024-10-05 | ObjC | bağlantı listesi |
| kennss/SiliconScope | MIT | 1.015 | 2026-11-02 | Swift, SwiftUI+AppKit | GPU/ANE/bellek bw; ağ yok |
| byrencheema/airstats | MIT | 492 | 2026-11-05 | Swift | CPU/RAM/GPU/ağ/disk/termal |
| TripMode | Ticari | - | v3.2.6 | ? | app başına izleme + engelleme |
| Little Snitch 6 | Ticari $59 | - | 6.4.1 | ? | bağlantı gruplama, trafik grafiği |

## 2. Detaylar

### Stats (DOĞRULANDI: README + API)
- Modüller: CPU, GPU, RAM, disk, ağ, pil, Bluetooth, sensörler, saat. macOS 12+. Fan kontrolü eski, bakımsız.
- macOS 26'da ikonlar için System Settings > Menu Bar izni gerekir. Widget'lar varsayılan kapalı. Wi-Fi adı için Konum izni. Sensör ve Bluetooth modülleri en maliyetli. Update ve public IP için geliştirici sunucusuna istek atar. PR'lar issue tartışması olmadan genelde kapatılır.
- En çok tepki alan issue'lar: "No sensors for M4" (61 yorum), combined mode, desktop widget, "Huge memory usage" (2025), kullanım geçmişi (hâlâ açık), Sonoma ağ widget'ı değer göstermiyor.
- Metrik API'leri README'de yok, kod okunmadı. VARSAYIM: SMC, host_statistics, IOKit.
- MIT: kod kopyalanabilir (atıf şart).

### MenuMeters (DOĞRULANDI)
- Orijinal ragingmenace.com. Fork NSStatusItem'lı faceless app. README Big Sur'a kadar destek yazıyor, Apple Silicon'dan söz etmiyor. Yazar yeni macOS için Stats, iGlance, Eul öneriyor. 106 açık issue. Lisans API'de GPL-2.0.

### eul / iGlance (yalnızca metadata)
- eul MIT, iGlance GPL-3.0. İkisi de 2023-2024'ten beri hareketsiz. Teknik detay incelenmedi.

### iStat Menus 7 (DOĞRULANDI: bjango.com)
- CPU, GPU, bellek, disk, ağ, sensör (fan kontrolü), pil, hava durumu. Kural/bildirim (IP değişimi, bağlantı kopması, yüksek CPU), combined mode. macOS 13.5+. 14 gün deneme, Setapp'te var.
- Ağ: top apps bant genişliği, bağlantı geçmişi grafikleri, public/private IP, bağlantı göstergesi.
- v7.5 Liquid Glass menüleri ekliyor (sayfa macOS 27'ye bağlıyor). Fiyat doğrulanamadı. Kapalı kaynak.

### Usage (DOĞRULANDI: App Store, iMore)
- Büyük olasılıkla "Usage: System Activity Monitor", geliştirici Oleh Stasula, id1561788435. Eşleştirme çıkarım, başka "Usage" olabilir.
- Ücretsiz + IAP (Pro yıllık ~$9.99, lifetime ~$14.99-19.99). v2.7.19, 4.6/5 (254 oy). Disk, bellek, ağ, pil, widget, özelleştirme, iCloud sync. iMore 2021: 19 çubuk bileşeni, 13 popover widget'ı. App başına ağ listede yok.

### Sensei, Private Eye, Bandwidth+, NetBar
- DOĞRULANMADI: aramalar sonuç vermedi. Ayrıca araştırılmalı. abbabon/net-bar: lisans yok, 0 yıldız, kod yeniden kullanılamaz.

### Ağ araçları
- netfluss (DOĞRULANDI: README, LICENSE GPL-3.0): top apps örneklemesi yalnızca popover görünürken. Bazı macOS 26.5 kurulumlarında adaptör `ifi_ibytes` sayacı takılıyor, `nettop` fallback'i (README: CPU-ağır). Ağ dilimi `netstat` farkı. Privileged helper opsiyonel. macOS 13+. Developer ID, Homebrew cask, EdDSA imzalı update.
- netpeek (DOĞRULANDI: README): `com.apple.network.statistics` kernel-control socket (PF_SYSTEM), nettop ile aynı, root'suz. Yalnızca kendi kullanıcı akışları, sudo ile hepsi. Apple haber vermeden değiştirebilir. Struct'lar XNU `ntstat.h`'den. Sadece macOS 26 Apple Silicon'da test. MIT, Swift'e taşıma için ideal referans.
- LuLu: mimari doğrulanmadı (README anlatmıyor). Network Extension kullanımı çıkarım.
- Netiquette: README API anlatmıyor, 2024-10'dan beri hareketsiz.
- TripMode (DOĞRULANDI: App Store özeti): app başına izleme, hotspot algılama, günlük/haftalık/aylık rapor, filtreleme, Tahoe uyumlu. Fiyat bölgeye göre değişir.
- Little Snitch 6 (DOĞRULANDI: obdev basın özeti): $59, macOS 14+, DNS şifreleme, blocklist, app/domain/sunucu/ülke gruplama. Heise: TCP sızıntısı sorunu Apple kaynaklı sürüyor. Trafik grafiğinin ne ölçtüğü doğrulanmadı.

### 2025-2026 yeni projeler (metadata; SiliconScope hariç kod okunmadı)
- SiliconScope (DOĞRULANDI: README): IOReport (özel) ile GPU frekansı/ANE/bellek bant genişliği, sudo'suz. `proc_pid_rusage(RUSAGE_INFO_V6)` süreç başına. SMC, IOHIDEventSystem, host_processor_info, host_statistics64. UI: AppKit NSStatusItem+NSPopover (MenuBarExtra dinamik öğelerde yetmedi), SwiftUI dashboard. SPM, Sparkle, notarized. Sandbox/App Store uyumsuz. macOS 14+, Apple Silicon. Örnekleme ~175 ms delta.
- airstats (MIT, 492, 2026-08 açılış, "0.046% CPU" iddiası doğrulanmadı), mectrics, mac-performance-monitor (989), ftop (402), Vitals (GPL-3.0), OpenStats, burrow (1.705): hepsi metadata. vorssaint-utils (33k, GPL-3.0) araç seti, monitör olup olmadığı belirsiz.

## 3. Metrik başına yöntem
- CPU/RAM: host_processor_info, host_statistics64, sysctl (SiliconScope'ta doğrulandı).
- GPU/ANE/bw: IOReport (özel, App Store dışı).
- Sıcaklık/fan: SMC, IOHIDEventSystem. Yeni çiplerde anahtarlar değişir (Stats'ın en büyük şikayeti).
- Süreç başına CPU/güç: proc_pid_rusage, libproc.
- Ağ toplam: getifaddrs/sysctl sayaçları (VARSAYIM); macOS 26.5'te takılma bildirimi var.
- Ağ app başına: nettop (ağır), doğrudan ntstat socket (netpeek), Network Extension (LuLu/Little Snitch; VARSAYIM).

## 4. UI/UX fikirleri
- Combined mode, kural/bildirim, görünürken örnekleme, top-5 + göreli çubuk, kullanım geçmişi (Stats'ta en çok istenen açık özellik), widget, Liquid Glass popover.

## 5. Yasal
- Kopyalanabilir: MIT (Stats, eul, netpeek, SiliconScope, airstats), atıf ile.
- Yalnızca referans: GPL (MenuMeters, iGlance, LuLu, Netiquette, netfluss). Kod alınırsa proje GPL olur; App Store ile uyumsuzluk yaygın görüş, hukuki tavsiye değil.
- Lisanssız (net-bar): kullanma.
- Özel API (IOReport, ntstat) App Store'u engeller.

## 6. Riskler / açık noktalar
- Doğrulanmamış: Stats API'leri, eul/iGlance/LuLu mimarisi, Sensei, Private Eye, Bandwidth+, NetBar.
- netfluss dil etiketi C# vs README Swift çelişkisi çözülmedi.
- Reddit şikayetleri bulunamadı; şikayet verisi yalnızca GitHub issue başlıklarından.
- iStat fiyatı doğrulanmadı.
