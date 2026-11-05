# Adalmon menu bar stil katalogu: arastirma raporu (2026-11-05)

Kapsam: Stats widget kaynak kodu, iStat Menus 7, Usage, Bjango menu bar extra makalesi, Tahoe. Hicbir proje dosyasi degistirilmedi.

## A. DOGRULANMIS BULGULAR

### A1. exelban/Stats widget'lari (kaynak: github.com/exelban/stats, Kit/Widgets/*.swift, raw.githubusercontent.com uzerinden okundu)
Dizin: BarChart, Battery, Dot, Icon, Label, LineChart, Memory, Mini, NetworkChart, PieChart, Speed, Stack, Tachometer, Text (listeleme "daha fazla" baglantisi gosteriyordu, eksik olabilir).
NOT: Constants.Widget.height/width/margin/spacing sayisal degerleri okudugum dosyalarda (helpers.swift, types.swift) bulunamadi. Asagidaki "X + margin" ifadeleri bu yuzden sembolik. Menu bar calisma alani 22pt oldugundan height buyuk ihtimalle 22 (cikarim).

| Widget | Boyut | Font | Secenekler (Store anahtarlari) |
|---|---|---|---|
| Mini | genislik 31 (etiketli) / 36 (etiketsiz) + 2*margin.x | deger: system 12 regular (etiketli) / 14 (etiketsiz); etiket: system 7 light, y=12, h=7 | label (bool, varsayilan true), color, alignment (left/center/right). Deger metni `Int(round2(v)*100)+"%"`. Renk: systemAccent, utilization (zones varsayilan 0.6/0.8), pressure, monochrome (koyu modda beyaz), ozel NSColor. Varsayilan renk monochrome |
| LineChart | grafik genisligi history'ye bagli: 30->24, 60->32, 90->42, 120->52; etiketli +6+spacing; yukseklik = height-2*margin.y | etiket: 7 regular, 3 harf dikey yigilmis (hucre 6pt genis, yukseklik/3); deger: 8 regular sagda | box (varsayilan true, dolu yuvarlak dikdortgen, radius 2), frame (sadece cizgi, box ile karsilikli dislayan), value, label, valueColor, color (varsayilan systemAccent), historyCount 30/60/90/120, scale (none/linear/...). Cizgi kalinligi 1/backingScaleFactor, offset yarisi. Box acikken monochrome rengi tersine doner |
| BarChart | sabit gruplar: 1 bar 10, 2 bar 22, 3-4 bar 30, 5-8 bar 40, 9-12 bar 50, 13-16 bar 76, 17-32 bar 84, >32 118; etiket sutunu +6 | etiket 7 regular dikey | box/frame, label, color. Bar araligi 0.5pt, segment istifleme (ic ice diziler), segment bazli renk override |
| PieChart | kare, kenar = height-2*margin.y; etiketli +8+spacing (draw) / +6 (toggle): kaynakta tutarsizlik | etiket WidgetLabelView (font dosyada yok) | label, monochrome ("Monochrome accent": renkler grayscaled()). Ornek segmentler: CPU kirmizi+mavi, RAM mavi/turuncu/pembe |
| NetworkChart | grafik 30->22, 60->30, 90->40, 120->50 | etiket 7 regular | iki tarafli: upload ust, download alt (reverseOrder takas), orta cizgi, her seri kendi max'i ile olcekli, dolgu alpha 0.5, varsayilan indirme .secondBlue, yukleme .secondRed, box/frame/label, history, scale |
| Speed | baslangic 58, sonra dinamik. Tek satir deger 58 (birimli) / 32 (birimsiz); iki satir 48 / 30 | tek satir: 11 regular; iki satir: 9 light; ikon char: 12 (tek) / 9 (iki) | icon: dots/arrows/chars/none (nokta 8pt tek satir, 6pt iki satir; ok aci pi/5), mode oneRow/twoRows, displayValue io/oi/i/o, valueAlignment, iconAlignment, units, base byte/bit, monochrome, valueColor (none/transparent/default/renk), iconColor, indirme/yukleme renkleri. Deger <1024 iken "transparent" -> .clear (bosta sonmus gorunum) |
| Stack (sensor) | sabit: tek satir 45, iki satir 32; otomatik: `width.rounded(.up)+2`, 2pt'den fazla degisince yeniden boyutla | tek satir 13 regular; iki satir 10 light; monospacedDigitSystemFont secenegi | mode auto/oneRow/twoRows, static width, monospaced font, alignment. Iki satirda ciftler halinde yigilir. Metin onbellegi 256 |
| Memory | genislik 50, etiket sutunu 8 | 9 light, sagda | iki satir "F:" (bos) ve "U:" (kullanilan) metin (bar DEGIL), symbols, orderReversed, renk modlari (accent/utilization/pressure/monochrome). Free satiri `(1-p).usageColor()`, used `p.usageColor()` |
| Tachometer | pie ile ayni kare, +etiket | yay cizimi TachometerGraphView'da (okunmadi) | label, monochrome; renk segmentleri |
| Battery | govde 22x12 (XL 26x14), radius 2, ic dolgu max 18x8, cikinti 2x4, kenar 1pt, ana hat textColor alpha 0.5, sarj simgesi 9x18 | tek satir 12 regular; iki satir 9 regular; ic yuzde 8 bold (XL 9) `.destinationIn` ile oyuk | additional (none/percentage/time/percentageAndTime/innerPercentage...), colorize, XL, chargerInside, hideAdditionalWhenFull |

Ortak desenler (dogrulandi): etiket 3 harf dikey yigin 7pt; hairline cizgi 1/scale; box radius 2; renk modlari enum'u (systemAccent, utilization, pressure, monochrome, ozel); pressure rengi Normal=systemGreen, Warning=systemOrange, Critical=systemRed (Kit/types.swift); renk bolgesi tipi `(orange, red)`, varsayilan 0.6/0.8; widget `setWidth` ile dinamik genislik; `Int(...)` ile kesme (yuvarlama degil).

### A2. Bjango "Designing macOS menu bar extras" (https://bjango.com/articles/designingmenubarextras/)
- Bar yuksekligi: 19 (System 1) -> 21 -> 22 (Yosemite) -> 24 (Big Sur). Notch'lu MacBook Pro 37pt; olcekleme ile 27-43pt.
- Extra calisma alani sabit 22pt, daha yuksek olamaz. Yuvarlak oge icin 16x16pt sistem ogeleriyle benzer agirlik. Dikey ortalamak disinda padding kullanma.
- Template image: renk yok sayilir, sadece alfa kullanilir; macOS acik/koyu icin otomatik boyar. Tek renk ciz, golgeleme icin opaklik kullan; Apple devre disi icin ~%35 opaklik kullanir.
- Tam renkli extra de mumkun. Kodla cizim dinamik icerik icin uygun.
- "Reduce transparency" bari duz gri yapar; ogeni bu modda da test et.
- Makalede YOK: font boyutlari, iki satir yazi, genislik titremesi, Tahoe. (Bu konularda istenen 9-10pt vb. dogrulanamadi; Stats iki satir icin 9-10pt kullaniyor, o dogrulandi.)

### A3. iStat Menus 7 (macrumors.com/2024/07/31/istat-menus-7-0-brings-new-features/, bjango.com/mac/istatmenus/)
Sadece arama ozeti goruldu, Bjango dokumanlari dogrudan okunamadi: 7.0'da her oge kendi ayarlariyla menu barda; birlesik mod yeniden yazildi; varsayilan tema birincil rengi macOS accent renginden alir; CPU icin "dual line label and bar" modu ve "stacked labels and values" modu eklendi; menu temalari ve arka plan renkleri var. Tam grafik/tema katalogu DOGRULANAMADI.

### A4. Usage (Oleh Stasula)
Arama ozeti (App Store, alternativeto, 2022 Mac Format): 30+ secilebilir menu bar bileseni, renk/grafik turu/yenileme hizi ayari. Ayrintili stil katalogu dogrulanamadi (uygulama okunmadi).

### A5. Kullanici algisi
iStat Menus "en yapilandirilabilir ve cilali" (ucretli), Stats "ucretsiz, modulerlik, widget secenekleri", MenuMeters "ucretsiz, temel grafikler, daha az cilali". Kaynaklar anekdot/agregator (alternativeto, macrumors forum).

### A6. Tahoe
Seffaf bar Liquid Glass ile varsayilan; Reduce Transparency opak yapar; baz bulgular anekdotik (eclecticlight.co/2025/09/15/appearance-matters-get-tahoe-looking-in-better-shape/). Template image tint/kontrast davranisina dair resmi Apple belgesi BULUNAMADI: cihazda test gerekli. Stats README: macOS 26'da System Settings > Menu Bar'dan izin gerekir.

## B. TASARIM ONERILERI (dogrulanmis degil, cikarim/oneri)

### B1. Cizim temeli
- Yukseklik 22pt. Kullanilabilir ic alan 18pt (ust/alt 2pt). Cizim `NSImage(size:flipped:drawingHandler:)` ile, Retina'da otomatik. Hairline = 1/backingScaleFactor.
- Monokrom modda `isTemplate = true` (sistem boyar: Tahoe'da otomatik kontrast). Renkli/gradient modda `isTemplate = false`; bu durumda metin rengi icin `NSApp.effectiveAppearance` ya da `statusItem.button.effectiveAppearance` ile beyaz/siyah sec ve appearance degisimini gozle (KVO) yeniden ciz.
- Karma mod (en iyi pratik): metin template tarzi (appearance'a gore beyaz/siyah, %100 opaklik), renk SADECE grafik/dolgu/bar'da. Tahoe'da secondaryLabel cok soluk kaliyor: etiketler icin alpha >= 0.7 kullan, 7pt ve alti light agirlik kullanma (Stats 7pt light kullaniyor, Tahoe'da riskli).
- Genislik titremesi: `monospacedDigitSystemFont`, sabit-genislik modu (en genis metin ornegiyle olc: "100%", "999.9 MB/s"), birim ayri sabit sutun, genislik yalnizca >2pt degisince guncellensin (Stats Stack boyle yapiyor, dogrulandi), `NSStatusItem.length` sabit atanabilir.
- Her stil bir `MenuBarStyle` protokolu: `func intrinsicSize(config) -> CGSize`, `func draw(in rect, data, config, appearance)`. Tek bir renderer tum stilleri NSImage'a cizer.

### B2. Stil katalogu

| # | Stil | Metrikler | Boyut (pt) | Font | Ana secenekler |
|---|---|---|---|---|---|
| 1 | Text (Mini) | hepsi | 30-36 x 22 | 12-13 medium monospacedDigit; etiket 7.5 semibold | etiket ac/kapa, hizalama, birim, renk modu |
| 2 | Stacked label+value | hepsi | 28-34 x 22 | etiket 8, deger 11 | etiket ustte/solda, iki renk |
| 3 | Sparkline (line) | CPU, GPU, RAM, ag | 24/32/42/52 x 18 | deger 8 opsiyonel | gecmis 30/60/90/120, dolgu (alpha 0.35), cizgi kalinligi 1-1.5, olcek lineer/log/auto, frame/box |
| 4 | Bar chart (cok cekirdek/gruplar) | CPU cekirdek, disk | 10 + n*3 x 18 | etiket 7 | bar araligi, yuvarlak uc, kutu, cekirdek-grubu (P/E renkleri) |
| 5 | Tek dikey bar | CPU, GPU, RAM, disk | 6-8 x 18 | - | kutu cercevesi, threshold renk, yuzde yaninda |
| 6 | Yatay ince bar + metin | RAM, disk, mobil veri | 40 x 8 + metin | 9 | kalan/kullanilan, gradient dolgu |
| 7 | Halka (ring/pie) | CPU, GPU, RAM, disk, mobil veri | 18 x 18 | ortada 7-8 bold opsiyonel | yay kalinligi 2.5-3, kapak yuvarlak, gradient yay (angular), iz alpha 0.2 |
| 8 | Gauge/Tachometer (yarim yay) | CPU, sicaklik | 22 x 16 | 8 | baslangic/bitis acisi 210deg-330deg, igne, renk bolgeleri |
| 9 | Network dual-chart | ag | 30-50 x 18 | - | ust up, alt down, ayri renkler (mavi/kirmizi alpha 0.5), orta cizgi, ters sira |
| 10 | Speed (iki satir) | ag | 44-58 x 22 | 9 medium, ikon 6pt nokta/ok | ikon dots/arrows/chars, birim, bit/bayt, bostayken soluk (<1KB/s), sabit genislik |
| 11 | Speed (tek satir) | ag | 58 x 22 | 11 | io/oi, ayirac |
| 12 | Daily-usage chip | mobil veri | 40-60 x 18 | 11 + 8 | "1.2 GB" + ince ilerleme cizgisi alt kenarda, kota ile threshold |
| 13 | Dual item | CPU+GPU, up+down | birlesik | 9-10 | iki ince bar/halka yan yana, tek status item |
| 14 | Dot/LED | hepsi | 8 x 8 | - | threshold renk, nabiz animasyonu yok (pil) |
| 15 | Ikon + deger | hepsi | 16 + metin | SF Symbol 13 | sembol agirligi, deger sagda/altta |

### B3. Renk modlari (enum `ColorMode`)
1. system (template, sistem boyar)
2. monochrome (beyaz/siyah, appearance'a gore, template degil)
3. accent (controlAccentColor)
4. threshold (yesil->sari->kirmizi; varsayilan esik 60/80, kullanici ayari; pressure icin Normal/Warning/Critical; renkler `systemGreen/Yellow/Red`, Tahoe'da acik zeminde kontrast testi sart)
5. custom (metrik basina NSColor)
6. gradient (2-3 duraklik; deger->renk interpolasyonu `NSGradient`, ya da dolgu boyunca sabit gradient maske)
Ek: monochrome accent (renklerin grayscale'i), "colorize value" (yalniz metin), "colorize graph" ayrimi.

### B4. Global secenekler
Oge araligi (spacing 2-10pt), kompakt/yigili etiket, birim goster/gizle, bit/bayt, sabit genislik, yenileme araligi (0.5/1/2/5 sn; grafik gecmisi sample'a bagli), oge sirasi (surukle), metrik basina stil + renk ayri, on izleme (preview) paneli, tema on ayarlari (ornek: "Calm", "Neon", "Mono", "iStat-like"), "Reduce transparency / koyu-acik" onizleme, yan yana iki saat kipli birlestirilmis oge.

### B5. Uygulama notlari
- Stats'ta dogrulanan tuzaklar: etiket ofseti draw/toggle arasinda tutarsiz (8 vs 6), NetworkChart init'te history'yi yeniden boyutlandirmiyor: tek bir `layout()` fonksiyonu kullan.
- Ayar modeli: `Codable` struct `MetricStyleConfig { style, colorMode, customColors, thresholds, label, units, width, history, ... }` UserDefaults/JSON; stiller icin `StyleCatalog` kaydi.
- Performans: `canDrawConcurrently`, degisim yoksa yeniden cizme (Stats setValue kontrolu), NSImage onbellegi (metin genislik onbellegi 256 kayit, Stats'ta dogrulandi).

## C. Acik noktalar
- Constants.Widget sayisal degerleri dogrulanmadi.
- iStat 7 stil/tema katalogu ve Usage ozellikleri yalnizca arama ozetlerinden; resmi dokuman okunmadi.
- Tahoe'da template/renkli oge kontrasti icin resmi kaynak yok; gercek cihazda duz/gradient duvar kagitlari uzerinde test gerek.
- MenuMeters, Eul, SiliconScope, Bandwidth+, NetSpeed incelenmedi.

## Kaynaklar
- https://github.com/exelban/stats (Kit/Widgets/Mini, LineChart, BarChart, PieChart, NetworkChart, Speed, Stack, Memory, Tachometer, Battery .swift; Kit/types.swift)
- https://bjango.com/articles/designingmenubarextras/
- https://macrumors.com/2024/07/31/istat-menus-7-0-brings-new-features/
- https://bjango.com/mac/istatmenus/
- https://apps.apple.com/au/app/id1561788435 (Usage)
- https://eclecticlight.co/2025/09/15/appearance-matters-get-tahoe-looking-in-better-shape/
