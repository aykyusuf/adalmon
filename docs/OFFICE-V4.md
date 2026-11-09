# Ofis v4 — modern vektör tema (web ajanı için)

Mantık (oda üretici, ızgara, koltuk, BFS, roller, gece/gündüz kuralı, taşıyıcı/temizlikçi, kart) v3 ile AYNI; yalnızca görünüm (doku) katmanı
ve kamera değişti. Sahne birimi hâlâ 16 pt/karo. Tek doğruluk kaynağı Swift: `OfficeTheme`, `OfficeVectorArt*.swift`, `OfficeLightParams`.

## Tema

* `OfficeTheme`: `vector` (varsayılan) | `pixel` (eski görünüm, aynen). UserDefaults `officeTheme`; bozuk değer → `vector`.
* macOS: sayfa başlığı ve ayrı pencere "Seçenekler" menüsünde "Tema: Vektör/Piksel"; değişince oda düğümleri yeni dokularla yeniden kurulur.
* `/v1/layout` kökünde `"theme": "vector"`; vektör dokular `v3.vector` altındadır. **Mevcut `appearance`, `furniture` (dosya eşlemesi) ve
  `v3.generated` (piksel data URI) alanları değişmedi** (istemci bir sonraki turda vektöre geçirilecek).

## Doku çözünürlüğü

* Tüm vektör dokular **4x**: 1 mantıksal birim = 4 px, 16 pt karo = 64 px. Mantıksal boyut = PNG boyutu / `scale`.
* Çizim: CoreGraphics (sRGB, premultiplied alfa), y aşağı mantıksal koordinat. İstemci `image-rendering: auto` (yumuşak/linear) kullanmalı;
  sprite'ı mantıksal boyutta (16 pt/karo) çizmeli, kamera ölçeği ile büyütmeli (kesirli ölçek serbest, en çok 8x; piksel temada tamsayı).
* macOS tarafı: `SKTexture.filteringMode = .linear`, pişirilmiş oda dokularında `usesMipmaps = true`.

## `v3.vector` (aynı JSON, `/v1/layout`)

```jsonc
"vector": {
  "theme": "vector", "scale": 4, "filter": "linear",
  "generated": { "imac_blue_off": "data:image/png;base64,...", "imac_blue_on1": "...", "macbook_gray_on3": "...", "lamp": "...",
                 "vglow_bulb": "...", "vglow_pool": "...", "vglow_screen": "...", "vglow_moon": "..." },   // piksel `generated` ile AYNI anahtarlar (+ vglow_*)
  "furniture": { "DESK_FRONT": "data:...", "PLANT": "...", ... },    // katalogdaki 38 varlık kimliği → 4x PNG (aynı ayak izi/boyut)
  "door": "data:...", "boardWrite": ["data:...", "...", "..."], "boardWriteOrigin": [5, 12],  // 22x9 mantıksal, 3 kare, opak beyaz zemin
  "windowDay": "data:...", "windowNight": "data:...",               // 14x20 mantıksal
  "backgrounds": { "s2": {"image": "data:...", "w": 640, "h": 768, "windows": [[x, y, w, h], ...]}, ... },   // oda başına TEK pişirilmiş gündüz arka planı
  "lighting": { "multiplyColor": [0.60, 0.66, 0.88], "washColor": [0.05, 0.10, 0.34], "washAlpha": 0.22, "bulbAlpha": 0.38, "poolAlpha": 0.40,
                "boardAlpha": 0.30, "screenAlpha": 0.9, "windowAlpha": 0.22 }
}
```

Anahtarlar: bilgisayar adları `OfficeArt.computerName` (`imac_{blue,green,pink,silver}`, `macbook_{silver,gray}` × `_off|_on1|_on2|_on3`, 64×128 px);
`lamp` (8×10 mantıksal); ışıklar `vglow_bulb` 64×64, `vglow_pool` 40×24, `vglow_screen` 24×16, `vglow_moon` 24×40 (tepe alfa 1, sprite alfası ile kısılır, additive).
Karakterler, aksesuarlar, balonlar ve zzz/mop/fincan/koli artık vektördür (aşağıdaki "Karakter atlası"); piksel tema `v3.generated` ve `characters/` ile aynen kalır.
Oda arka planı `backgrounds[tier]`: `bounds` başlangıcından, boyut = (kat genişliği+2)·16·4 × (yükseklik+2)·16·4; içinde zemin, halı, duvar, pencereler,
gün ışığı hüzmesi ve pişirilebilir mobilya (duvar öğeleri, bank, yönetici sandalyesi, kahve tezgâhı+makine) vardır; dinamik mobilya (`DESK_FRONT`,
`SMALL_TABLE_FRONT`, `PLANT`, `PLANT_2`, bilgisayarlar) ayrı sprite olarak (`furniture`/`generated`) çizilir; z sırası v3 ile aynı.
Pencere kutuları `windows` (mantıksal, arka plan başlangıcına göre). Gece: `windowNight` her kutunun üstüne (karakter altında, örtü üstünde değil) çizilir.

## Palet (hex)

| rol | hex |
|---|---|
| duvar / gölge / kenar / süpürgelik | F4EFE6 / E6DECF / CFC4B1 / D8CEBC |
| duvar bandı (nane) / koyu | 9ADBC6 / 6FBFA6 |
| yan duvar | E9E2D4 |
| zemin (açık meşe, 4 ton) | DDBE92, D9BA8D, E1C398, D5B68A; derz C2A073 (α .32) |
| halı / kenar / nokta | 8FA7C4 / DCE7F3 / 7C95B4 |
| masa üst / ön / metal ayak | F1E8D8 / D6C8AE / 8D95A2 |
| vurgu: turkuaz (bank) / mercan (sandalye) | 5FAFBE / E98A78 |
| gökyüzü gündüz / gece | 8FCBF2→D7EFFF / 0E1A40→2D468A |
| iMac çene (mavi/yeşil/pembe/gümüş) | 6F9BEF / 8FD18F / F2A7BC / DDE1E7 |
| MacBook (gümüş / uzay grisi) | D9DDE3 / 80868F |
| kitap sırtları | E98A78, 5FAFBE, F2C46D, 8FB996, 7A8CC9, D98BB0, F4EFE6, 6B7A8F |

Tasarım dili: düz renkli yuvarlatılmış formlar, 0.35 mantıksal birim koyu ton kenar çizgisi, öğe altında radyal elips gölge (α ≈ 0.17–0.25),
ışık yönü sol-üst. Gölgeler sprite sınırı içinde kalır.

## Işık kuralları

Kural aynı (`auto`: 19:30–06:30 gece; mod değişimi 1 sn crossfade). Değerler tema başına `OfficeLightParams`:

| | piksel (eski) | vektör |
|---|---|---|
| multiply örtü | [0.14,0.18,0.40], düğüm α 0.34 | [0.60,0.66,0.88] (α 1; SpriteKit `.multiply` düğüm alfasını yok sayar) |
| lacivert wash (normal karışım) | yok | [0.05,0.10,0.34], α 0.22 |
| tavan lambası (additive) | 0.85 | 0.38 (`vglow_bulb`, oda genişliği 1.3x, yükseklik 1.15x, merkez y=h·0.55) |
| masa ışık havuzu / tahta | 0.9 / 0.5 | 0.40 / 0.30 |
| PC ekran parıltısı | 1 | 0.9 |
| pencere ay ışığı | yok | 0.22 (`vglow_moon` 26×44, pencerenin altında zemine) |

Gündüz: pencerelerden yumuşak çapraz paralelkenar hüzme (α ≤ 0.34 → 0, statik) arka plana pişirilir.

## Kamera

Vektör temada kesirli zoom: `fitScale = min(8, max(1, min(vw/cw, vh/ch)))` (içerik `OfficeRoomArranger.margin`=10 kenar boşluğunu taşır); odaya
yakınlaşma `focusScale` (12 birim boşluk). Çok odada ızgara seçimi (`OfficeRoomArranger.best`) aynı; piksel temada tamsayı zoom (1…6) korunur.

## Performans

Oda başına zemin+duvar+sabit mobilya TEK doku; kademe (tier) başına **bir kez** pişirilir, tüm odalar paylaşır (`OfficeAssets.background(_:theme:)`).
Boyut (4x RGBA8): s2/s4 640×768 (1.9 MB), s6 832×768 (2.4 MB), s8/s12 832×1024 (3.3 MB), s16 832×1280 (4.1 MB); 6 kademe toplam ≈ 17 MB.
Düğüm sayısı piksel temayla aynı (gündüz); gece vektörde oda başına +≤ 2·pencere+1 düğüm. 12 fps üst sınırı ve duraklatma kuralları değişmedi.

## Karakter atlası (`v3.vector.characters`)

Kaynak: `OfficeVectorCharacter*.swift` (parametrik CoreGraphics figürü; `OfficeVectorUI.swift` etiket/balon). Tema `vector` iken macOS sahnesi
karakteri (kıyafet rengi, model + rol aksesuarı, kapüşon/yelek/kravat/önlük) **tek dokuya pişirir**; ek düğüm yoktur. Tarayıcı için aynı çizim
atlas olarak gelir.

**Kare ve ölçek.** Mantıksal kare `frameWidth × frameHeight` = **24×32** (16 genişlik figür + her yanda `padX` = 4 boşluk; kolu/aksesuar/koli taşabilsin);
4x ile hücre **96×128 px** (`cell`). Sprite, ayak ortası alt-orta (anchor 0.5, 0) hizalı; sahne/zoom/z-sırası/boy ölçeği (`small` → `spriteScale`) piksel
tema ile aynı. Oturan karakter `sitDrop` = 3 mantıksal birim aşağı çizilir (ayakta/tahtada/voltada 0). Ayak gölgesi karenin içindedir.

**Yön ve kare dizini.** `directions` = `["down","up","right"]` (satır sırası); **sol = sağ karenin yatay yansıması** (hücre merkezi etrafında `scaleX(-1)`).
Kare dizinleri (sütun) — 0-6 piksel sheet ile aynı, 7+ vektöre özel:

| dizin | poz | | dizin | poz |
|---|---|---|---|---|
| 0, 1, 2 | yürüme (`walkCycle` = 0,1,2,1; 1 = ayakta) | | 11 | esneme (kollar yukarı) |
| 3, 4 | yazma (dönüşümlü kollar) | | 12 | uyuklama (baş eğik; `zzz` aksesuarı ayrı) |
| 5, 6 | okuma (kitap elde) | | 13, 14 | kahve (fincan elde / ağızda) |
| 7, 8 | tahtada yazma (sağ kol yukarı, yön `up`) | | 15, 16, 17 | koli taşıma (yürüme 0,1,2) |
| 9, 10 | el kaldırma (izin bekleme; dönüşümlü sallanır) | | | |

`bob[kare]` = baş/gövde zıplaması (mantıksal birim, + aşağı; yürüme/taşıma kareleri 0.45, uyuklama 0.9).
macOS kullanımı: izin bekleme (`!` balonu) → 9,10; yönetici tahtada yazma → 7,8 (aşağı bakarken 1); `.coffee` boşta → 13↔14; esneme → 11; zzz → 12;
taşıyıcı → 15-17 (koli gövdeye pişirilmiş); temizlikçi önlüklü yürüme + `mop` dokusu (7×16, anchor alt-orta, x +7, ±0.18 rad sallanır).

**Atlas.**
```jsonc
"characters": {
  "scale": 4, "frameWidth": 24, "frameHeight": 32, "figureWidth": 16, "padX": 4, "cell": [96, 128],
  "frameCount": 18, "frameNames": ["walk0","stand","walk2","type0","type1","read0","read1","board0","board1","raise0","raise1","yawn","sleep","coffee0","coffee1","carry0","carry1","carry2"],
  "walkCycle": [0,1,2,1], "directions": ["down","up","right"], "sitDrop": 3, "bob": [...18],
  "frames": {"stand":1, "walk":[0,1,2], "typing":[3,4], "reading":[5,6], "boardWrite":[7,8], "raiseHand":[9,10], "yawn":11, "sleep":12, "coffee":[13,14], "carry":[15,16,17]},
  "looks": [{"index":0,"skin":"#EFC29E","hair":"#3A2A22","hairStyle":"short","pants":"#394868","shoe":"#F6F6F8"}, ...6],
  "neutralShirt": "#F2F2F4", "shirtTint": "color = atlas.rgb * lerp(white, shirt, mask.gray) ...",
  "atlas": { "image": "data:...png" /*RGBA*/, "mask": "data:...png" /*8-bit gri*/, "width": 1728, "height": 2304,
             "layout": "x = frame * w, y = (look * 3 + directionRow) * h",
             "index": [{"look":0,"direction":0,"frame":0,"x":0,"y":0,"w":96,"h":128}, ... 324 giriş] },
  "accessories": { "image": "data:...png", "width": 288, "height": 2304,
                   "index": [{"name":"crown","kind":"model","direction":0,"x":0,"y":0,"w":96,"h":128}, ...] },
  "models": [{"badge":"opus","look":2,"shirt":"#B052DE","accessory":"crown","small":false}, ...],
  "roles":  [{"key":"reviewer","shirt":"#E04848","accessory":"glasses","place":"face","hoodie":false,"vest":false,"small":false}, ...],
  "props":  [{"key":"cleaner","shirt":"#2673FA","look":1,"accessory":"apron"}, {"key":"carrier","shirt":"#E68C26","look":1,"accessory":"hardhat"}],
  "bindings": {"head":[12,11], "face":[12,11], "chest":[12,20], "hand":[18,22], "unit":"logical, cell origin top-left, y down, before bob"}
}
```
* **Look → model:** `appearance[badge].character` (Opus 2, Sonnet 0, Haiku 4, Fable 5, bilinmeyen 3; 1 = yardımcı/yedek). Alt ajanda look model rozetinden,
  kıyafet rengi (`shirt`) rolden gelir (`models[].shirt` yöneticide model rengi).
* **Gömlek rengi:** atlas nötr gömlekle (`#F2F2F4`) çizilir; `mask` düzlemi (beyaz = gömlek + kollar + kapüşon) ile hücre rengi `rgb * lerp(white, shirt, mask)`
  çarpılır (macOS gömleği doğrudan `shirt` ile pişirir; web çarpımı aynı görünümü yaklaşık verir). Alfa `atlas.image`'dan alınır.
* **Aksesuarlar:** `accessories` atlası (model: crown/cap/star/sprout; rol: binoculars/book/hood/headphones/glasses/magnifier/vest/compass/clipboard/tie/ruler/tag;
  yardımcı: hardhat/apron) karakterle **aynı hücre boyutunda, ayakta (kare 1) pozunda** çizilmiş saydam kaplamalardır: karakter karesinin üstüne aynı konumda
  çizilir; zıplayan karelerde `bob` kadar kaydırılır. Baş/yüz öğeleri kafayı, `chest` (yelek, kravat, etiket, binoküler) gövdeyi izler; **el öğeleri** (kitap, pano,
  pusula, büyüteç, cetvel) her pozda sağ kalçanın yanındadır. Kapüşonun (`hoodie: true`) kafa arkası parçası kaplamada yoktur: web için `shirt` + `mask` yeterli,
  yaka/cep ayrıntısı macOS'a özgüdür. Yelek (`vest`): gömlek açık krem, `shirt` rengi yelektir.
* **Boyut:** `atlas.image` ≈ 1.28 MB, `mask` ≈ 0.17 MB, `accessories` ≈ 0.05 MB (data URI toplamı ≈ 1.5 MB); `/v1/layout` yalnızca özellik açılırken bir kez üretilir.
* **Gece:** macOS yöneticisi/karakteri geceye özel doku (`nightGrade`: renk, sahne multiply çarpanının tersiyle açılır). Web `lighting.multiplyColor` uygularsa
  karakter hücresini aynı çarpanın 0.8 üssünün tersi ile aydınlatmalı (ya da çarpan örtüsünün altında bırakıp gömlek renklerini doygun tutmalı).

### Etiket / balon / başlık (macOS vektör teması)

* Ad etiketi: tek 4x yuvarlak "hap" dokusu (genişliğe göre üretilir, gölgeli), solda rol/model renk noktası, sistem yazısı (SF, yarı kalın, 10 pt ekran
  eşdeğeri); gündüz açık yüzey (beyaz α .92, ince koyu kenar), gece koyu cam (`#1B2132` α .9, ince beyaz kenar). Zoom'dan bağımsız boyut (düğüm ölçeği 1/zoom).
* Konuşma balonu: beyaz yuvarlak gövde (14 pt) + 4 pt kuyruk + yumuşak gölge, koyu gri metin; `OfficeTextBubble.height`/`tailX` temaya göre (vektör 18 / 4);
  `resolveBubbleOverlaps` aynıdır. `!` ve `…` balonları (`bubble_alert`, `bubble_think`, 11×12 / 11×10) aynı dilde vektör dokulardır.
* Oda başlığı: yuvarlak kart (gündüz açık, gece koyu slate), kalın ad, renkli model rozeti, oturum renginde ince alt çizgi; "+N" rozeti yuvarlak hap.
* Vektör yardımcı dokular `v3.vector.generated` içinde de vardır: `zzz` 9×8, `mop` 7×16, `cup` 6×5, `box` 10×7, `bubble_alert`, `bubble_think` (mantıksal boyut / 4x).

### Bellek / performans

Kareler tembel üretilir ve `spec.key|yön|kare[|n]` anahtarıyla bellekte tutulur (RGBA8 96×128 = 48 KB/kare). 10×10 senaryosunda (~100 karakter, gündüz + gece)
286 kare ≈ 13 MB. Düğüm sayısı piksele göre azalır (karakter başına aksesuar/rol düğümü yok); 12 fps ve duraklatma kuralları değişmedi.

### Tarayıcı istemcisi (Resources/Web) için sözleşme notları

* `/v1/state` → `rooms[].computers`: `{ "<pc yerleşim indeksi>": "imac_blue" | "macbook_gray" | ... }`. Boş masaların bilgisayarı da dahildir (tohum oda kimliğine
  bağlı olduğu için tarayıcı hesaplayamaz); anahtar `layout.tiers[..].seats[].pc` / `furniture[].i` ile aynıdır. Bilgisayar sprite'ı: `v3.vector.generated[name + "_off" | "_on1".."_on3"]`.
* `tiers[..].lamps` son öğesi (yönetici masası) artık `dx: 0` (sahnedeki x = col·16 + 16 ile uyumlu); masa bloklarında `dx: 8`.
* CSP `connect-src 'self'` data: adreslerinde `fetch`'i engeller: istemci base64'ü `atob` ile çözüp `Blob` → `createImageBitmap` kullanır.
* Tarayıcı testi: `node Tests/Web/office-client.test.js` (sahte DOM/canvas; gerçek tarayıcı değil).

## Arka plan işlemleri (sunucu rafı)

Oturumun (Claude süreci, hook'tan gelen `pid`) başlattığı ve hâlâ çalışan komutlar. Ajan DEĞİLDİR; ofiste her odada küçük bir sunucu rafı eşyası + kartta liste olarak görünür. Veri kaynağı süreç ağacıdır (hook'a bağlı değil).

**Örnekleme (`SessionProcessSampler`, `ProcessTableProviding`):** libproc (`proc_listallpids`, `PROC_PIDTBSDINFO`, `PROC_PIDTASKINFO`). CPU % = iki örnek arası CPU süresi farkı / duvar zamanı. `KERN_PROCARGS2` (argv) YALNIZCA Claude'un doğrudan çocuğu olan kabuklar için, sarmalayıcı mı kararı için okunur; hiçbir yerde saklanmaz/gösterilmez/loglanmaz, ortam değişkenleri ayrıştırılmaz.
- Claude'un doğrudan çocuğu `zsh|bash|sh|dash` + argv'de `-c` bayrağı ve (`shell-snapshots` ya da `claude`) = "komut kökü": sarmalayıcı gizlenir, altındaki ilk gerçek işlem katmanı listelenir (çocuklu alt kabuklar atlanır; torunlar ayrıca sayılmaz, `hasChildren` işaretlenir).
- Sarmalayıcı `exec` ile komuta dönüşürse (aynı pid + başlangıç, daha önce sarmalayıcı görülmüş) süreç kendisi görünür.
- Doğrudan çocuk olup kabuk olmayanlar (MCP, hook, eklenti) ve sarmalayıcı olmayan kabuklar GÖSTERİLMEZ. 2 sn'den genç süreçler ve zombiler sayılmaz.
- Çıktı: `SessionShell {pid, name (yalnızca basename, ≤24 karakter, kontrol karakteri yok), ageSeconds, cpuPercent, rssBytes, hasChildren}`; en çok 12 öğe (CPU, sonra yaş), `total` ayrıca. Değerler görünür duyarlığa yuvarlanır (yaş 5 sn/1 dk, CPU 0,1/1, RSS 1 MB) ki değişmeyen durum eşit çıksın.

**Talep-temelli yoklama (pil):** `AgentMonitorModel.shellObservers` (panel, ofis sayfası/pencere görünürken, web SSE istemcisi >0 iken +1). Gözlemci > 0 VE pid'li açık oturum varken tek Task, 5 sn aralık (tolerance), `Task.detached(.utility)`; aksi halde hiç iş yok. Durunca `AgentSession.shells` temizlenir. Değişmeyen örnekleme state yazmaz.

**Raf:** `SERVER_RACK` (16×32 px, ayak izi 1×2, engel), şablonda sütun 1 / satır 3-4 (yönetici şeridinin sol ucu). 4 LED: N=0 hepsi gri; 1…4 → N yeşil; N>4 → 4 LED, sonuncusu turuncu. Statik (yanıp sönme yok). pid yoksa gri, ipucu "İşlem bilgisi yok (eski oturum)"; aksi halde "Arka plan işlemleri: N". Rafa tıklama oturum (yönetici) kartını açar.

**`/v1/state` (`rooms[]`):**
```json
"shells": {"count": 15, "known": true, "hidden": 3, "items": [{"name": "xcodebuild", "ageSec": 120, "cpu": 42, "rssMB": 300}]},
"rack":   {"leds": ["green","green","green","orange"], "lit": 4, "count": 15, "known": true, "tooltip": "Arka plan işlemleri: 15"}
```
`items` en çok 12; isim yalnızca basename; komut satırı/argüman/pid alanı YOKTUR.

**`/v1/layout`:** `tiers[*].rack = {col, row, w, h}` (raf gövdesi `furniture.SERVER_RACK` ve vektör arka plana pişirilmiştir); `v3.vector.rack = {w, h, ledCount, dotX, dotY, dotDy, dotW, dotH, dots: {off, green, orange}}` (LED dokuları data URI; i. LED: `x = rack.col*16 - ox + dotX`, `y = rack.row*16 - oy + dotY + dotDy*i`).

**İstemci:** `drawRack` LED'leri çizer (statik); raf tıklaması/hover'ı oturum kartına "Arka plan işlemleri (N)" listesi (ad · süre · CPU · RAM, "+K daha", "Yalnızca işlem adı gösterilir") ekler. SSE istemcisi bağlıyken sunucu gözlemci sayacını artırır.
