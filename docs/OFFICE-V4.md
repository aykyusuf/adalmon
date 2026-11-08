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
Rol aksesuarı, fincan, zzz, mop, koli, balonlar ve karakterler bu turda piksel kalır (`v3.generated`, `characters/`).
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
