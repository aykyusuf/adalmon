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
- "git geçmiinde de kalmasın bu arada sildiklerin" — takım kimliği/bundle id git geçmişinden de silindi (yeni kimlik/kişisel veri repoya ve geçmişe girmemeli).
- "iyice test etsene bak kesin çalışıp çalışmadıpnı anlayalım" / "çok garanti çalışması lazım" — ajan hattı ve ofis için gerçek zincirle (uçtan uca) test; edge durumlar ara ara kontrol edilmeli.
- "over engineering e gerek yok abarmtmaya çalış kendi sunucumuz var" ve "Sadece analiz et gel" — Windows/çok-PC sunucu işi: abartma, şimdilik yalnızca analiz (docs/WINDOWS-VE-SUNUCU-ARASTIRMA.md); kod yazma kararlar gelince.
- Silme komutlarında crew-chief guard: 5 satır SAFE/RISKY gerekçesi yaz, sonra aynı komutu tekrar çalıştır.
- "neden kendin yapıon paraler ajanlarla yapsana bitir işte" — işleri paralel ajanlarla yürüt (ayrı DerivedData, ajanlar commit/kurulum yapmaz).
- "salak salak yine çok önemli bi soru mu sordun sanki" / "askquestion ile sro" — küçük kararlarda durma, varsayılanı uygula; gerçek kararları metinle değil AskUserQuestion ile sor ve devam et.
- "kapanması gerkenleri tek tek sorsana bana askquestion ile bi de yeni işleri de tek tek sor" — görev kapatma ve yeni işleri AskUserQuestion ile tek tek sor.
- "filtre aktif değilse mobilde uyar ıversin olm ciddi bi şekilde" — filtre bağlı/aktif değilken mobilde ciddi uyarı.
- "firefox uyumluluğu da olmasın amk" — Temizlik'te Firefox desteği hiç olmayacak.

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

## Handoff (2026-11-09 gece, compact öncesi) — son kod commit'i bu bölümle birlikte (c2dbd5c + sonrası)
**Constraints:** dosyanın başındaki "Constraints" bölümü geçerli (kullanıcı kuralları kelimesi kelimesine); ayrıca global CLAUDE.md (branch açma, belirsizde AskUserQuestion, alt ajan ≤ Sonnet bu session) ve bu dosyadaki "Dersler" bölümü.

**Now (bitti, kurulu, push edildi, uygulama çalışıyor):**
- Kimlik: takım kimliği/bundle öneki repoda ve **git geçmişinde yok** (force-push + taze klonla doğrulandı); kendi değerler `Config/Identity.local.xcconfig` (gitignored), `tools/gen-identity.sh` Swift sabitlerini üretir. Yedek bundle scratchpad'de (eski geçmişi içerir; istenirse sil).
- Ofis: uykuda sistemi (30 dk boşta otomatik, elle küçült kalıcı, izin beklerken öne çıkar, sola süzülme animasyonu, sol kenar Stage Manager şeridi, hover küçült düğmesi), robot süpürge (vektör tema, macOS + web), tam ekran pano (saat ortada, paneller/düğme yalnızca hareketle), oda plaketi serif + ✦ model hapı (macOS + web).
- Ajan hattı sağlamlığı: test host'u gerçek `config.json`'u ezmiyordu → düzeltildi (`AppModel.start` testte `agents.apply()` çağırmaz; `AgentService.repairConfigIfNeeded` öne gelince onarır). Hat sağlık çipi + "Hattı test et". Alt ajan evlat edinme (SubagentStart kaçsa da), bayat alt ajan 45 dk, **süreç keşfi** (çalışan `claude` pid+cwd → "bekleyen oturum", Ctrl+Z `T` süreçleri atlanır, 30 sn/3 dk periyodik yeniden tarama), takılı "çalışıyor" 20 dk sonra boşta.
- **Boşta süresi kaynağı:** transkript DOSYASININ değişim zamanı DEĞİL; dosya içindeki son zaman damgalı kayıt (Claude Code dosyaya düzenli damgasız durum kayıtları yazıyor: last-prompt, custom-title, session-owner, bridge-session). Asyıldız 10,7 saat sessiz görünüp uykuya geçiyor.
- Pil: kalan süre anlık tüketimden (`BatteryRuntimeEstimator`, ≈). Duvar kâğıdı ofis arka planı "Otomatik". Tarayıcılar sayfası yeniden tasarım + sekme↔süreç RAM eşlemesi (CPU-delta probe; Safari için Develop > Apple Events'ten JavaScript'e izin gerekir). Süreçler'de tarayıcı alt süreç adları okunur.
- Doküman: `docs/WINDOWS-VE-SUNUCU-ARASTIRMA.md` (Windows portu + 3 PC'de ajan paylaşımı araştırması, **yalnızca analiz**).

**Next (sıra):** (1) kullanıcının canlı doğrulamaları: plaket görünümü, tam ekran pano, uykuda şeridi, hat sağlık çipi, Tarayıcılar sekme ölçümü (tasks.json: PLAQUE-01, PANO-02, DORM-01, HOOK-02, TABMAP-01, BROWSER-01). (2) Windows/sunucu işi **kararlar bekliyor** (SERVER-01): sunucu dili (Node/Go/Python), Windows'ta görünüm (tarayıcı/PWA mı tray mi), cloud oturumları dahil mi; sonra Faz 0 (Windows'ta hook komutunu elle deneme) → Faz 1. (3) Eski küçük işler: SAVER-01 (16:10'da Doldur/Sığdır), izin gerektiren testler (PERM-01), BATT-01 canlı doğrulama.

**Decisions:** alt ajan/oturum veri hattı = hook → 127.0.0.1 dinleyici (değişmedi). Uzak (çok-PC) tasarımda: hook `command` + `async` + `curl` (http tipi SessionStart desteklemez, senkron, 600 sn zaman aşımı); sunucu bellekte tutar (kalıcı log yok); pid yok → TTL; planlayıcıyı JS'e taşımak Faz 2; hesabın oturumlarını listeleyen resmi API yok, belgesiz OAuth API önerilmez. Manuel küçültme kalıcı (çalışırken de), yalnızca izin beklerken açılır. Plaket yazı tipi: Claude'un kendi fontları lisanslı olduğu için sistem serif (New York) kullanıldı.

**Failed attempts / dersler (doğrulanmış neden):** (a) testler gerçek config.json'u ezdi → ajanlar görünmedi (bkz. Dersler). (b) transkript mtime ile boşta süresi hesabı yanlış (damgasız durum kayıtları dosyayı sürekli değiştirir) → içerik zaman damgası. (c) Ctrl+Z ile durdurulmuş `claude` süreci oturum sayıldı → SSTOP atlanır. (d) elle küçültülen çalışan oturum geri açılıyordu + uygulanmayan küçültmede oda görünmez kalıyordu → düzeltildi. (e) Mac pildeyken Düşük Güç Modu açık: 7 `BatteryLiquidGlyphTests` animasyon testi düşer (fişteyken geçer, kod hatası değil). (f) Aynı DerivedData'da iki `xcodebuild` aynı anda koşturma (testler bozulabilir).

## Handoff (2026-11-11) — SETTINGS-BUG-01 kodu yazıldı, commit EDİLMEDİ
**Now:** Bellek eşiği sıfırlanma hatası düzeltildi (kök neden: `ComponentInspector` `.onChange(of: component.primary)` seçim değişimini düzenleme sanıyordu). Değişen dosyalar: `MenuBarComponent.swift` (ComponentFieldKey + applyPrimaryEdit), `ComponentInspector.swift`, `MenuBarSettingsTab.swift` (.id), `MenuBarConfig.swift` (Lossy bileşen çözümü), `MenuBarConfigStore.swift` (çözülemeyen kayıt yedeği), `PanelConfig.swift` (Lossy private→internal), `Tests/MenuBarConfigTests.swift` (+5 test). İlgili testler 46/46 geçti.
**Next:** (1) Uygulamayı kurup canlı doğrula (Gelişmiş düzenleyici: bellek eşiğini değiştir → başka bileşen seç → geri dön, eşik korunmalı). (2) Kullanıcı isterse commit (secret taraması). (3) Sonra MENUBAR-02+03, MEM-COLOR-01.
**Ders:** SwiftUI'de seçime göre değişen binding'e bağlı `.onChange` seçim değişiminde de tetiklenir; düzenleme tepkisini id+değer anahtarıyla sınırla ya da view'a `.id` ver.

## 2026-11-11 ~23:15 — MENUBAR-02/03 bitti (onay bekliyor); kullanıcı 45 dk yok
**Decisions:** Kullanıcı 45 dk için paralel ajanlarla şunları seçti: MEM-COLOR-01, SAVER-01, araştırmalar (MENUBAR-01, USAGE-01, CLEAN-01 — yalnızca rapor), canlı ekran testleri (kullanıcı yokken; ekran görüntüleri dönüşte onay için). Commit en sonda tek seferde. Menü çubuğu yedekleri: `~/Library/Application Support/Adalmon/MenuBarLayouts.json`; yıkıcı her işlem `MenuBarConfigStore.replaceConfig` üzerinden (yedek + geri al).
**Ders:** Hazır düzen her uygulandığında bileşenler yeni UUID alır; düzen karşılaştırmasında `MenuBarConfig.isSameLayout(as:)` kullan, `==` değil.

## 2026-11-11 ~23:30 — paralel tur sonucu
**Now:** MEM-COLOR-01 ve SAVER-01 kodlandı, test edildi, kuruldu (onay bekliyor). Araştırma raporu `docs/ARASTIRMA-2026-11-11.md`. Ekran testi ajanı (ui-tester) ekran görüntüsü alıyor → scratchpad/ui/.
**Open questions (kullanıcıya):** (1) Sığdır sabit resim duvar kâğıtlarına da uygulansın mı (şu an evet)? (2) Panel bellek basıncı renkleri menü çubuğundaki eşik renklerini mi izlesin (şu an evet, yalnızca eşik modunda) yoksa ayrı ayar mı? (3) USAGE-01: Claude statusLine betiği (kullanıcının kendi statusLine'ı ile çakışma) + Codex yerel belgesiz format kullanılsın mı? (4) MENUBAR-01 "Sırayı menü çubuğundan al" düğmesi yapılsın mı? (5) CLEAN-01 kendi küçük temizleyicimiz mi?
**Ders:** Tam suite'te `PanelControllerTests/testOpenToggleSwitchAndEscape` ve `SessionProcessSamplerTests/testRealLibprocSeesRealChild` kararsız (tek başına geçer).
**Ders (23:35):** Bu oturumda computer use araçları yok → ui-tester uygulamayı gezemedi. Görsel kontrol için opt-in snapshot testleri kullanıldı: `TEST_RUNNER_ADALMON_PREVIEW_DIR=<dir> xcodebuild test ... -only-testing:AdalmonTests/MenuBarFeaturePreviewTests` (kayıtlı düzenler + geri al şeridi, seviye renkleri editörü, menü çubuğunda Renksiz/varsayılan). Bulunan ve düzeltilen: Renksiz seçiliyken renk kutusu yeşil kalıyordu.
**Decisions (23:40, kullanıcı):** USAGE-01 ikisi de: Claude limitleri statusLine sarmalayıcı (kullanıcının mevcut statusLine'ı bozulmadan) + Codex yerel rollout okuması (format değişirse gösterge sessizce gizlenir). MENUBAR-01: "Sırayı menü çubuğundan al" düğmesi (tek seferlik okuma). CLEAN-01: kendi temizleyicimiz (tara → önizle → onay → Çöp; kalıcı silme yok), önce plan. Küçük açık sorular varsayılanla kaldı: Sığdır sabit resimlere de uygulanır; panel bellek renkleri menü çubuğu eşik renklerini izler.

## Handoff (2026-11-12 ~00:05) — usage limiti öncesi durduruldu; kullanıcı "başla" deyince devam
**Commit'li ve push'lu (kurulu):** SETTINGS-BUG-01, MENUBAR-02/03, MEM-COLOR-01, SAVER-01, araştırma raporu (son commit c2439de).
**Commit EDİLMEMİŞ çalışma ağacı (dikkat: ağaç şu an DERLENMEYEBİLİR):**
- MENUBAR-01 bitti (ilgili 65 test geçti) — commit/kurulum bekliyor.
- USAGE-01 kodu tam yazıldı ama hiç derlenmedi (tasks.json evidence'ta dosya listesi + sonraki adımlar).
- CLEAN-01 yarım: model/tarayıcı/çöp/UI yazıldı, derlenmedi; testler + sekme bağlama + project.yml yapılmadı. Plan: `docs/plans/CLEAN-01-plan.md`. Bilinen hata: `CleanupScanner.swift:79,85` escaping closure captures non-escaping 'isCancelled'.
**Next (sıra):** (1) CleanupScanner derleme hatasını düzelt → `xcodegen generate` → derle; USAGE dosyalarındaki derleme hatalarını düzelt. (2) USAGE-01 testleri (SubscriptionLimitsTests, AgentPluginTests, AgentWebTests, PanelConfigTests, AgentHTTPParserTests). (3) CLEAN-01 kalan adımlar (plan "Not started": ProcessesTab case cleanup, ProcessesPage, ProcessesTabTests:10, project.yml, Tests/CleanupTests.swift). (4) Tam suite (bilinen kararsızlar: PanelControllerTests/testOpenToggleSwitchAndEscape, SessionProcessSamplerTests/testRealLibprocSeesRealChild) → kur → secret taraması → commit+push. (5) Kullanıcı onayları: tasks.json'daki in_progress görevler.
**Kurallar (bu oturumdan):** paralel ajanlar ayrı DerivedData (`/private/tmp/claude-501/adalmon-dd-<ad>`), bitince sil; ajanlar commit/kurulum yapmaz, ana oturum yapar. Gerçek `~/.claude/settings.json` ve `ClaudePlugin/config.json`'a ajanlar/testler dokunmaz. Küçük kararlarda durma; önemli kararları AskUserQuestion ile sor.

## 2026-11-12 ~07:25 — Handoff tamamlandı
**Now:** MENUBAR-01, USAGE-01, CLEAN-01 kodlandı, test edildi (tam suite 1279/1282; 3 düşen bilinen kararsız), kuruldu, commit+push. Tüm in_progress görevler kullanıcı onayı bekliyor.
**Open:** Kurulum sonrası Adalmon CPU ~%4-5 (hedef <%1). `sample` profilinde Adalmon kodunda sıcak nokta yok (tüm thread'ler bekliyor); muhtemelen açık duvar kâğıdı/ofis çizimi. Ayrıca bakılmalı: duvar kâğıdı kapalıyken CPU ölçümü.
**Next:** kullanıcı onayları; USAGE-01 için Ayarlar > Claude ajanları > "Claude limitlerini bağla"; CLEAN-01 Süreçler > Temizlik canlı deneme; CPU konusu.
**Decisions (2026-11-12 08:10, kullanıcı):** Genel bakış = "Kompakt pano" (üstte tıklanabilir özet karoları, altta [Ağ|CPU|Bellek] sekmeli tek liste + aralık seçici + satırdan sınır, altta ince durum şeridi; kaydırmasız). Bildirimler: uygulama içi + isteğe bağlı sistem bildirimi (ikisi de seçilebilir). Yeni görevler: USAGE-02, NOTIF-01, MOBILE-LIVE-01, NET-LIVE-01, OVERVIEW-UX-01, ICON-01.
**Decision (2026-11-12, kullanıcı):** Canlı listede "Engelle" → "mobil mi Wi-Fi mı" diye sorsun (Mobilde / Wi-Fi'de / Her yerde). Önce mevcut kural motoruyla (filtre uzantısına dokunmadan) yapılacak; filtre değişikliği gerekirse kullanıcıya önceden haber + curl testi + otomatik geri alma.
**Ders (2026-11-12 08:20, doğrulandı):** Her kurulumda `CURRENT_PROJECT_VERSION=$(date +%s)` filtre sistem uzantısının da sürümünü değiştiriyor → macOS her seferinde yeni uzantı yüklüyor, eskiler "terminated waiting to uninstall on reboot" kalıyor ve uygulama yeni filtreye XPC ile bağlanamıyor (`bootstrap look-up ... No such process`, 07:32'den 08:17'ye). Sonuç: uygulama başına sayım ve hız sınırı/engel ayarları filtreye gitmedi. Kullanıcı Ayarlar › Filtre'den kapat-aç yaptı → düzeldi (curl 200, cfil 2, yeni satırlar geliyor). KURAL: Sources/Filter veya Sources/Shared değişmediyse kurulumda aktif uzantının sürümünü koru (`systemextensionsctl list` ile oku, aynı CURRENT_PROJECT_VERSION'ı ver); değiştiyse kullanıcıyı uyar, kurulumdan sonra bağlantıyı log'dan doğrula.
**Decision (kullanıcı):** filtre aktif/bağlı değilse mobilde ciddi uyarı versin.

## 2026-11-12 ~09:00 — Handoff
**Now:** Kuruldu + commit: USAGE-02 (limit tahmini), NOTIF-01 (uygulama içi/sistem/ikisi; varsayılan sistem), MOBILE-LIVE-01 + NET-LIVE-01 (60 sn…1 sa canlı liste, satırdan sınır, Mobilde/Wi-Fi'de/Her yerde engel), OVERVIEW-UX-01 (kompakt pano), ICON-01, FILTER-LINK-01 (yeniden bağlanma + mobilde kırmızı uyarı). Tam suite 1341/1344 (OfficeLiveArrival ×2 yük altında zaman aşımı, tek başına geçer; SessionProcessSampler/testRealLibprocSeesRealChild kararsız).
**Kurulum komutu (yeni kural):** aktif filtre sürümünü oku → `CURRENT_PROJECT_VERSION=<aktif>` ile derle (Sources/Filter|Shared değişmediyse) → kur → `log show ... "bootstrap look-up"` = 0, `curl` 200, `net.cfil.active_count` 2.
**Next:** kullanıcı onayları (tasks.json in_progress); eski Overview kart dosyalarının temizliği (testlerle birlikte); CPU %4-5 ölçümü (duvar kâğıdı kapalıyken).
**Open:** Wi-Fi'de engel ağ değişimine göre uygulanır (Adalmon kapalıyken son config kalır); tam çözüm FilterConfig'e yeni liste (uzantı değişikliği → kullanıcı onayı).
**Decision (2026-11-12, kullanıcı):** Günlük bütçe = günlük limit (örn. 3 GB). "Aylık kalan ÷ kalan gün" yalnızca bilgi/uyarı satırı; artık bugünün bütçesini düşürmez.
**Ders (2026-11-12 08:48):** Kurulum sırasında aynı saniyede iki Adalmon açıldı (ikisi de launchd'den; tek kopya koruması yoktu → iki menü çubuğu öğesi, iki dinleyici). Düzeltme: `AdalmonMain.main` başında `SingleInstance` (küçük PID kalır, büyük PID öncekini öne getirip çıkar). Kurulum kontrolüne `pgrep -x Adalmon | wc -l` = 1 eklendi.
**Decisions (2026-11-12 ~09:30, kullanıcı onay turu):** 12 görev kapandı (done). Açık: FILTER-LINK-01 (canlı görülmedi), USAGE-01 → USAGE-03 (limitler Genel bakışa), CLEAN-01 → CLEAN-02 (CleanMyMac tarzı tam bölüm; açık kaynak özellikleri araştırılıp kategori kategori kullanıcıya sorulacak; "erişim yok" çözülecek). Yapılacak: CPU ölç+düzelt, BATT-02, POLISH-01, OFFICE-CTRL-01 (önce plan). Ertelendi: Wi-Fi engelinin filtre tarafı çözümü.
**Ders (2026-11-12 ~10:00, doğrulandı):** Yerel proxy (SpoofDPI 127.0.0.1) üzerinden giden uygulama trafiği filtrede `.proxied` + global `expensive` bayrağıyla raporlanıyor → hotspot'tayken Mac'ten çıkmayan loopback baytları mobil sayıldı (09:00: uygulamalar 550 MB, arayüz 107 MB; Python 465 MB), yanlış "yüksek kullanım" uyarısı. Proxy'nin gerçek dış trafiği (`.proxyEgress`) UsageEngine'de atılıyordu. Düzeltme uygulama tarafında (egress'e göre paylaştırma + arayüz deltasıyla sınır + burst mobil bayttan).
**Decisions (CLEAN-02, kullanıcı):** sistem çöpü + geliştirici: hepsi (log, node_modules/.build, brew, Docker/Gradle/Cargo/CocoaPods, Chrome/Firefox/Edge önbelleği); silme: Çöp'e + kalıcı silme seçeneği de; tam kaldırıcı + artıklar (yetimler dahil); büyük/eski + kopya bulucu; tarayıcı geçmişi/çerez de; admin işleri: yalnızca bilgi + komut kopyala; treemap + Başlangıç sekmesini genişlet; kendi kodumuz (MIT/Apache kural listeleri, GPL kod yok) + doğru erişim akışı (Dosyalar ve Klasörler vs Tam Disk Erişimi, dönünce yeniden dene).
**Decisions (OFFICE-CTRL-01, kullanıcı 2026-11-12):** içerik: kontrol açıkken kartta hep gösterilir (komut/dosya/soru metni; yalnız bellekte, log yok); "Hep izin ver" = global (userSettings → ~/.claude/settings.json, her projede) — kullanıcı açıkça istedi; mesaj kutusu (Channels) şimdi değil; terminal diyaloğu bloklanıyorsa yalnız "Ofisten cevapla" işaretli oturumlarda 120 sn bekle. Plan: crew-chief reports office-ctrl-01-091745.md (Phase 0 spike önce).
**Decisions (CLEAN-02 plan soruları, kullanıcı):** Temizlik = yeni kenar çubuğu sayfası ⌘0 (Süreçler › Temizlik sekmesi kalkar); kalıcı silme işlem başına seçilir (2 onay, sonra Çöp'e döner); brew/Docker komutlarını Adalmon önizlemeyle çalıştırır (sudo yok); Firefox desteği HİÇ olmayacak (önbellek/gizlilik dahil). Paralel ajanlar tek çalışma ağacı + ayrı DerivedData. Plan: docs/plans/CLEAN-02-plan.md (Phase 0 + N önce, sonra 1-6 paralel, 7 son).
**Ders (2026-11-12 ~10:40):** Kurulumlar Debug'du (optimize edilmemiş). Artık `-configuration Release`, `CURRENT_PROJECT_VERSION=<aktif filtre sürümü>`, ürün `build/Build/Products/Release/Adalmon.app`. İmza aynı (Apple Development, BC62U5TGCQ), uzantı yeniden yüklenmez. Release açılışında `config.json` yeniden yazılabilir (port aynı kaldı, 56567 = dinleyici) — kontrol: config port == `lsof` dinleyici portu.
**Decision (2026-11-12, kullanıcı):** Video duvar kâğıdına dokunma (fps sınırı/eşik değişmez); pil sıvı animasyonu fişteyken şarj olmasa da çalışmaya devam etsin. Kalan idle CPU (~%7, pencere açık + video duvar kâğıdı) bu tercihlerin sonucu; CPU-01'in hedefi buna göre değerlendirilir.

## Handoff (2026-11-12, compact öncesi) — son commit eff4cb5, çalışma ağacı temiz
**Now:** Her şey commit+push+Release kurulu. Temizlik ⌘0 sayfası var ama alt bölümlerin çoğu "Yakında" (yalnız Sistem çöpü ve Başlangıç çalışıyor). Kullanıcı ⌥⌘0 (Ana pencere) kısayolunu onayladı; spike artıkları ~/.claude'dan silindi.
**Next (sıra):** (1) CLEAN-02 Phase 1-6 paralel ajanlarla (plan docs/plans/CLEAN-02-plan.md; Phase 0 + N bitti; Phase 1 ajanı başlatılıp kullanıcı tarafından durduruldu, değişiklik bırakmadı) → sonra Phase 7. (2) OFFICE-CTRL-01 uygulaması: her şey PermissionRequest hook'uyla (spike: terminali bloklamıyor), bekletme üst sınıra kadar (hook script cap < timeout, örn. 590/600 sn), terminal cevabı sonraki olaydan (PostToolUse/PermissionDenied) algılanınca kart düşer + bağlantı kapanır; eşleştirme session+agent+tool+input+prompt_id; içerik kontrol açıkken gösterilir; "Hep izin ver" = userSettings (global); mesaj kutusu yok. (3) Kullanıcı onayı bekleyenler: tasks.json in_progress (FILTER-LINK-01, USAGE-01/03, CPU-01, USAGE-FIX-01, POLISH-01, BATT-02, CLEAN-02, OFFICE-CTRL-01).
**Kurulum rutini:** Release + `CURRENT_PROJECT_VERSION=<aktif filtre sürümü>` → killall → ditto → open → kontroller: tek kopya, curl 200, bootstrap look-up 0, config port == dinleyici portu.
**Paralel ajan kuralları:** ayrı DerivedData `/private/tmp/claude-501/adalmon-dd-<ad>` (bitince sil), commit/kurulum yok, gerçek settings.json/config.json'a dokunma, filtre koduna dokunma, Firefox yok.


### 2026-11-12 öğleden sonra
**Now:** CLEAN-02 Phase 1–7 bitti (Temizlik'te hiçbir bölüm "Yakında" demiyor), OFFICE-CTRL-01 MVP uygulandı (varsayılan kapalı, plugin 1.5.0), Limitler detay sayfası + animasyonlu Genel bakış kartı + panel kartı. Bağımsız inceleme (silme + hook) kritik bulgu yok, 4 nit düzeltildi. Tam suite 1581 test, 3 bilinen kararsız (OfficeLiveArrival, SessionProcessSampler, AgentRealScriptEndToEnd yük altında; tek başına geçer). Release kuruldu (filtre 1794457926 korundu), kontroller temiz.
**Next:** (1) Kullanıcı onayları tek tek (AskUserQuestion): CLEAN-02, USAGE-03, OFFICE-CTRL-01 (önce gerçek oturumda: Ayarlar > Claude ajanları > Ofisten cevapla aç → plugin Güncelle → YENİ claude oturumu aç → izin/soru dene) + önceki in_progress'ler. (2) Açık küçük kararlar: Docker için yalnız `builder prune` mı yoksa `system prune` mı; Akıllı tarama riskli kartlarda sayı göstersin mi.
**Dersler (doğrulandı):** (a) `CODE_SIGNING_ALLOWED=NO` ile tam suite'te BundledLibraryTests çöküyor ve testlerin bir kısmı koşmuyor → tam suite imzalı (`-allowProvisioningUpdates`) koşulmalı. (b) `ditto` eski paketin üstüne kurunca widget appex'te silinmiş dosya kalıp imza bozuluyor → kurulumda eski paketi kenara al (mv), sonra ditto, sonra `codesign --verify --deep --strict`.

### 2026-11-12 öğlen (2)
**Now:** Limitler artık kenar çubuğunda ayrı sayfa (kısayolsuz; plan rozeti Claude Max 20x / ChatGPT Plus; 3D halkalar, hover eğilme; Genel bakış kartı bu sayfayı açar). Yer kaplayanlar: tek geçiş ağaç önbelleği (drill-down µs), 3D karolar + zoom geçişi. Akıllı tarama: tek "Tara", gereksiz build'ler ortak köklerde otomatik aranır (30 günden eski seçili). Test sunucusu artık menü çubuğu/Dock/pencere göstermiyor (kullanıcı "her seferinde 2 tane" şikayeti). Tam suite 1627 test, 2 bilinen kararsız (PanelControllerTests önde başka uygulama varken, SessionProcessSampler). Release kuruldu, tek kopya, kontroller temiz.
**Next:** kullanıcı onayları tek tek: Limitler sayfası (3D hover canlı bakılmadı), Yer kaplayanlar, Akıllı tarama, CLEAN-02, OFFICE-CTRL-01 (gerçek oturum denemesi), önceki in_progress'ler.
**Ders (doğrulandı):** Test sunucusu = Adalmon.app; testler sırasında menü çubuğunda/Dock'ta ikinci Adalmon görünüyordu → testte StatusBarController/DockMode/ana pencere yok, aktivasyon .accessory (.prohibited PanelControllerTests'i bozar). Kurulumda eski paketi `mv` ile kenara al (rm yerine), pkill sonrası süreç bitene kadar bekle.
