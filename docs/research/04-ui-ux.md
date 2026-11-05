# r4: Menu bar sistem monitoru, UI/UX arastirma raporu (macOS 26 / 27, 2026)

Not: DOGRULANDI = kaynakta gordum (arama ozeti). CIKARIM = kendi bilgim/yorumum, dogrulanmadi.

## 0. "Usage" hangi uygulama?
- DOGRULANDI: "Usage: System Activity Monitor", gelistirici Oleh Stasula, Mac App Store id1561788435, macOS 14+, ucretsiz + Pro Lifetime IAP. Pil, CPU, bellek, ag, disk; Product Hunt listesinde GPU/fan/iCloud sync. iMore (Agu 2021): 19 menu bar bileseni + 13 popover widget'i, ozellestirme artisi. Product Hunt lansmani 2 Sub 2025, 482 upvote.
  - https://apps.apple.com/cn/app/id1561788435
  - https://www.imore.com/usage-cool-new-system-activity-monitor-your-mac (2021, sayilar eski)

## 1. Teknik mimari
### 1.1 MenuBarExtra vs NSStatusItem + NSPanel
- DOGRULANDI (MenuBarExtraAccess README): MenuBarExtra icin sunum durumu, NSStatusItem ve pencere erisimi icin birinci taraf API yok; orchetect/MenuBarExtraAccess Bool binding ile saglar. `.menu` stilinde acik menu run loop'u bloke eder.
- DOGRULANDI (mjtsai, Haz 2025): SettingsLink MenuBarExtra icinde guvenilmez, `openSettings` macOS 15'te calisiyor, Tahoe'de calismiyor.
- DOGRULANDI (macOS 27 beta, KRITIK): `.window` stilli MenuBarExtra artik status button target/action kullanmiyor, AppKit'in ozel "expanded interface session" mekanizmasina gecti (`NSStatusItem.expandedInterfaceDelegate`). MenuBarExtraAccess kirildi; PR #26 acik; tekrarlanan programatik acma sessizce basarisiz olabiliyor. https://github.com/orchetect/MenuBarExtraAccess/pull/26
- DOGRULANDI (Apple Forum, macOS 27 beta): status item view hover (FB23329983, beta 5'te duzeldi); `button.highlight(true)` etkisiz (FB23330269, kismi cozum expandedInterfaceDelegate); `occlusionState` artik gizli menu bar gorunurlugunu yansitmiyor (FB23349447); ozel NSPanel'de dokunmatikle disari tiklama algilanamiyor (FB23688090, tek yol didResignKey). https://developer.apple.com/forums/thread/836113
- DOGRULANDI: Remotion ekibi MenuBarExtra'yi yetersiz bulup NSStatusItem + SwiftUI hosting view'a gecti. https://multi.app/blog/pushing-the-limits-nsstatusitem
- ONERI (CIKARIM): cekirdek NSStatusItem + kendi NSPanel (borderless, nonactivating) + SwiftUI icerik (NSHostingView); macOS 27 icin expandedInterfaceDelegate uyumlulugu `responds(to:)`/#available arkasinda. MenuBarExtra yalniz prototip. Birden cok bagimsiz item (CPU/RAM/Ag ayri) ve kullanici ayariyla dinamik item sayisi NSStatusItem ile kolay (sahne sayisi derleme zamaninda sabit).
- Paketler (adlari biliniyor, guncel surum/macOS 27 uyumu DOGRULANMADI): sindresorhus/Settings, LaunchAtLogin-Modern, KeyboardShortcuts, Defaults. SMAppService.mainApp.register() dogrudan kullanilabilir.

### 1.2 Status bar'da canli metin/sparkline
- DOGRULANDI (zenn.dev/kyome): `NSImage(size:flipped:drawingHandler:)` SwiftUI yeniden cizim dongusunden bagimsiz, appearance degisiminde otomatik yeniden cizilir. https://zenn.dev/kyome/articles/58d89dc746e0dc
- DOGRULANDI (Apple Forum 771535): MenuBarExtra label'inda ozel cizim farkli render olur; ImageRenderer ile boyutlu image onerilir.
- CIKARIM: tum item'i tek NSImage olarak ciz (22pt yukseklik), iki satirli stacked ag metni + mini grafik; `isTemplate=true` ile acik/koyu otomatik; renkli esik gostergesi icin ayri non-template katman. Genislik titremesi: `NSFont.monospacedDigitSystemFont`, birim icin sabit sutun, `statusItem.length`'i hysteresis ile guncelle; metin degismediyse yeniden cizme; Core Graphics ImageRenderer'dan ucuz.
- Tahoe seffaf menu bar (DOGRULANDI: MacStories, Jason Deegan, MacVector): varsayilan seffaf + koyu gradyan; acik duvar kagidinda ikonlar zor okunur; "Display Menu Background" opak Sequoia gorunumunu geri getirir; 26.1'de Tinted modu. Ucuncu taraf item'lari renklendirme/kontrast API'si BULAMADIM. Sonuc: tek renk template metin + kucuk renkli vurgu (nokta/cubuk); seffaf/opak, acik/koyu duvar kagidinda test et.
  - https://www.macstories.net/stories/macos-tahoe-the-macstories-public-beta-preview/
  - https://jasondeegan.com/?p=12606
- Bjango (DOGRULANDI): calisma alani 22pt, 16x16pt ikon, devre disi ~%35 opaklik. https://bjango.com/articles/designingmenubarextras/
- Apple HIG "The menu bar": extras sagda, kisa basliklar; menu bar extra'ya ozel ayrintili bolum yok. https://developer.apple.com/design/human-interface-guidelines/the-menu-bar

### 1.3 Uygulama bazli ag
- DOGRULANDI: process basi ag icin public API yok; `nettop` yetkisiz calisir, ozel NetworkStatistics framework'unu kullanir. `nettop -P -n -L 1 -x` CSV: `name.pid,,iface,state,bytes_in,bytes_out`. Degerler kumulatif (iki ornegin farki = hiz); isimler 15 karaktere kesilir (pid ile anahtarla); tarayici helper surecleri ana uygulamaya toplanmali (NetSpeed boyle yapiyor).
  - https://github.com/oxcod/netspeed
  - https://emmanuelochem.lovable.app/writing/macos-per-process-network-stats
- DOGRULANDI (vendor iddiasi): NetPulse, DataCever, Bytetally "observe-only Network Extension" kullaniyor (tek seferlik onay, VPN/proxy atfi). Little Snitch kendi ag monitorune sahip.
- CIKARIM: nettop alt sureci = notarized DMG dagitiminda izinsiz; Mac App Store sandbox'inda muhtemelen olmaz. Oneri: v1 nettop, v2 istege bagli Network Extension "Hassas mod".

## 2. Liquid Glass (macOS 26)
- DOGRULANDI: Xcode 26 ile yeniden derleme toolbar, sidebar, menu bar, Dock, NSPopover, sheet'lere otomatik cam verir; MenuBarExtra/ozel NSPanel'in alip almadigi kaynaklarda YOK (acik).
- DOGRULANDI (Apple, macOS 26.0+): `GlassEffectContainer` birden fazla `glassEffect(_:in:)` sekli gruplar; cam camdan ornek alamaz, iliskili ogeler tek container'da; ic ice konmaz; `.interactive()` yalniz etkilesimli ogelerde; #available + fallback. https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- 3. taraf rehberler: cam kontrol/gezinme katmanidir, icerik arka plani degil, her yuzeye uygulama.
- CIKARIM: panel govdesi cam (`NSGlassEffectView` veya `.glassEffect(.regular, in: RoundedRectangle)`), grafik alanlari duz kalsin, segment secici/ayar dugmeleri cam; `.contentTransition(.numericText())`, `.smooth` spring, reduceMotion kontrolu. Liquid Glass okunabilirlik sikayetleri surmekte (WebProNews, tek ikincil kaynak: macOS 27'de iyilestirme bekleniyor, dogrulanmadi).
- SF Symbols 7, Swift Charts yenilikleri, UserNotifications HIG: bu turda ARASTIRILMADI.

## 3. Rakipler ve geri bildirim
- iStat Menus 7: Setapp %97 onay (~5.3k); TidBITS v6'ya gore CPU kullanimi %20'ye kadar; Sweet Bits dogru + hafif. Sikayetler (anekdot, bazilari 2024): arayuz v6'dan kotu/ayarlar karmasik (Bjango saat ayarlarinin zorlastigini kabul etti), yeni macOS'a uyum gecikmesi (7.3/7.5 Setapp), M5 destegi eksik, hava durumu konumu, 7.10'da cikis/kaldirma sorunu iddiasi.
  - https://macrumors.com/2024/07/31/istat-menus-7-0-brings-new-features/
  - https://mjtsai.com/blog/2024/08/01/istat-menus-7
  - https://setapp.com/apps/istat-menus/customer-reviews
  - https://tidbits.com/?p=67835
- Stats (exelban): acik kaynak, CPU/GPU/RAM/disk/ag/sensor/pil; CPU'da surec listesi, ag arayuz bazli (uygulama bazli degil), guncel v2.12.x. Issue'lari okumadim. https://github.com/exelban/stats
- Usage: moduler bar bilesenleri + popover widget'lari, ozellestirme ovgusu, Pro lifetime.
- Notch/kalabalik (blog/forum, kalite karisik): fazla ikon varsa notch'a yakin ogeler sessizce gizlenir; Tahoe yerlesik gizleme sunar; 26.3 sonrasi Bartender/Ice/Dozer ikon kaybi raporlari (Apple Community, tekrarlanamadi); item araligi 12->6 hilesi 30-40px kazandirir (resmi degil). https://discussions.apple.com/thread/256265881 ; https://badgeify.app/how-to-fix-mac-menu-bar-icons-disappearing-behind-notch/
- Sonuc (CIKARIM): iStat'in acik bosluklari "ayar karmasikligi + macOS uyum gecikmesi"; sade ayar + gun-1 macOS 27 destegi farklilastirici. Tek kompakt item varsayilan olmali.

## 4. Oneri (CIKARIM, urun karari)
### Menu bar varyantlari (varsayilan A)
- A "Tek Kapsul" (~90-110pt): mini CPU/GPU halka veya 2 ince cubuk + iki satirli stacked `↑ 1.2 MB/s` / `↓ 14 MB/s` (9-10pt, monospacedDigit, sabit sutun).
- B "Metin": `CPU 23%  RAM 61%  ↓14 ↑1.2` sabit genislik hucreler.
- C "Grafik": 28pt CPU alan sparkline + ag sparkline.
- D "Ayri item'lar": CPU/RAM/Ag ayri; notch riski uyarisi.
- Renk: normal template; >%70 amber nokta, >%90 kirmizi nokta; renk tek basina bilgi tasimasin.

### Panel (~340pt, cam, kaydirmasiz, Esc kapatir)
1. Baslik: Mac modeli/uptime, ayar + pin dugmeleri (cam).
2. 2x2 kartlar CPU/GPU/RAM/Disk: buyuk sayi (numericText), 60 sn alan sparkline, esik rengi; tikla = bolum genisler.
3. Ag: yukari/asagi canli grafik, bugunku toplam; "Uygulamalar" ilk 5: ikon, ad, ↓/↑, mini cubuk; hover ayrinti, sag tik eylemler.
4. Surec listeleri CPU/RAM/GPU (segment secici).
5. Alt serit: sicaklik/fan, pil, uyari ozeti.
- Hover'da grafikte deger balonu (Swift Charts chartXSelection, CIKARIM).
- Ayarlar: 3 sekme (Gorunum/Moduller/Uyarilar), canli onizleme, 5-6 preset + gelismis bolum.
- Bildirimler: sure esikli ("CPU %90 ustu 2 dk"), cooldown, "Surecleri goster" eylemi; varsayilan kapali, opt-in.
- Izin onboarding: nettop izin istemez; Network Extension istege bagli, tek ekran "neden"; menu bar'da Cmd-surukle ipucu.
- Kisayollar: global panel acma (KeyboardShortcuts). Login: SMAppService, `.requiresApproval` durumunda Sistem Ayarlari baglantisi.
- Performans hedefi: bosta <%1 CPU, panel kapaliyken grafik cizimi yok, ornekleme kapaliyken 2-3 sn, acikken 1 sn.

## Acik noktalar
- Reddit/HN okunmadi (arama araci Reddit dondurmedi); geri bildirim forum/Setapp/blog kaynakli.
- Usage'in guncel Tahoe UI'i, fiyati, ekran goruntuleri incelenmedi.
- MenuBarExtraAccess PR #26 durumu, macOS 27 final davranisi belirsiz (beta).
- GPU/sensor veri kaynaklari (IOKit/SMC/powermetrics) bu turda arastirilmadi.
- Not: istenen yola (scratchpad/r4-ui-ux.md) yazma crew-chief hook'u tarafindan engellendi; rapor bu dosyada.
