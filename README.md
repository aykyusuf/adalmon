# Adalmon

macOS 26+ için menü çubuğu sistem monitörü: CPU, GPU, RAM, disk, sıcaklıklar ve **uygulama / site bazlı ağ kullanımı**.

## Öne çıkanlar
- **Uygulama ve domain bazlı ağ ölçümü:** `NEFilterDataProvider` system extension ile her akış sayılır (ör. Chrome › YouTube). Yerel DPI-bypass proxy'leri (SpoofDPI, ByeDPI) varken de trafik doğru uygulamaya yazılır, çift sayım yapılmaz.
- **Mobil veri koruması:** iPhone hotspot (Wi-Fi/USB) otomatik algılanır. Günlük limit, "son 1 dakikada X MB" uyarısı, mobilde tek tıkla engelleme.
- **Hız sınırı (deneysel):** `NETransparentProxyProvider` ile uygulama bazlı ↓/↑ sınırı.
- **Özelleştirilebilir menü çubuğu:** metrik kartları, tek satır / etiket üstte / simge düzenleri, gelişmiş bileşen düzenleyici.
- **Düşük enerji:** boşta ~%0,5–1 CPU.

## Derleme
Gereksinimler: Xcode 27+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Network Extension yetkisi olan bir Apple geliştirici hesabı.

```bash
xcodegen generate
xcodebuild -project Adalmon.xcodeproj -scheme Adalmon -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates build
```

`project.yml` içindeki `DEVELOPMENT_TEAM` ve bundle id'leri kendi hesabına göre değiştir. System extension'ın yüklenebilmesi için uygulama `/Applications` altında çalışmalıdır.

## Notlar
- Sıcaklık (IOHID, SMC) ve GPU yükü (IOReport) özel API'ler kullanır; App Store'a uygun değildir.
- `docs/` klasöründe araştırma notları ve test planları var.
