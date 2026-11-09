# Adalmon — Durum (2026-11-05 ~19:30)


## Constraints (kullanıcının koyduğu kurallar, kelimesi kelimesine)
- "ASLA kendi kararınla yeni git branch AÇMA" — olduğun branch'e (main) commit et; branch yalnızca kullanıcı "branch aç" derse.
- "commit at gh ile de public bi repo kur pushla, ama keyleri secretları falan gite koyma patlamayalım aman dikkat et" — her commit öncesi secret taraması.
- "pil yemesin o kadar ona çok dikkat et iyi optimzie ettir" — idle CPU ~<%1 (görsel iyi + CPU <%5 üst sınır).
- "dikkatli olsana olm" (ağ filtresi) — filtre değişikliğinde önce uyar; sonra `sysctl net.cfil.active_count` (2) ve `curl https://example.com` (200) kontrolü.
- "maci yeniden başlatamam çalışmalar var" — reboot gerektiren adım yok.
- "mevcuttaki düzeni bozmamaya çok dikkat et".
- Belirsiz/riskli kararlarda AskUserQuestion ile sor (global CLAUDE.md); alt ajanlar sormaz, ana oturuma rapor verir.
- Disk ~%96 dolu: ajan DerivedData'larını (`/private/tmp/claude-501/adalmon-dd-*`, `adalmon-dd-main` hariç) fazdan sonra sil.
- Kullanıcı ekran başındayken UI'yi sürme / başka uygulamaya tuş gönderme; TCC pencerelerini kullanıcı tıklamaz.
- Ajan modeli (YALNIZCA o oturum için söylendi, kalıcı değil): "ajanları opus açma ben sdiyene kadar en fazla sonnet high ajan açabilirsin"; basit işte sonnet medium.
- Silme komutlarında crew-chief guard: 5 satır SAFE/RISKY gerekçesi yaz, sonra aynı komutu tekrar çalıştır.

## Dersler (doğrulanmış nedenler)
- Test host'u Adalmon.app'in kendisidir: `AppModel.start()` testte gerçek ajan dinleyicisini kurarsa kullanıcının `~/Library/Application Support/Adalmon/ClaudePlugin/config.json` dosyasını ve `agentsPort` tercihini ezer; çalışan uygulamanın hook'ları ölü porta gider, ajanlar ofiste görünmez. Önlem: `AppModel.start` testte `agents.apply()` çağırmaz; dinleyici testleri kendi geçici dizinini kullanır (`AgentPluginGenerator(root:)`). Tam suite sonrası config md5 ve `/v1/state` kontrol edilir.
- Mac pildeyken macOS Düşük Güç Modu'nu açar; `BatteryLiquidGlyphTests` içindeki 7 animasyon testi bu yüzden düşer (fişteyken geçer).

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

## Süreçler yeniden tasarım (2026-11-07, Görev Yöneticisi tarzı) — kurulmadı, commit yok
- BUG kök sebebi: canlı `Table(of:rows:)` (DisclosureTableRow, ~80 satır) içeriğine göre yükseklik bildiriyordu (3004 pt); NavigationSplitView 3184 pt oldu, pencerede ortalanıp üst/alttan taştı → başlık ve kenar çubuğu satırları pencerenin üstünde kaldı. Düzeltme: sayfa içeriği `BoundedHeight` (GeometryReader) ile sunulan boyuta sabitlenir; tablo yerine List + özel hücreler. Regresyon: `ProcessesLayoutTests` (1400x900 ve 940x600).
- Sekmeler (Süreçler sayfası başlığında): İşlemler | Performans | Uygulama geçmişi | Başlangıç | Disk. Seçili sekme `router.processesTab`.
- GPU: canlı örnekleyici her turda AppUsage (IOAccelerator) farklarını pid → grup eşler; tüm satırlar GPU % gösterir (WindowServer, Warp, Safari doğrulandı).
- Ağ sütunu: `UsageEngine.last60Bytes` (60 sn ortalama). CPU sütunu artık makinenin tamamına göre (çekirdek sayısına bölünmüş).
- Açık: Ayrıntılar/Hizmetler sekmesi yok; thread sayısı ve CPU GHz yok (Apple Silicon'da ucuz kaynak yok); Ağ için 1 sa aralığı yok (yalnız saatlik toplam, 24 sa).

## Pil Faz 1 (2026-11-07) — Mac pili, kök yok; kurulmadı, commit yok
- `Sources/App/Battery/` (BatteryMonitor: IOPS olayı + 60 sn zamanlayıcı tol. 15 sn, panel/pencere görünürken 5 sn; parser, health, rollup, alert motoru), `UsageStore+Battery` (battery_min 14 gün, battery_daily 400 gün), menü çubuğu `.batteryCapsule` bileşeni, panel "Pil" bölümü, Dock ⌘7 Pil sayfası, Ayarlar › Pil uyarıları (balon/kenar parlaması/ses/bildirim).
- Sağlık: Apple "Maksimum kapasite" (system_profiler, 6 sa önbellek) + ham/tasarım ikisi birlikte. Sıcaklık: mevcut HID örnekleyici (bu Mac'te 27,1 °C okundu).
- Açık: pil sıcaklığı canlı uygulamada izlenmeli; uyarı balonu tıklanabilir (tam click-through değil, kapat düğmesi için); uygulama kapanırken bekleyen ≤5 dakikalık örnek flush edilmiyor.

## Pil Faz 2 — cihazlar (2026-11-07) — kurulmadı, commit yok
- `Sources/App/Battery/Devices/`: `DeviceBatteryService` (HID IORegistry + system_profiler önbelleği + CoreBluetooth GATT 0x180F + AirPods proximity-pairing reklamı + libimobiledevice), saf çözümleyiciler/birleştirici/uyarı motoru, `LibIMobileDevice` (dlopen). Kadans: arka planda 5 dk, görünürken 30 sn (tarama 60 sn), iOS ayrıntıları 10 dk. CoreBluetooth ancak panel/sayfa açılınca ya da izin zaten verilmişse kurulur; testte hiçbir canlı kaynak yok.
- UI: panel Pil bölümünde "Cihazlar" satırları; Pil sayfasında Mac | Cihazlar | iPhone & iPad; menü çubuğuna cihaz sabitleme (`MenuBarComponent.deviceID`); Ayarlar › Genel › Lisanslar.
- Kitaplıklar: `Vendor/libimobiledevice` (tools/vendor-libimobiledevice.sh ile üretilir, @rpath), Xcode takım kimliğiyle gömüp imzalar.
- DOĞRULANMADI (kullanıcı gerekir): Bluetooth izni + gerçek AirPods/GATT, iPhone USB "Güven"/Wi‑Fi okuması, LifetimeData anahtar adları, reklam bayt düzeni.

## Terminal alt süreçleri + aynı ad ipucu (2026-11-07) — kurulmadı, commit yok
- Terminal/IDE coalition'ları (`TerminalApps`: Warp, Terminal, iTerm, Ghostty, Alacritty, kitty, WezTerm, VS Code, Cursor …) `ResourceSweeper.splitTerminals` ile süreç başına bölünür: anahtar `"<terminal .app yolu>|<çalıştırılabilir yol>"` (`TerminalChildKey`), görünen ad "Warp › xcodebuild"; terminal paketinin içinden çalışanlar terminalin kendi anahtarında kalır.
- Kısa ömürlü süreçler: kalan = coalition toplamı − görülen süreçler (`TerminalSplit.split`), anahtar `…|__residual__`, ad "Warp › diğer (kısa ömürlü süreçler)". Aralıkta doğup hâlâ yaşayan süreç baştan sayılır (`TerminalChildTracker`). Kalan GPU süresi terminalin kendisine verilir (süpürme süreç başına GPU okumaz), kalan belleği 0.
- Canlı İşlemler: terminal satırı toplam gösterir, açılınca çalıştırılabilire göre gruplanmış üyeler (+ kendi süreçleri + kalan). Geçmiş/Disk "En çok yazanlar"/Genel bakış alt anahtarları olduğu gibi gösterir. Şema değişmedi (`proc_app.key`).
- Aynı görünen ad: `DuplicateNameHints` ("Adalmon · DerivedData", "· /Applications"); İşlemler, Uygulama geçmişi ve Disk yazanlar listesinde.
- Ad: `AppNaming.executableName` (Xcode içindeki araç Xcode olmaz; swift-frontend → "Swift derleyici").

## Pil Faz 3 — widget'lar + kestirmeler (2026-11-07) — kurulmadı, commit yok
- `Sources/WidgetShared/` (app + eklentiye derlenir): `WidgetSnapshot` (JSON, app group `widget-snapshot.json`), `WidgetBatteryOptions` (cihaz seçimi/stil/kapasite), `AdalmonRoute` (`adalmon://battery` vb.), widget görünümleri (Tüm piller halka/liste/çubuk, Mac pili, Sistem, Mobil kota). `Sources/Widgets/` = WidgetKit eklentisi `AdalmonWidgets` (com.example.adalmon.widgets, sandbox + app group; `AllBatteriesIntent` yapılandırması).
- Yazma: `AppModel.step()` → `WidgetPublisher.tick` → `WidgetPublishGate` (yazma ≥60 sn ve içerik değiştiyse, 10 dk nabız, tak/çıkar anında; `reloadTimelines` ≥5 dk, zorunluda ≥30 sn). Yeni zamanlayıcı yok. Eski veri (>15 dk) "Adalmon'dan veri gelmedi".
- Kestirmeler: `Sources/App/Intents/` (Pil durumu, Cihaz pilleri, Mobil veri, Adalmon'u aç, Hız sınırı koy/kaldır, Mobilde engelle/kaldır) + `AdalmonShortcuts` Türkçe ifadeler. Ayarlar › Widget'lar (canlı önizleme + ekleme adımları) ve Kestirmeler.
- URL yönlendirme: `SettingsRouter.handle(url:)`; Dock modu kapalıysa en yakın ayar bölümü açılır.
- DOĞRULANMADI (kullanıcı gerekir): widget galerisinde görünme/yerleştirme, gerçek app group dosyası okuma (sandbox), Kestirmeler/Siri ifadeleri (geliştirme dili en; ifadeler Türkçe), widget yenileme bütçesi.

## Faz 5 — metrik başına panel (2026-11-07) — kurulmadı, commit yok
- Menü çubuğu öğesine tıklayınca birincil metriğin kendi paneli açılır (CPU, GPU, Bellek, Disk, Ağ, Sıcaklık, Pil); tek öğe (birleşik gösterim) modunda tıklanan x konumundaki bileşen seçilir. Ayarlar › Menü çubuğu › "Tıklayınca" (metriğin kendi paneli / birleşik panel); gelişmiş düzenleyicide bileşen başına "Tıklayınca açılacak panel". `PanelRouter`, `PanelToggle` (saf), `MenuBarConfig.clickMode`, `MenuBarComponent.panelKind`.
- Tek `PanelController` penceresi + tek hosting view; `PanelSession.kind` ile içerik değişir (başka öğeye tıklayınca titremeden, aynı öğe/içerikte kapanır). Pil/cihaz örnekleme yalnızca Pil/Birleşik panelde; süreç örnekleyici (`PanelLiveSources`, kendi `LiveResourceSampler`ı) yalnızca CPU/GPU/Bellek panelleri açıkken, Disk "en çok yazanlar" 60 sn'de bir.
- Kod: `Sources/App/UI/Panel/Metric/*`, `App/Panel/PanelKind|PanelRouter`. Testler: PanelRoutingTests, MetricPanelModelTests, PanelControllerTests, MetricPanelPreviewTests.
- Açık: Esc için panel açılırken uygulama etkinleştirilir (ana pencere görünürken atlanır); başka uygulama önde iken gerçek tıklamayla elle doğrulanmadı. CPU frekansı yok (kaynak yok). Düşük güç modu anahtarı yalnızca yardımcı kurulu/açıkken değiştirilebilir.

## Faz 6 — panel cilası (2026-11-07) — kurulmadı, commit yok
- İskelet: `ListLoadState` + `SkeletonGroup/SkeletonSwap` (parıltı, Hareketi azalt → durağan, gerçek satırla aynı yükseklik, çapraz geçiş; 6 sn zaman aşımı). CPU/GPU/Bellek/Disk listeleri, pil enerji uygulamaları ve cihazlar. Canlı örnekleyici panel açılırken en başta başlar, ilk fark ~0,5 sn (`PanelLiveSources.firstDeltaDelay`). Pil paneli açılınca `refreshHistoryExtras` çağrılır (önceden yalnız Pil sayfasında yükleniyordu).
- Pil paneli yeniden: `BatteryHeroCard`, `PanelCollapsibleCard` (Pil bilgisi varsayılan kapalı, durum `PanelConfig.detailExpanded/Collapsed` ile hatırlanır), `BatteryEnergyAppsCard`, `BatteryDevicesCard` (iğne = menü çubuğuna ekle/çıkar), `BatteryActionsCard`.
- Cihaz öğeleri: `StatusItemPlan` — sabitlenmiş cihaz her iki gösterim modunda KENDİ NSStatusItem'ı (önceden birleşik modda "compact" öğesine karışıyordu). Çizim "simge + 32%" (şimşek, <%20 turuncu, ≤%10 kırmızı). Tıklayınca Pil paneli o cihaza odaklı açılır (`PanelRoute.focusDeviceID`). Ayarlar › Menü çubuğu: "Pil" kartı (Mac kapsülü, varsayılan gizli) + sabitli cihaz listesi.
- Panel zemini: `PanelBackground` (.solid varsayılan "Koyu (opak)" / .glass), `PanelSurface` + `PanelCardBackground`; Ayarlar › Panel › Zemin. Cam modda eski NSGlassEffectView.
- Testler: PanelSkeletonTests (18), PanelP6PreviewTests (3, p6-*.png). Tümü 588 test geçti.
- Açık: gerçek menü çubuğunda tıklama/odaklanma ve pencere yüksekliği animasyonu (NSAnimationContext 0,16 sn) elle doğrulanmadı; yeni cihaz öğesi macOS tarafından en sola eklenir.

## Handoff (2026-11-07 gece, compact öncesi) — son commit 6f54f80
**Now:** Kurulu sürüm = main. Faz 4–7 bitti: Pil (Mac, cihazlar, iPhone/libimobiledevice, uyarılar, widget, Kestirmeler, root yardımcı kodu), metrik başına menü çubuğu panelleri (CPU/GPU/Bellek/Disk/Ağ/Sıcaklık/Pil, skeleton, koyu opak zemin, cihaz menü öğeleri), animasyonlu güç akışı (ızgara düzen), Süreçler (Görev Yöneticisi, terminal alt süreçleri, Başlangıç kaldırma, Finder/Dock koruması), canlı duvar kâğıdı (A) + deneysel Aerial + 4K ekran koruyucu (AdalmonSaver, /Users/Shared/Adalmon/Saver), çapraz geçiş/kırpma/posterli başlangıç, sade "Ekran koruyucu ve kilit ekranı" kartı (varsayılan duvar kâğıdıyla aynı, otomatik senkron). 757 test geçiyor. Filtre ext 1793986709 değişmedi (kurulumda CURRENT_PROJECT_VERSION=1793986709).
**Next (kullanıcıyla canlı):** Şarj yardımcısı kurulumu (Pil › Şarj › Kur + Giriş Öğeleri onayı; .notFound düzeltildi, denenmedi); Kestirmeler'de Adalmon eylemleri görünüyor mu; iPhone USB "Güven" → iPhone & iPad detayları; duvar kâğıdı/ekran koruyucu canlı (siyah başlangıç düzeldi mi, çapraz geçiş, Stage Manager/tam ekran/çoklu ekran); Aerial kilit ekranı (Main10 temporal layer kanıtlanmadı); Esc ile panel kapatma Dock penceresi açıkken çalışmıyor (Giriş İzleme izni gerekir, kullanıcıya soruldu, cevap yok); pil panelinin canlı görünümü (menü çubuğuna pil kapsülü eklenmedi, Juicy kullanıyor).
**Decisions:** şarj sınırı YOK (bu Mac'te CHTE/CH0B yok, kullanıcı "şarj sınırı olmasın"); libimobiledevice (dylib'ler repoda değil, tools/vendor-libimobiledevice.sh); AirPods canlı BLE + system_profiler yedek; pil geçmişi dakikada bir; her metrik ayrı panel (birleşik panel ayarda); duvar kâğıdı A + B deneysel, duraklatma kuralları varsayılan açık ama kapatılabilir; ekran koruyucu .saver da eklendi (4K).
**Failed attempts:** Esc → PanelWindow.sendEvent/cancelOperation yetmedi (uygulama aktif değilken tuş öndeki uygulamaya gidiyor); ilk Aerial kaydı showInTopLevel=false yüzünden Ayarlar'da görünmedi (düzeltildi, elle yamalandı + WallpaperAgent yeniden başlatıldı); ⌘ kısayolları Dock modunda ana menü yokken çalışmıyordu (düzeltildi); kütüphane küçük resimleri taşıyordu (düzeltildi).
**Disk:** her ajan sonrası /private/tmp/claude-501/adalmon-dd-* sil (kullanıcının diski ~%96 dolu).

## Güncelleme (2026-11-08)
- Root helper + Pil › Şarj sekmesi kodu tamamen kaldırıldı (kullanıcı kararı: faydası az, kalıcı root daemon istenmiyor).
- Saver: poster `init`'te senkron çiziliyor, örtük 0,25 sn contents solması kaldırıldı. Gerçek host'ta ölçüm için: `/usr/bin/log stream --predicate 'subsystem == "com.example.adalmon" AND category == "saver"'`.
- Sıradaki: Esc için Input Monitoring izni, menü çubuğuna pil kapsülü + canlı test.
- Eski kurulumda `ditto` silinen dosyaları temizlemez; kurarken stale dosyaları kontrol et (`codesign --verify --deep --strict`).

## Handoff (2026-11-09 gece) — son commit c09f05c, Ofis v3 çalışıyor
**Bitti ve kurulu:** Claude ajan izleme (plugin 1.3.0: hook → 127.0.0.1 dinleyici → durum modeli; session_title, pid canlılık, model okuma [transcript model alanı], hedef gösterimi opt-in), menü çubuğu Ajanlar paneli, Ajan ofisi (⌘9, oda başına oda, yönetici alanı, balonlar), ayrı pencere (⌥⌘9), tarayıcı görünümü (`agentsWebEnabled`; /, /v1/state, /v1/layout, /v1/stream; token+Host+Origin), açık kalma süresi (CPU paneli/birleşik panel/Genel bakış), pil sıvı animasyonu (10 stil, şimşek).
**Gece testi (gerçek):** `claude -p … --model haiku` ile 3 oturum ve 10 alt ajanlı oturum açıldı; hepsi paneldeki/odadaki listede ve Chrome'daki web görünümünde göründü (alt ajanlar `crew-chief:scanner`, oda "large" 12 üye). `-p` oturumlarında model "unknown" kalıyor (SessionStart.model gelmiyor, transcript kısa sürede kapanıyor).
**Düzeltilen web hataları:** Sec-Fetch-Site cross-site üst düzey gezinme 403 (artık navigate'e izin), mobilya dosyaları `furniture/` öneksiz 404 (istemcide düzeltildi).
**Bilinen sorun:** web istemcisinde yönetici karakteri yarı saydam/duvarda; web layout'u eski şablonlar. Ofis v3 sonrası vektör yeniden tasarımla düzelecek.
**Süren iş:** Ofis v3 ajanı (masalar ajan sayısıyla büyür, taşıyıcı/temizlikçi, gece modu, iMac/MacBook, crew rolleri, interaktif kart, /v1 sözleşmesi docs/OFFICE-V3.md). Bitince: build+kur+commit; sonra vektör 2D yeniden tasarım (kodla çizilen, net), web istemcisini eşle, canlı duvar kâğıdına taşı.
**Karar/kısıt (bu session):** alt ajan en fazla Sonnet (karmaşık: high, basit: medium), Opus yok. Kurulumda `osascript quit` bazen kapatmıyor: `killall Adalmon` + süreç başlangıç saatini doğrula. Temiz kurulum için `git worktree add --detach /private/tmp/claude-501/adalmon-wt HEAD` (+ Vendor/libimobiledevice kopyala) kullanıldı.

## Güncelleme (2026-11-09 gece, ~02:35) — son commit 1034356
**Bitti ve kurulu:** Ofis v3 (parametrik odalar s2…s16, taşıyıcı/temizlikçi, gece modu, iMac/MacBook, 15 crew rolü, interaktif kart/ipucu), **modern vektör 2D tema** (ortam + 6 look karakter + 18 poz + pill etiket/balon/oda kartı; `OfficeTheme` .vector varsayılan, .pixel yedek), etiket çakışma çözücü (Swift + JS), kesirli zoom, okunur gece, ayrı pencere (⌥⌘9), tarayıcı görünümü (vektör canvas istemcisi; `Resources/Web`; Chrome'da denendi: bağlantı, oda, kart, ipucu, yakınlaşma çalışıyor), **ajan ofisi canlı duvar kâğıdı kaynağı** (Duvar kâğıdı › Kaynak: Video | Ajan ofisi; masaüstünde denendi, CPU %1-2), model tespiti Stop/SessionEnd'de.
**Gerçek test (claude -p, haiku):** 3 oturum + 10/6 alt ajanlı oturum → panel, ofis, Chrome'da göründü.
**Bilinen/açık:** model sonradan öğrenilince macOS karakter görünümü yenilenmiyor (ajan çalışıyor); web'de etiket çözücü Chrome'da gözle denenmedi; Esc için Input Monitoring ve Safari Otomasyon izinleri (kullanıcı onayı lazım); Tarayıcılar sekmesi (Safari/Chrome debug) canlı denenmedi; 10x10 kalabalıkta etiket çakışması kaçınılmaz bazı durumlarda; macOS "ekran kaydı yeniden onayı" penceresi (senin onayını bekliyor).
**Test notu:** tam suite'te `PanelControllerTests/testOpenToggleSwitchAndEscape` ön plandaki uygulamaya bağlı kararsız (tek başına geçer).
**Kurulum notu:** `osascript quit` bazen kapatmaz → `killall Adalmon`; kurulum sonrası süreç başlangıç saatini doğrula. Port kalıcı (UserDefaults agentsPort), yeniden başlatmada değişirse config.json'daki yeni portu kullan.

## Handoff (2026-11-09 öğleden önce, compact öncesi) — son commit 5b4d822
**Now (bitti, kurulu, push edildi):** modern vektör 2D ofis (ortam + karakter + etiket/balon + gece/gündüz), parametrik odalar, yönetici alanı/tahta, temizlikçi (yavaş, aralarda süpürür), taşıyıcı, iMac/MacBook, 15 crew rolü, interaktif kart/ipucu (alt ajanda ad iki kez yazılmıyor), arka plan işlemleri (süreç ağacı: panel listesi + oda sunucu rafı + web alanı), pano modu (tam ekran: temalı arka plan, otomatik gizlenen şerit, köşe saati/özet, uyanık tut opt-in; web'de de), kamera zoom 60 fps, ayrı pencere (⌥⌘9), tarayıcı görünümü (Chrome'da denendi), ofis canlı duvar kâğıdı kaynağı (Duvar kâğıdı › Kaynak), model tespiti (transcript model alanı, Stop'ta zorunlu), pil uyarısı kartı (büyük yazı, renkli ton), açık kalma süresi (CPU/birleşik panel/Genel bakış), pil sıvı animasyonu + şimşek.
**Next (bekleyen):** (1) izin gerektiren canlı testler: ekran kaydı yeniden onayı penceresi, Esc için Input Monitoring kararı (kullanıcı "ekle" demişti), Safari Otomasyon izni, Tarayıcılar sekmesi (Safari/Chrome debug) canlı testi; (2) diğer Windows PC oturumlarını gösterme (analiz yapıldı: `http` hook plugin + Mac'te LAN/Tailscale dinleme, makine adı alanı; kullanıcıya soruldu, cevap yok); (3) web pano modu ve macOS pano modu gerçek tam ekranda gözle doğrulanmadı; (4) "araç: Bash" durum metnini daha açık yazma (öneri); (5) 10x10 kalabalıkta etiket çakışması kaçınılmaz bazı durumlar.
**Decisions:** vektör 2D tema varsayılan (piksel yedek: `officeTheme`); alt ajan veri hattı = hook → 127.0.0.1 dinleyici (plugin `adalmon-agents@adalmon-local` 1.3.0); gizlilik: yalnızca olay/oturum/ajan/araç adı/model/proje adı/session_title; komut/argüman/istem/dosya içeriği ASLA (hedef gösterimi opt-in: dosya adı/komut adı); arka plan işlemleri = süreç ağacı (komut satırı gösterilmez); web görünümü yalnızca 127.0.0.1, token+Host+Origin; ofis duvar kâğıdı Seçenek A (masaüstü penceresi), Aerial'e uygulanmaz.
**Failed attempts / dersler:** Chrome 403 (cross-site navigate; düzeltildi), web mobilya 404 (`furniture/` öneki; düzeltildi), `osascript quit` bazen kapatmaz (`killall Adalmon` + süreç saati doğrula; son kurulumlarda sorun çıkmadı), tam suite'te `PanelControllerTests/testOpenToggleSwitchAndEscape` ve `ProcessActionsTests/testTerminateAndForceKillChildProcess` ön plan/zamanlamaya bağlı kararsız (tek başına geçer), 4 fps pil animasyonu CPU'yu düşürmedi (asıl yük Süreçler sayfasıydı), animasyonun ilk "suçlusu" yanlış çıkmıştı, ajanın sahte DOM testi gerçek tarayıcı hatalarını yakalamadı (Chrome ile doğrulama şart).
**Constraints:** bu dosyada Constraints bölümü YOK; uydurmadım (kullanıcı kuralları global CLAUDE.md ve memory'de: branch açma, belirsizde AskUserQuestion, alt ajan en fazla Sonnet [bu session], secret taraması, disk temizliği vb.).
