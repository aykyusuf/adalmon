# Adalmon arastirma raporu — MENUBAR-01, USAGE-01, CLEAN-01 (2026-11-11)

Salt okunur arastirma; kod/commit/build yok. Web kaynaklari asagida, "dogrulandi" = kodda/komut ciktisinda/cekilen sayfada gordum, "cikarim" = gormedim.

## 1) MENUBAR-01 — Cmd+surukle ile degisen sirayi okuma

**Karar: Dogrulanabilir ama kirilgan — "yapilabilir, onemli kosullarla" (pratikte: sadece kendi ogelerimizin GORECELI sirasi, dusuk guvenle).**

Kodda (dogrulandi):
- `Sources/App/UI/StatusBar/StatusBarController.swift:166-168` — her oge `NSStatusBar.system.statusItem(withLength:)` ile olusuyor, `autosaveName = "adalmon.<key>"`. Tek oge modunda tek, ayri modda widget basina bir NSStatusItem (satir 4 yorumu).
- Satir ~160: "NSStatusBar yeni ogeyi solun en sonuna ekler; sirayi korumak icin sagdan sola olustur" — yani uygulama su an sirayi kendi olusturma sirasiyla belirliyor; kullanici ayrica Cmd+surukleyince macOS konumu kendisi saklar.
- `buttonFrames()` (satir 189-194) zaten `button.window.convertToScreen(...)` kullaniyor.

Mekanizma (kismen dogrulandi):
- autosaveName verilince AppKit konumu `NSStatusItem Preferred Position <autosaveName>` anahtariyla UserDefaults'a yazar. Bu Mac'te baska uygulamalarda `NSStatusItem Preferred Position Item-0 = 170` gibi sayisal degerler gordum (dogrulandi: baska uygulama alanlari). Deger = menu cubugunun SAG kenarindan piksel uzakligi (cikarim; belgesiz). Anahtar Apple belgesinde YOK (Apple NSStatusItem sayfasi sadece autosaveName'in "konumu saklar" dedigini soyluyor) — belgesiz, surumler arasi degisebilir.
- Adalmon'un kendi domaininde anahtar var mi, bu oturumda dogrulayamadim (tests `adalmon.p6.*` gibi yuzlerce cop domain birakmis; ayrica `defaults` filtresi cok gurultulu). Ac nokta: gercek domainde `defaults read <bundle-id> | grep "Preferred Position"` ile elle bakilmali.
- Tahoe (macOS 26): Ayarlar > Menu Cubugu'nda ogeler artik acma/kapama listesi; Bartender/Ice gibi yoneticiler 26'da gorunurluk/konum raporlama sorunlari yasadi (heise, Ice issue #711, forum). Menu cubugu degisiklikleri nedeniyle `NSStatusItem VisibleCC Item-0` gibi ek belgesiz anahtarlar var (tek bir GitHub issue; cikarim).

Okuma yollari ve guvenilirlik:
1. `item.button?.window?.frame.minX` — canli ve belgeli API; ayni ekranda ogelerin GORECELI sirasini verir. Riskler: oge gizliyse / "menu cubugu kisaltildi" durumunda window ekran disina (x<0) ya da (0,0)'a gidebilir; cok monitorde her ekranda ayri; macOS 26'da gorunurluk raporu guvenilmez. Yalnizca kendi ogelerimizi karsilastirmak yeterli, mutlak konum gerekmez.
2. UserDefaults `Preferred Position` anahtarlari — belgesiz; yazilma zamani surukleme biter bitmez mi gecikmeli mi garanti degil; KVO ile izlemek mumkun ama tetik garantisi yok.
3. Bildirim: Surukleme icin ozel public bildirim YOK (bulamadim). `NSWindow.didMoveNotification` ogenin penceresine kayit edilebilir (cikarim: status item penceresi surukleme sirasinda yer degistirir, bildirim gelir; denenmedi). Yedek: `NSEvent`/zamanlayici ile 1-2 sn'de bir minX karsilastirma — pil onceligine (CPU <%0,5) uymaz; sadece panel/ayar acikken yoklama kabul edilebilir.

Nasil senkron olur (oneri):
- Ayarlarda "Sirayi menu cubugundan al" dugmesi: tiklayinca butun ogelerin `window.frame.minX` degerini oku, buyukten kucuge (sag = ilk) sirala, sirayi uygulama ayarina yaz. Surekli izleme yerine istek-uzerine okuma; CPU maliyeti sifir.
- Ters yon (uygulama sirasini macOS'a dayatma): Preferred Position yazmak belgesiz ve kirilgan; mevcut "sagdan sola olustur" + autosaveName yeterli. Dayatma onerilmez.
- Test: iki ogeyi elle yer degistir, minX sirasini logla; Tahoe'de gizli/kisaltilmis durumda (x<=0) oge filtrele.

Riskler: belgesiz anahtar; autosaveName degisince konum kaybi (cihaz kimligiyle anahtar uretiliyor, `StatusItemPlan.swift:44`); Tahoe'nin ogeleri gizleme/yeniden yerlestirmesi; kullanici sirasi ile uygulama ayarinin yarisi (son yazan kazanir kurali gerekir).

## 2) USAGE-01 — Abonelik limitleri ve kredi bakiyesi

**Karar: Claude ve Codex limitleri icin resmi/yerel yol VAR; kredi bakiyesi icin belgeli endpoint YOK.**

### Claude Code 5 saat / haftalik limit
- Statusline JSON girdisi resmi olarak `rate_limits.five_hour.used_percentage`, `rate_limits.five_hour.resets_at`, `rate_limits.seven_day.used_percentage`, `rate_limits.seven_day.resets_at` icerir (epoch saniye; yuzde 0-100). Sadece claude.ai Pro/Max/Ultra aboneliginde ve oturumdaki ilk API cevabindan sonra gelir; her pencere ayri ayri eksik olabilir; `resets_at` gecince pencere dusurulur. Kaynak: https://code.claude.com/docs/en/statusline (dogrulandi, cekilen sayfa; satirlar 193-194, 344). Ayrica gateway'de `rate_limits.spend_limit.*` (v2.1.251+).
- Hook payload'lari: ortak alanlar `session_id, prompt_id, transcript_path, cwd, permission_mode, effort, hook_event_name`; rate_limits/usage ALANI YOK (sayfanin ilk 100k karakteri okundu; kalan ~193k okunmadi — ac nokta). Kaynak: https://code.claude.com/docs/en/hooks.
- Sonuc: hook'lar yetmez. Cozum: Claude Code `statusLine` ayari ile calistirilan KUCUK bir betik; stdin JSON'dan sadece `rate_limits`'i alip 127.0.0.1 dinleyiciye POST eder (mevcut plugin kanali). Gizlilik kurali (STATUS "Decisions": komut/istem/dosya icerigi asla) korunur: yalnizca yuzde + resets_at gonderilir.
- Risk: kullanicinin zaten bir statusLine'i varsa cakisir (tek ayar). Plugin, kullanicinin mevcut betigini sarmalayip cikisini aynen gecirmeli; ya da kullaniciya sorulmali (AskUserQuestion). Veri, yalnizca Claude Code oturumu aciksa taze; kapaliyken son bilinen deger + resets_at ile "eski" etiketi gosterilmeli.
- `/usage` / `/status` ciktisi: interaktif TUI, makine-okur yol degil (dogrulanmadi).
- Yerel dosyalar: `~/.claude` altinda sadece adlar listelendi: `projects/` (transkriptler, icerik OKUNMADI), `stats-cache.json`, `policy-limits.json`, `telemetry/`, `state/`. Limit yuzdesi icin belgeli yerel dosya bulamadim (stats-cache icerigi okunmadi; ac nokta ama token sayimi icindir, aboneligin kalan limiti degil — cikarim).
- Yasak/imkansiz: claude.ai'nin dahili OAuth usage endpoint'i belgesiz → kullanici kurali geregi kullanilmaz.

### Codex (OpenAI) abonelik limiti
- Yerel kanit (dogrulandi, yapi okundu; plan/kimlik yazdirilmadi): `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` icindeki `token_count` olaylarinda `rate_limits` nesnesi var: `limit_id`, `primary{used_percent, window_minutes:300, resets_at}`, `secondary{used_percent, window_minutes:10080, resets_at}`, `credits{has_credits, unlimited, balance}`. Yani 5 saat + haftalik + kredi bakiyesi YEREL dosyadan okunabilir. Bu semada resmi belge bulamadim (belgesiz yerel format → surum degisince kirilabilir, Codex'in 12 Temmuz 2026'da 5 saatlik pencereyi gecici kaldirdigi bildirildi; `primary` olmayabilir).
- Resmi yol: `codex app-server` JSON-RPC `account/rateLimits/read` ve `account/rateLimits/updated` bildirimi, `rateLimits.primary/secondary{usedPercent, windowDurationMins, resetsAt}` (ucuncu taraf kaynaklar; "experimental"; resmi sayfa https://developers.openai.com/codex/app-server dogrulanamadi). `/status` oturum icinde yuzdeleri gosterir. Ayrica app-server, ChatGPT kimligiyle kendi cagrisini yapar → "belgesiz OAuth API" sayilabilir mi diye kullanicıya sorulmali; yerel dosya okumak bu riski tasimaz.
- Oneri: en son rollout dosyasinin son `token_count` olayini dosya izleme (FSEvents) ile oku; salt-okunur, ag yok.

### API kredi bakiyesi
- Anthropic: Usage & Cost Admin API (`/v1/organizations/usage_report/messages`, `/v1/organizations/cost_report`, gecmis harcama; Admin key `sk-ant-admin01-...`, bireysel Console hesabinda once organization kurmak gerekir; yeni yol "Usage and Cost Analytics API"). Kaynak: https://platform.claude.com/docs/en/build-with-claude/usage-cost-api (dogrulandi). Kalan on odemeli KREDI bakiyesi donduren belgeli endpoint bulunamadi.
- OpenAI: org kullanim/maliyet endpoint'i admin key ister (`/v1/organization/costs`), topluluk raporlari 404/0$ sorunlari; resmi bakiye endpoint'i yok (topluluk + CodexBar notlari; ucuncu taraf).
- Sonuc: "kalan kredi" gostermek belgeli API ile imkansiz; yapilabilir olan: aylik harcama (Admin key ile) + kullanicinin elle girdigi bakiye - harcama tahmini. Codex tarafinda `credits.balance` yerel dosyada var (ChatGPT kredileri, API kredisi degil).

### Minimum guvenilir yol
1. Claude: statusLine betigi → 127.0.0.1 → UI (esik uyarilari: %80/%95, resets_at geri sayim).
2. Codex: rollout dosyasindan `rate_limits` oku (uyarilar ayni motor).
3. API bakiyesi: ertelensin ya da Admin-key harcamasi + elle bakiye; "belgeli API'si yok" notu.

## 3) CLEAN-01 — Acik kaynak temizleyiciler

Adalmon LICENSE: MIT (dogrulandi, `LICENSE` ilk satir).

| Proje | Lisans | Bakim | Ne yapar |
|---|---|---|---|
| Mole (tw93/Mole) | GPL-3.0 (GitHub sayfasi; eski mirror README'ler MIT diyor — sonradan degismis, tarih dogrulanmadi) | Aktif: son surum V1.71.0, 2026-11-10 (GitHub API); ~74,6k yildiz | CLI: clean (onbellek/log/gelistirici artiklari, varsayilan Cop'u da bosaltir), uninstall, purge (node_modules vb.), installer, optimize, slim, analyze; `--dry-run`, whitelist, islem logu |
| Pearcleaner (alienator88) | Apache 2.0 + Commons Clause (para kazanmayi yasaklar; MIT ile uyumsuz ek kisit) | Durmus: "On hold", son commit 2026-06-22, son surum 5.4.3, 2025 sonundan beri neredeyse durgun | SwiftUI uygulama: uninstall, yetim dosya arama, Homebrew/PKG yoneticisi, Sentinel |

Mole'un GUI uygulamasi kapali kaynakli ticari (cekilen ozet, ucuncu taraf).

Guvenlik: Mole `clean/purge/installer` kalici siler (Cop'a atmaz); `uninstall/analyze/slim` varsayilan Cop'a gonderir; yol dogrulama ve sistem klasoru korumasi var ama gecmiste temizleyicilerin hatali yol siliciligi vakalari olagan risk (cikarim). Admin yetkisi gerektirebilir.

Entegrasyon secenekleri:
- Kod kopyalama: Mole GPL-3 → Adalmon MIT oldugu icin KOPYALANAMAZ (turev eser GPL olur). Pearcleaner Commons Clause → MIT ile bagdasmaz. Ikisi de reddedilir.
- CLI cagirma: ayri sureç olarak `mo` cagirmak (GPL "aggregate/arms-length") hukuken genelde turev sayilmaz ama kullanici ayrica kurmak zorunda, surum/cikti formati kontrolu yok, ve silme eylemini Adalmon'un onizleme/onay/Cop akisina baglamak zor (clean kalici siler). Onerilmez.
- Kendi kucuk temizleyicimiz, kurallari referans alarak (kural LISTESI/yol bilgisi gercek olgu; kod kopyalanmaz, kendi kelimelerimizle yazilir): onerilen.

**Oneri:** Kendi yazilan, kucuk ve guvenli temizleyici. Kapsam V1: `~/Library/Caches/<app>`, `~/Library/Logs`, Xcode DerivedData (projede zaten bellek notu var), npm/pip/brew onbellekleri; sadece kullanici alanı, TCC'li ve sistem yollari yok. Zorunlu akis: (1) tara ve boyut/yol onizlemesi, (2) kullanici onayi (secili ogeler), (3) `FileManager.trashItem` ile Cop'a tasi (kalici silme yok), (4) islem logu, (5) `--dry-run` esdegeri testler, izin listesi (allowlist) + yol sembolik baglanti kontrolu. Referans: Mole'un README'sindeki kural listeleri (GPL kodunu degil, hangi klasorlerin guvenli oldugu bilgisini ogren; emin degilsen lisans konusunu kullaniciya sor).

## Acik noktalar
- Adalmon'un gercek defaults domaininde `Preferred Position` anahtarlari ve Tahoe'de surukleme sonrasi minX davranisi denenmedi.
- Hook dokumaninin son ~193k karakteri okunmadi.
- Codex `rate_limits` yerel formati belgesiz; app-server resmi sayfasi dogrulanamadi.
- Mole'un lisansinin MIT'ten GPL-3.0'a ne zaman gectigi dogrulanmadi.

Kaynaklar: https://code.claude.com/docs/en/statusline ; https://code.claude.com/docs/en/hooks ; https://platform.claude.com/docs/en/build-with-claude/usage-cost-api ; https://github.com/tw93/Mole ; https://github.com/alienator88/Pearcleaner ; https://developer.apple.com/documentation/appkit/nsstatusitem ; https://github.com/jordanbaird/Ice/issues/711 ; https://heise.de/-11167978 ; https://community.openai.com/t/access-billing-balance-costs-via-admin-api/1383654 ; https://dev.to/ianlpaterson/how-i-track-claude-codex-and-gemini-quotas-from-one-script-36n5
