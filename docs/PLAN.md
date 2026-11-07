# Adalmon — Faz 2 planı (2026-11-06)

Kaynak araştırmalar: `/var/folders/qx/y4mg7k7x0sg4w7njh186vl3w0000gn/T/crew-chief-reports/features-171324.md` (+ `-corrections.md`), `.../dock-ui-171447.md`.

## Kullanıcı kararları (birebir)
- İlk paket: Mobil bütçe+tahmin, Uygulama detay paneli, Genel bakış = bugün özeti, Geçmiş sayfası + saatlik. "uygulama panelini de yeniden tasrlayalım çok güzel olsun".
- Panel yeniden tasarımı: **İkisi de** (menü çubuğu paneli + Dock'taki uygulama detay paneli). Menü çubuğu paneli yönü: **B: Kart ızgarası** (iStat tarzı 2x3 mini kart CPU/GPU/RAM/sıcaklık/↓/↑, altında kota çubuğu, altında top uygulamalar ▸).
- Dişli çark: "bu panel gelio dişli çark direk ayrı docktaki uygulamayı açsın" → dişli menü açmaz; Dock modunda ana pencereyi, değilse Ayarlar penceresini doğrudan açar. Menüdeki Yoğunluk / Sistem görünümü / Bölümler seçenekleri ayarlarda olmalı (eksikse taşınır).
- Koruma: Kademeli limit + Veri Tasarrufu modu. "bi uygulama mesela 10dk da ne kadar net yediyse ya da 60 dk da ona göre bi sınır belirleyebiliriz anlık bant daraltma ya da 3 saatliğine 4 gb ygibi ayrı sınrlar da koyabilelim , wifi de de yapılabilsin bu arada istersem".
- Kural ağı: **kural başına seç** (sadece mobil / tüm ağlar).
- Kural penceresi: **Sabit pencere** (pencere dolunca sayaç sıfırlanır, engel o zaman kalkar).
- SpoofDPI CONNECT peek geri dönüşü: **aynı filtre kurulumunda** (tek risk penceresi).

## Sıralama
### Faz A — yalnız app (ext versiyonu sabit: `CURRENT_PROJECT_VERSION=1793966788`)
1. Pil: pencere minimize/occluded iken `mainWindowVisible=false` (1 sn örnekleme durur).
2. Dişli çark yönlendirmesi + menü seçeneklerinin ayarlara taşınması.
3. Temel katman: Preferences (fatura dönemi başlangıç günü, kurallar, kademeli limit, allowlist), saatlik tablo (`usage_hourly`, CREATE IF NOT EXISTS, mevcut flush ile toplu yazım; ilk çalışmadan önce `usage.sqlite` yedeği), bütçe/tahmin hesabı, kural motoru (app tarafı, dakika ring buffer, sabit pencere, histerezis/min tutma süresi, testler). Çıktısı sadece `FilterConfig` (limits + blocked).
4. UI: Genel bakış özeti + toolbar + Cmd+1–4/Cmd+F; Uygulama inspector; Mobil sayfası (dönem, ETA, kümülatif grafik); Geçmiş sayfası (gün/hafta/ay + saatlik); Kurallar sayfası; menü çubuğu paneli kart ızgarası.
### Faz B — tek filtre kurulumu (kullanıcı uyarılır, watchdog açık, `net.cfil.active_count` + curl)
- `blockedAlways` (Wi-Fi dahil engel), Veri Tasarrufu allowlist (default-deny; SpoofDPI egress, Adalmon, DNS/mDNSResponder, temel daemon'lar asla engellenmez; engel orijin app'in loopback akışında, `.proxyEgress`'te değil), SpoofDPI CONNECT peek geri dönüşü.
- Yeni `FilterConfig` alanları iki yönlü toleranslı decode.

## Kurallar
- Uygulama işi Sonnet high ajanlar; ben orkestratör. Ayrı `derivedDataPath`. Commit yok (kullanıcı onayıyla).
- Pil: CPU < ~%1; gizli UI çizilmez.

## Faz A API (temel katman — UI sayfaları bunun üzerine kurulur)
Hepsi `Sources/App`; `Sources/Filter` ve `Sources/Shared` (XPC, `FilterConfig`) DEĞİŞMEDİ. Kural/merdiven çıktısı yalnızca mevcut `limits` + `blockedOnMobile` değerleridir.

**Ayarlar** (`Preferences`, UserDefaults; `init(defaults:)` enjekte edilebilir): `billingCycleStartDay` (1–28, varsayılan 1), `monthlyCapGB: Double?` (+ `monthlyCapBytes`), `tierLadder: TierLadderConfig` (enabled=false, warn 80 / slow 95 / cut 100, `slowDownBytesPerSec` 256 KB/s, `appliesTo: NetworkScope`, `protectedApps`, `cutTopCount` 10), `dataSaver: DataSaverConfig` (yalnız saklama; zorlama Faz B), `usageRules: [UsageRule]`.

**Kural modeli** (`Rules/`): `UsageRule{id,name,enabled,app,scope,trigger,action}`; `app` = `UsageBucket.app` = `AppLimit`/`blockedOnMobile` anahtarı (.app yolu ya da çalıştırılabilir yol). `NetworkScope` = `.mobileOnly | .allNetworks` (sayaç da buna göre: mobil-only yalnız `expensive` byte'ları sayar). `RuleTrigger` = `.rolling(minutes:bytes:)` (son N dk ≥ X; N ≤ 720) | `.fixedWindow(minutes:bytes:)` / `.fixedWindow(hours:bytes:)`. `RuleAction` = `.throttle(downBytesPerSec:upBytesPerSec:)` | `.block`.
- Sabit pencere: ilk kullanımda başlar, süre dolunca sayaç sıfırlanır ve eylem kalkar. Kayan pencere: tetiklenince en az N dk (en az 2 dk) tutulur; ancak pencere kullanımı eşiğin %80'inin altına inince kalkar; kalktıktan sonra 60 sn bekleme (titreme yok).

**Motor** (`AppModel.rules: RuleEngine`): bellek içi dakika halkaları (yalnız kuralı olan uygulamalar) + sabit pencere sayaçları; SQLite okumaz. Durum `Application Support/Adalmon/rule-state.json` (en çok 30 sn'de bir, `persistIfNeeded`). UI okuması: `model.ruleStatuses(now:) -> [RuleStatus]` (`phase`, `usedBytes`, `thresholdBytes`, `windowStart/End`, `secondsUntilReset`, `isEnforcedNow`, `pendingFilterSupport`), `rules.causes(for: app) -> [RuleCause]`, `rules.ladderStatus: LadderStatus` (level, percent, throttledApps, blockedApps, pendingFilterSupport), `rules.output`. `RuleEngine` `@Observable`; `revision` her sayaç değişiminde artar. Kural listesi UI'dan değişince `model.rulesDidChange()` çağır (yoksa sonraki ölçümde uygulanır).
- Birleştirme (`EffectiveConfigBuilder`): engel = birleşim (elle olanlar aynen/sırayla korunur); hız sınırı = yön başına en kısıtlayıcı. Kapsam karışıksa (elle yalnız-mobil + kural tüm-ağlar gibi) tek `onlyOnMobile` bayrağı ikisini ifade edemez: mobildeyken ikisi de geçerli, Wi-Fi'deyken yalnız tüm-ağlar olanlar (ağ değişince yeniden itilir). `prefs.appLimits` / `prefs.blockedOnMobile` ASLA yazılmaz.
- Adalmon'un kendisi ve `proxyOwnerPaths` (SpoofDPI) kural ya da merdivenle asla engellenmez/sınırlanmaz; merdiven ayrıca `/System`, `/usr`, `/bin`, `/sbin` yollarını ve `protectedApps`'i muaf tutar.
- Tüm-ağlar + ENGEL kuralı: mobilde `blockedOnMobile` ile uygulanır, Wi-Fi tarafı `pendingFilterSupport` (Faz B). Hız sınırı tüm ağlarda kodda destekli (`ThrottlePolicy.activeLimit` `onlyOnMobile=false` iken `expensive`'e bakmaz; saydam proxy `.any` on-demand) — gerçek Wi-Fi'de test EDİLMEDİ.
- Kural tetiklenince/kalkınca toast; tetiklenince bildirim (`AlertCenter.notify`). Yeni sınırlanan/engellenen uygulamanın bağlantıları mevcut reset yoluyla yenilenir (birden çoksa tek özet toast). Kademeli limit açıkken `AlertCenter.checkCap` (50/80/100) devre dışı; merdiven kendi bildirimlerini yollar (warn gün başına bir kez, yeniden başlatmada tekrarlanmaz).
- Açılışta durum (bugünkü toplamlar, dönem tabanı, kural durumu) yüklenene kadar (`rulesReady`) filtreye yapılandırma itilmez; ilk itme kıyas noktasıdır (açılışta sahte sıfırlama/gevşeme yok). Aylık limitin tuttuğu kademe gün sınırında bozulmaz (yalnız kademe düşünce uygulama listesi/kesme kümesi temizlenir).
- Hız sınırı proxy'si `updateProxyWanted()`: elle sınır, açık hız sınırı kuralı ya da açık merdiven varsa önceden kurulur (etkin duruma göre değil).

**Bütçe** (`Budget/BudgetCalculator`, saf): `model.budget(now:) -> BudgetSnapshot` (cycleStart/nextCycleStart, cycleUsed, remaining, daysLeft, `dynamicDailyBudgetBytes` = (aylık − bugünden önceki)/kalan gün (bugün dahil, gün içinde sabit), `effectiveDailyCapBytes` = min(günlük limit, dinamik), `todayRemainingBytes`, `etaRecentRate` / `etaAverageRate: CapETA` (.reached/.at(Date)/.notToday/.noData; GÜNLÜK limite göre) ve aylık limit varsa `etaBudgetRecentRate` / `etaBudgetAverageRate` (dinamik bütçeye göre, yoksa nil), `projectedCycleBytes`). `model.todayMobileCumulativeSeries() async -> [CumulativePoint]` (saatlik arayüz toplamlarından). Gün anahtarı hesabı `UsageStore.keyCalendar` (GMT) — bkz. aşağıdaki not.

**Saatlik depolama** (`UsageStore`): tablo `usage_hourly(hour, app, domain NOT NULL DEFAULT '' ('' = alan adı yok), mobile, bytes_in, bytes_out)`; mevcut flush ile `add(day:rows:hourly:)` tek işlemde. Alan adı `DomainGrouper` grubudur (ham host değil). Fiziksel arayüz saatlik toplamları ayrılmış `app = "__iface__"` satırlarıdır (bytes giriş+çıkış `bytes_in`'de); grafikler/uygulama listeleri bunu ayırır. Açılışta 60 günden eski satırlar silinir (`pruneHourly`). Sorgular: `interfaceHourly(from:to:)`, `appsHourlyTotal`, `hourlySeries(app:from:to:)`, `topApps(hour:limit:)`, `hourlyDomains(app:hour:)`, `dailyTotals(fromDay:toDay:)` (arayüz), `dailySeries(app:fromDay:toDay:)`, `topDomains(app:fromDay:toDay:limit:)`, `interfaceBytes(fromDay:toDay:mobile:)`. `UsageStore(path:)` test için; varsayılan yol testlerde (XCTest host) geçici dizindir (`AppEnvironment`).

**Gün sınırı (yerel saat):** `UsageStore.dayKey(_:calendar:)` ve `UsageStore.keyCalendar` kullanıcının yerel saat dilimini kullanır (Gregoryen, `yyyy-MM-dd`); "bugün", günlük limit sıfırlaması ve kural/merdiven gün değişimi yerel gece yarısındadır (DST günleri 23/25 saat, takvim aritmetiğiyle). `UsageEngine` ve `AlertCenter` `calendar:` enjekte eder (testler Europe/Berlin kullanır). Saatlik tablo epoch saat başı anahtarlıdır; günün saatleri yerel gün sınırlarıyla gruplanır. Eski satırlar GMT günlerine göre yazılmıştı ve taşınmadı: geçiş günü bugünün toplamı yerel ve GMT satırlarını ayrı görür (yalnız o gün örtüşür/eksik görünür).

## Faz 3 (2026-11-07) — kullanıcı istekleri
- "dünün falan da ağ kayıtlarını görebileyim ne ne kadar harcamış rapor alabileyim genel olarak kısaca" → Geçmiş'te gün/aralık raporu (top uygulama + alan adı, eski günler `usage` günlük tablodan).
- "ram'i o an ne çok yiyor cpu gpu'yu ne yiyor düzgün isimlerle görebileyim" → Süreçler sayfası (canlı, yalnız görünürken).
- "uygulama açıldığında büyük açılsın pencere olarak biraz doldursun" → ilk açılışta ekranın büyük kısmı.
- "ram gpu cpu'yu çok yiyen ya da son 1 / 6-12 / 24 saatte diski de çok dolduran uygulamayı da görebilelim, ne doldurdu nerede" → arka plan süreç kaydı **dakikada bir** (CPU süresi, RAM, GPU süresi, disk yazma; 7 gün), disk "nerede" için **yazan uygulama + saatlik klasör taraması** (büyüyen klasörler).
- "mevcuttaki düzeni bozmamaya çok dikkat et".

## Faz 4 (2026-11-07) — kullanıcı istekleri
- Süreçler: geniş pencerede sütunlar sağa yapışıyor; değerler "pat diye" değişiyor, açılır satırlar animasyonsuz → yumuşak geçişler, sabit sıralama; Performans sekmesi açılınca geçmişi anında göstermeli; tüm grafiklerde hover ile değer/zaman (interaktif).
- Juicy benzeri pil özelliği, "en az onun her şeyini karşılayacak, görsel olarak en az o kadar hatta daha iyi": menü çubuğunda Mac + iPhone pili, şarjdan çıkınca kalan dakika / şarjda dolma süresi, sağlık/döngü/sıcaklık, güç akışı (adaptör W, kablo), kapasite mAh, enerji yiyen uygulamalar, geçmiş grafikleri (seviye, günlük enerji, ekran süresi, kapasite, döngü, sıcaklık), iPhone/iPad pil detayları, Bluetooth cihaz pilleri, uyarılar (düşük/dolu/takıldı-çıkarıldı, ekran ortası balon + kenar parlaması), widget'lar, Kestirmeler. Önce web + API araştırması.
- Kararlar (2026-11-07): iPhone/iPad detay → **libimobiledevice** (LGPL, dinamik bağlama + kaynak notu); şarj sınırı / düşük güç modu / MagSafe LED → **root SMAppService yardımcı, EN SON aşamada** (güvenli varsayılanlar + kapatma); AirPods → **canlı BLE taraması, yedek: sistem önbelleği (system_profiler)**; pil geçmişi **dakikada bir** + tak/çıkar anında. Araştırma: crew-chief-reports/adalmon-battery-research-104328.md. Kullanıcı: "sorularını AskUserQuestion ile sor, direkt yap".
- Backlog (kullanıcı geri bildirimi 2026-11-07): terminal (Warp/Terminal/iTerm) altındaki süreçleri ayrı göster ("Warp › xcodebuild"); aynı adlı iki uygulama (ör. /Applications/Adalmon ve DerivedData test host) yol ipucuyla ayırt edilsin; grup satırında PID = ana süreç + "+N" (yapıldı, kurulmadı); disk boş alan grafiği taşması (yapıldı, kurulmadı).
