# Adalmon — Durum (2026-11-05 ~19:30)

## Çalışan
- NE içerik filtresi (system extension) kurulu, aktif. SpoofDPI (127.0.0.1:8080) ayrıştırma: app→proxy akışı app'e yazılır, proxy egress hariç tutulur. Spike'ta 50 MB testinde %0,15 sapma, YouTube testi googlevideo'yu Chrome altında gösterdi.
- XPC (pull, 1 sn), SQLite (~/Library/Application Support/Adalmon/usage.sqlite), mobil veri tespiti (NWPathMonitor isExpensive/isConstrained), 50 MB/dk ve günlük limit bildirimleri, mobilde engelleme.
- Metrikler (CPU/RAM/Disk/Ağ/GPU), kapsül menü bar öğesi, Liquid Glass panel (NSGlassEffectView), ayarlar penceresi.
- Testler: MetricsSamplerTests, UsageLogicTests geçiyor.

## Devam eden / yapılacak (öncelik sırası)
1. **Pil/CPU (ÖNCELİK):** Adalmon ~%5 CPU yiyor (hedef <%0,5).
   - Panel kapalıyken NSHostingView'ı modelden ayır (rootView'ı sadece açıkken bağla ya da gizliyken gözlemi durdur).
   - Menü bar görüntüsünü yalnızca gösterilen (yuvarlanmış) değer değişince çiz.
   - Filtre STAT raporu .medium (1 sn); gerekirse .low.
2. Menü bar widget stil sistemi — implementer-hard ajanı yarıda kaldı, notu: docs/progress-menubar-agent.md. "devam" ile aynı ajan sürdürülecek.
3. Filtre düzeltmesi koda girdi (proxied akışta CONNECT okununca Wi-Fi'de .allow()), henüz kurulmadı — ajan bitince birlikte build + /Applications'a kur.
4. nsurlsessiond → gerçek app ataması gerçek kullanımda doğrulanacak; iPhone USB tethering arayüz adı / isExpensive hotspot'a bağlanınca test edilecek.
5. Henüz commit yok (kullanıcı istemedi). Branch açma yasak, main'e commit.

## Kurulum notu
Build: `xcodegen generate && xcodebuild -project Adalmon.xcodeproj -scheme Adalmon -configuration Debug -derivedDataPath build -allowProvisioningUpdates CURRENT_PROJECT_VERSION=$(date +%s) build`
Kur: Adalmon'u kapat, build/Build/Products/Debug/Adalmon.app → /Applications (ditto), aç.

## 19:30 güncellemesi
- Pil: %6 → ~%0,9 (2 sn aralık, etiketli Kompakt). Kalanın çoğu macOS'un status item replicant snapshot'ı (öğe genişliğiyle orantılı). 5 sn aralıkta ~%0,3–0,4.
- Ayarlar: NavigationSplitView sidebar, stil/renk galerisi, gerçekçi menü bar önizlemesi, 7 preset, sıcaklık metriği, ağ yön/kaynak seçenekleri (60 sn / bugün / mobil).
- Engelleme: satır içi onay, toast + geri al, panelde "Mobilde engellenenler".
- Sıcaklık: IOHID (özel API), 15 sn'de bir, 6 tdie + NAND + pil. M4'te GPU sensörü yok.
- GPU %25–40: IOKit Device Utilization doğru; düşük frekansta meşgul süre. İyileştirme fikri: IOReport ile frekans ağırlıklı.
- Henüz commit yok.

## ~20:00 — paralel ajanlar çalışıyor
- GPU sıcaklığı (SMC Tg* anahtarları) → Sources/App/Metrics (build-temp)
- Kompakt/özelleştirilebilir panel + PanelSettingsPane → Sources/App/UI/Panel, App/Panel (build-panel)
- Bileşen tabanlı menü bar (docs/progress-menubar-agent.md planı) → MenuBar/StatusBar/Settings (build-comp)
- Uygulama bazlı hız sınırı (NETransparentProxyProvider aynı sysext içinde) → Filter/Shared/Network, ThrottleSettingsPane, docs/throttle-test-plan.md (build-throttle)
- Hepsi bitince: birleşik build + test, Release kur, CPU ölç, hız sınırı test planını uygula (kullanıcı onayıyla). Henüz commit yok.

## ~23:30
- Tüm paralel işler birleşti ve kuruldu (Release): GPU sıcaklığı (SMC Tg*), kompakt panel (~550 pt), bileşen sistemi + Gelişmiş düzenleyici, basit metrik kartları (Tek satır varsayılan, Etiket üstte, Simge), hız sınırı (TransparentProxyProvider; gerçek sistemde HENÜZ TEST EDİLMEDİ — docs/throttle-test-plan.md).
- Testler: 74/74. CPU boşta ~%0,8 (90 sn ölçüm).
- Açık: hız sınırı testi (kullanıcı curl'e limit koyup izin verecek), SpoofDPI açıkken Chrome testi, ilk commit (kullanıcı onayı bekleniyor).

## 2026-11-06 ~16:30 (commit 724caf1, push edildi)
- Filtre interneti kesme olayı: kök sebep macOS güvenlik duvarı süreci (socketfilterfw) kirli kalmıştı; `killall socketfilterfw` ile çözüldü (reboot yok). Uygulamada 60 sn'lik otomatik emniyet testi var.
- SpoofDPI'a giden (proxied) akışlar artık peek edilmiyor → site detayı (Chrome › YouTube) SpoofDPI açıkken yok. Peek asıl suçlu değildi; geri açmak için kullanıcı onayı bekleniyor.
- Anında sınır/engel: pid_shutdown_sockets (root gerekmez, kullanıcı süreçleri). Chrome ve curl'de doğrulandı.
- Dock modu + ana pencere + ayarlar ana pencerede; Tahoe uyumlu full-bleed simge.
- Kurulum notu: filtre kodu değişmediyse Release'i aktif extension sürümüyle derle (CURRENT_PROJECT_VERSION=<aktif>) ki filtre yeniden başlamasın.
- Açık: site detayını geri açma, iPhone hotspot/USB testi, nsurlsessiond ataması, anında sınırı Chrome+YouTube ile kullanıcı testi.

## Handoff (2026-11-06, compact öncesi)
**Now:** Son commit a41c6dc (push edildi). Kurulu sürüm Release, filtre aktif (ext 0.1.0/1793966788), internet normal, CPU ~%0,8.
**Next:** 1) SpoofDPI CONNECT peek'i (site detayı) geri açma — kullanıcı onayı + emniyet sistemi açıkken. 2) Chrome+YouTube ile anında sınır testi. 3) iPhone hotspot (Wi-Fi/USB) algılama testi. 4) nsurlsessiond ataması.
**Decisions:** Anında sınır/engel = pid_shutdown_sockets (+ yeniden başlatma yedeği). Dock modu opsiyonel, ayarlar Dock modunda ana pencerede. Simge full-bleed (Tahoe maskeler). Filtre kodu değişmezse Release'i aktif extension sürümüyle derle.
**Failed attempts:** "pass 4MB + peek 1 byte" filtre kararı tüm bağlantıları kilitledi (watch-chunk.patch, uygulanmadı). Kesintilerin kalıcı sebebi socketfilterfw'nun kirli durumuydu; çözüm `killall socketfilterfw`. "Boş kimlik önbelleği" ve "SpoofDPI'dan önce açılan soket" tahminleri test edilip elendi.

## Faz 2 (2026-11-06/07) — tamamlandı
- Faz A (app): bütçe/ETA, fatura dönemi, kural motoru (kayan + sabit pencere, histerezis), kademeli limit, saatlik tablo `usage_hourly`, yerel gün anahtarı, Dock sayfaları (Genel bakış özeti, Ağ kullanımı + inspector, Geçmiş, Mobil veri + ayarlar, Kurallar), menü çubuğu paneli kart ızgarası, dişli çark doğrudan uygulamayı açar, dostça uygulama/alan adları (Yerel ağ / SpoofDPI üzerinden), performans (pencere açıkken kullanıcı aralığı; boşta ~%0,8).
- Faz B (filtre, ext 1793986709 kurulu): proxied akışta 1 KB CONNECT peek → .allow() (site detayı geri; 10,49 MB indirme 10,52 MB sayıldı), WebKit → sorumlu uygulama (responsibility_get_pid_responsible_for_pid; Safari doğrulandı), blockedAlways (Wi‑Fi engel), Veri Tasarrufu (mobil, default-deny + güvenli muafiyetler), proxy sahibi bilinmezken fail-open.
- Kurulum notu: ext değişince app filtre mach servisine bağlanamayabilir (launchd job MachServices'siz); filtreyi kapat/aç düzeltir.
- Açık: SLOW identity (Warp ilk akışta ~3 s), boşta %0,8 tabanı (status item çizimi), Veri Tasarrufu gerçek hotspot'ta test edilmedi.

## Faz 3 (2026-11-07) — tamamlandı
- Geçmiş › Rapor (Dün / Son 7 gün / Bu ay, önceki döneme göre %, Kopyala); pencere ilk açılışta ekranın ~%85'i (`mainWindow.sizedV2`).
- Süreçler sayfası (⌘6): Şu an / Geçmiş (1-6-12-24 sa, 7 gün; CPU, bellek, GPU, disk yazma, enerji) / Disk (boş alan, en çok yazanlar, büyüyen klasörler). Coalition API (dlsym) dakikada bir, ~2,3 ms/tarama; klasör taraması kademeli (1/3/6 sa), TCC korumalı klasörler taranmaz.
- Ölçüm: kurulu build sabit durumda ~%0,48 CPU (pencere açık); açılıştan sonraki ilk dakikalarda watchdog + ilk tarama nedeniyle geçici yükselme.
