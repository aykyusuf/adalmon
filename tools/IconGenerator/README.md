# IconGenerator

Adalmon uygulama simgesini (CoreGraphics, bağımlılıksız) çizer ve tüm macOS boyutlarını üretir.

```bash
swiftc -O tools/IconGenerator/main.swift -o /tmp/icongen
/tmp/icongen appiconset b Sources/App/Resources/Assets.xcassets/AppIcon.appiconset docs/icon-1024.png
```

Varyantlar: `a` nabız çizgisi, `b` gösterge yayı + ↓↑ okları (kullanılan), `c` gösterge + nabız. Önizleme: `/tmp/icongen preview b out.png`.

macOS 26 (Tahoe) uygulama simgesini kendi squircle maskesiyle keser, gölge/parlama ekler. Bu yüzden asset catalog'a **maskesiz, tam kenara taşan** kare konur (`--style fullbleed`, varsayılan): opak gradyan 1024x1024'ün tamamını doldurur, glif (yay + oklar) ortada tuvalin ~%62'sini kaplar; çerçeve/gölge/squircle yok.

Stiller (`--style`):
- `fullbleed` (varsayılan) Tahoe için; `appiconset` PNG'leri alfa kanalsız yazar.
- `masked` aynı çizimin squircle'a kırpılmış hali (824 px gövde + yumuşak gölge); `appiconset` komutunda `docs/icon-1024.png` (README) hep bu stille üretilir.
- `classic` eski Tahoe öncesi simge (squircle + çerçeve + gölge gömülü).

İsteğe bağlı: `/tmp/icongen iconlayers b Out/AppIcon.icon` Icon Composer paketi (opak arka plan + glif katmanı) üretir; `actool` derler. Şu an kullanılmıyor, çünkü tam kenarlı appiconset Tahoe'da diğer uygulamalarla aynı boyutta çiziliyor.
