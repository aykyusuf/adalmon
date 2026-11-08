# Ofis v3 — tarayıcı veri sözleşmesi

Tek doğruluk kaynağı Swift'tir (`OfficeRoomTemplates`, `OfficeRoles`, `OfficeLighting`, `OfficeComputer`, `OfficeIdle`, `OfficeCleaner`,
`OfficeCarrier`, `OfficeArt`). Tarayıcı istemcisi yalnızca çizer; hiçbir kuralı yeniden türetmez. Yeni piksel-art dokuları
`/v1/layout` içinde `v3.generated[<ad>]` altında **data URI** (`data:image/png;base64,...`) olarak gelir (CSP `img-src 'self' data:` izinli).

Sürüm: `/v1/state` ve `/v1/layout` artık `"v": 3`. Eski alanlar korunur (eski istemci bozulmaz), **tek istisna**: oda kademesi anahtarları
(`room.tier`, `layout.tiers[<anahtar>]`) `small|medium|large` yerine `s2|s4|s6|s8|s12|s16` olur.

## 1. Oda kademeleri (parametrik üretici)

`tier` = masa istasyonu sayısı (yönetici koltuğu ayrı, `capacity = stations + 1`). Üst kademe alt kademenin **üst kümesidir**: aynı
karodaki koltuklar yerinde kalır, büyüme yalnızca yeni masa bloğu ekler.

| tier | istasyon | kapasite | üye sayısı | zemin (G×Y karo) | blok (2'li masa) |
|------|---------|----------|------------|------------------|------------------|
| s2   | 2  | 3  | 0–3   | 8 × 10  | 1 |
| s4   | 4  | 5  | 4–5   | 8 × 10  | 2 |
| s6   | 6  | 7  | 6–7   | 11 × 10 | 3 |
| s8   | 8  | 9  | 8–9   | 11 × 14 | 4 |
| s12  | 12 | 13 | 10–13 | 11 × 14 | 6 |
| s16  | 16 | 17 | 14–17 | 11 × 18 | 8 |

* 17'den fazla üye: fazlası `overflow` ("+N" rozeti). Odada hiçbir salon koltuğu ajan koltuğu değildir (`lounge` artık yok).
* Blok `i`: masa sol-üst karosu `col = 1 + 4·(i mod 3)`, `row = 6 + 4·(i div 3)`. Masa 3×2 karo, iki uçta (`col`, `col+2`) bilgisayar,
  `row+2` satırında iki bank (istasyon koltukları: `(col, row+2)`, `(col+2, row+2)`). Tek bloktaki iki istasyon yan yanadır.
* Yönetici alanı (tahta, halı şeridi `zone`, masa, koltuk id 0) ve kapı (sağ duvar, en alt satır) her kademede aynı yerde mantıktadır.
* Kahve makinesi her kademede vardır: `coffeeTable` karosu (sol-üst, 2×2 masa) ve `coffee` (`tile`, `facing`).
* Büyüme (küçük→büyük kademe): yeni ajan için boş masa yoksa oda zemini/duvarı **0.4 sn crossfade** ile yenilenir (`carrier.growFade`), kapıdan
  bir taşıyıcı kolisiyle girer, yeni bloğun önüne (`(blockCol+1, blockRow+2)`) yürür, masa 0.4 sn yukarıdan düşer/kayar
  (`carrier.dropSeconds`), bilgisayar belirir, taşıyıcı çıkar; **sonra** yeni ajan kapıdan yürüyüp oturur. Oturanlar kaybolmaz.
* Küçülme histerezisi: `üye sayısı <= altKademe.capacity - 1` olunca iner (örn. s8'den s6'ya 6 üyeyle); boş masalar sessizce kalkar (animasyonsuz).

### `/v1/layout` → `tiers[<anahtar>]` yeni alanlar

```jsonc
{
  "key": "s6", "stations": 6, "capacity": 7, "floorWidth": 11, "floorHeight": 10,
  "blocks": [{"i": 0, "col": 1, "row": 6}, {"i": 1, "col": 5, "row": 6}, {"i": 2, "col": 9, "row": 6}],
  "laneRows": [5, 11],                       // temizlikçi S rotasının koridor satırları
  "lamps": [{"col": 2, "row": 6, "dx": 8, "dy": 14}],   // masa lambası: karo + karo içi piksel sapması (üstten); son öğe yönetici masası
  "coffeeTable": {"col": 3, "row": 9},
  "coffee": {"tile": [8, 9], "facing": "right"},
  "seats": [{"id": 3, "col": 1, "row": 8, "kind": "desk", "facing": "up", "pc": 4, "computerKey": 801, "enter": [[..]]}],
  "...": "mevcut alanlar (cols, rows, tiles, colors, furniture, entrance, door, board, zone, zoneTiles)"
}
```

`furniture` içindeki `PC_FRONT_OFF` yerleşimleri artık **bilgisayar yer tutucusudur**: hangi sprite'ın çizileceği `seat.computerKey` +
oda kimliği ile belirlenir (aşağıda) ya da `/v1/state` üyesinin `appearance.computer` alanından alınır (önerilen).

## 2. Bilgisayarlar (iMac / MacBook)

`v3.computers` altı varyant listeler: `imac_{blue,green,pink,silver}`, `macbook_{silver,gray}`; her biri 16×32 px (eski PC sprite'ıyla aynı
yerleşim) `off` + `on[3]` (ekran animasyonu 0.45 sn/kare) doku adıdır → `v3.generated[<ad>]`.

Seçim: `seed = fnv1a64(roomID + "|pc|" + seatKey)`, `seatKey = row·100 + col` (koltuk karosu; kademe değişse de sabit); `splitmix64(seed, 0) < 0.55 ⇒ imac`,
aksi halde macbook; renk `splitmix64(seed, 1)` ile ilgili renk listesinden. Yönetici masası her zaman `imac_silver`. İstemci hesaplamak yerine
`member.appearance.computer = {kind, color, name}` değerini kullanmalıdır.

## 3. Roller (`member.role`)

```json
"role": {"key": "implementer-hard", "name": "crew-chief:implementer-hard", "tint": "#8E4FE0", "accessory": "headphones", "small": false, "hoodie": true, "known": true, "labelColor": "#C8A6F0"}
```

Ana ajan (oturum): `{"key":"lead","name":"ana ajan","tint":<model tonu>,"accessory":<crown|cap|star|sprout|none>}` ve model aksesuarını korur.
Alt ajanda **rol stili baskındır**: gövde tonu `tint` (`appearance.tintBlend` ile karışım), aksesuar `role.accessory`; model rengi
`appearance.modelDot` (etiketin solunda minik nokta). Etiket: `role.name` (kısaltmasız, en çok 22 karakter) `role.labelColor` renginde.

Eşleme: `agentType` küçük harf; tam anahtar bilinmiyorsa son `:` sonrası alınır (plugin öneki ayıklanır, `name` değişmez). Bilinmeyen tip:
ton = HSL(`fnv1a64(key) % 360`, s 0.55, l 0.55), aksesuar `tag`.

| anahtar | ton | aksesuar | boy |
|---|---|---|---|
| scanner | #3FBF5F yeşil | binoculars | küçük |
| deep-reader | #F2A93B sarı/turuncu | book | normal |
| implementer | #3B7BFF mavi (hoodie) | hood | normal |
| implementer-hard | #8E4FE0 mor (hoodie) | headphones | normal |
| reviewer | #E04848 kırmızı | glasses | normal |
| ui-tester | #F28A1E turuncu yelek | magnifier | normal |
| ui-smoke | #F7B267 açık turuncu | vest | küçük |
| explore | #28C7C0 turkuaz | compass | normal |
| plan | #1F3A8A lacivert | clipboard | normal |
| general-purpose | #8A8F98 gri | tie | normal |
| feature-dev:code-architect | #8C2F45 bordo | ruler | normal |
| feature-dev:code-explorer | #28C7C0 turkuaz | compass | normal |
| feature-dev:code-reviewer | #E04848 kırmızı | glasses | normal |
| claude-code-guide | #F07AB0 pembe | book | normal |
| statusline-setup | #C9CED6 açık gri | none | normal |

Aksesuar doku adı: `role_<accessory>` (`v3.generated`). `place`: `head` (headphones), `face` (glasses), `chest` (hood, vest, tie, tag), `hand` (diğerleri).
Karakter 16×32; ofsetler (ayak tabanından, ölçek `small` ise ×s): glasses y+23, headphones y+25, hood y+17, vest/tie y+11, tag (x+4, y+9), el (x±7, y+10);
arkaya (`up`) bakarken `face`/`chest` gizlenir.

## 4. Işık (gece / gündüz)

`/v1/state` kökünde: `"lighting": {"mode": "auto|day|night", "nightStartHour": 19, "nightStartMinute": 30, "nightEndHour": 6, "nightEndMinute": 30, "resolvedNight": false, "timeZone": "Europe/Istanbul"}`.
Kural: `auto` → yerel saat 19:30 ≤ t < 06:30 gece; `day`/`night` saate bakmaz. Tarayıcı yine kendi yerel saatiyle de çözebilir; `resolvedNight`
sunucu (Mac) saat dilimine göre çözümdür. Mod değişimi **1 sn crossfade** (`lighting.crossfade`). Zamanlayıcı döngüsü yok: saat sınırı için tek `setTimeout`.

Gece katmanı (`v3.lighting`): çok koyu lacivert örtü `overlayColor` (RGB 0–1) × `multiply`, `overlayAlpha` 0.34; tavan lambası `glow_bulb` (additive, alpha 0.85, oda
boyunun ~1.3×'ü, merkez x=w/2, y=h·0.55) ; her masa bloğunda `lamp` sprite'ı + `glow_pool` (additive, 64×36, alpha 0.9) (`tier.lamps`); tahtada
`glow_pool` (alpha 0.5); ekranı açık PC'de `glow_screen` (30×20, additive). Katmanlar animasyonsuzdur. Örtü z=4000 (balon/etiket üstte kalır).

## 5. Boşta davranışı, temizlikçi, taşıyıcı

* `member.idleVariant = {"seed": "<roomID>|<memberID>", "sequence": [{"variant": "read|coffee|yawn|zzz", "seconds": 5–9}, ... 8 öğe]}` — tarayıcı sıradaki
  varyantı bu diziden döngüyle alır (hash/rastgele gerekmez). Yalnız masada oturan boştaki (idle/done) ajanlar; çalışırken yazar. read: okuma kareleri; coffee: `cup`
  elde yukarı-aşağı; yawn: iki kare + 1.5 px zıplama; zzz: `zzz` balonu. Varyantlar arası durma serbest (ucuz zamanlayıcı).
* Kahve yürüyüşü: `v3.idle` — olasılık `wanderChance` 0.3, yürüyüşler arası `wanderGapMin..Max` 20–60 sn, bekleme `wanderStayMin..Max` 5–8 sn, odada eşzamanlı en çok
  1 (üye < 8) ya da 2 (≥ 8) kişi. Yönetici bundan muaftır.
* Temizlikçi (`room.cleaner` + `v3.cleaner`): aralık 90–180 sn (`intervalMin/Max`), oda başına bir kerede bir; yalnızca oda görünürken ve sayfa/sahne duraklatılmamışken.
  Rota `S`: kapıdan girip `laneRows` koridor satırlarını sırayla soldan sağa / sağdan sola dolaşır (koltuk karolarına girmez), girişe dönüp çıkar. Karakter `character: 1`,
  mavi önlük (`tint [0.15,0.45,0.98]`, blend 0.6), elinde `mop` (yürürken ±0.18 rad salınır); her yürünen karoda 14×7 açık additive şerit 3.2 sn'de solar (`trailFade`).
  Adım süresi `stepSeconds` (0.25 sn). Zamanlama **tarayıcıda yerel simüle edilir** (sunucu olay göndermez).
* Taşıyıcı (`v3.carrier`): `steps = enter, walkToDesk, dropDesk, showComputer, walkBack, leave, seatAgent`; yalnızca kademe büyürken. Karakter 1 + turuncu ton, elinde `box`.

## 6. `/v1/state` yeni üye alanları (özet)

| alan | anlam |
|---|---|
| `role` | bkz. §3 |
| `appearance` | `{character, tint (hex), tintBlend, small, accessory (model; alt ajanda none), modelDot?, computer: {kind, color, name}}` (`computer` yalnızca koltuklu üyede) |
| `seat` | (eski) koltuk id |
| `seatInfo` | `{id, col, row, kind, facing, key}` — istasyon id/konum; `key` = bilgisayar tohumu anahtarı |
| `idleVariant` | bkz. §5 |
| oda: `tier`, `stations`, `capacity`, `cleaner{intervalMin,intervalMax,route,laneRows,seed}` | oda kademesi ve temizlikçi sabitleri |

Örnek üye:

```json
{"id":"sess#a1","kind":"subagent","label":"crew-chief:implementer-hard","badge":"haiku","status":"tool","seat":3,"seatKind":"desk","pose":"typing",
 "role":{"key":"implementer-hard","name":"crew-chief:implementer-hard","tint":"#8E4FE0","accessory":"headphones","small":false,"hoodie":true,"known":true,"labelColor":"#C8A6F0"},
 "appearance":{"character":4,"tint":"#8E4FE0","tintBlend":0.55,"small":false,"accessory":"none","modelDot":"#33C759","computer":{"kind":"macbook","color":"gray","name":"macbook_gray"}},
 "seatInfo":{"id":3,"col":1,"row":8,"kind":"desk","facing":"up","key":801},
 "idleVariant":{"seed":"sess|sess#a1","sequence":[{"variant":"zzz","seconds":6.4}]}}
```

## 7. macOS tarafı (referans)

`officeLightingMode` (UserDefaults, `auto|day|night`): sayfa başlığı ve ayrı pencere "Seçenekler" menüsünde "Işık" seçici. Sahne 12 fps üst sınır; görünmeyen odada
ışık/animasyon düğümleri kapalı; boşta varyantı/temizlikçi/kahve yalnızca görünür odada, 12 sn'lik tek düşük frekanslı zamanlayıcıyla başlar ve sonludur.
