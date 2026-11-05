# Hız sınırı (uygulama bazlı) — manuel test planı

Kapsam: `AdalmonFilter` system extension'ına eklenen `TransparentProxyProvider` (NETransparentProxyProvider),
filtredeki QUIC düşürme ve `ThrottleSettingsPane`. Birim testleri (`Tests/ThrottleTests.swift`) token kovası
matematiğini, `FilterConfig` Codable'ını ve "akışı üstlen?" kararını kapsar; buradaki adımlar gerçek sistemde
çalışmayı doğrular.

Ölçüm hedefi: `https://speed.cloudflare.com/__down?bytes=50000000` (50 MB). Başka hızlı bir hedef de olur.
Hız birimleri 1024 tabanlıdır: 1 MB/s = 1 048 576 B/s; curl `speed_download` B/s yazar.

## 0. Ön koşullar

- SpoofDPI çalışıyor, sistem HTTP/HTTPS proxy'si `127.0.0.1:8080`.
- Ayrı bir terminalde log akışı açık:
  ```
  log stream --level info --predicate 'subsystem == "com.yusufayik.adalmon"'
  ```
  Beklenen kategoriler: `filter`, `xpc`, `throttle`.

## 1. Kurulum ve onay

1. Yeni derlemeyi kur (ana oturum), Adalmon'u başlat.
2. Filtre zaten kuruluysa uygulama açılışta extension'ı yeni sürümle değiştirir (`updateIfInstalled`).
   Değilse Ayarlar → Filtre → "Kur / Yeniden kur". Sistem Ayarları'nda extension'ı onayla.
3. Log'da `filter started` ve `XPC listener started` görülmeli.
4. Henüz hiç sınır yokken: `scutil --nc list` içinde "Adalmon hız sınırı" **olmamalı**
   (ayar ilk sınır eklenene kadar oluşturulmaz → sınır yokken sıfır ek yük).

## 2. Temel çizgi (sınır yok)

```
URL='https://speed.cloudflare.com/__down?bytes=50000000'
# Proxy üzerinden (uygulama → loopback:8080 → SpoofDPI):
curl -s -x http://127.0.0.1:8080 -o /dev/null -w 'proxy  %{speed_download} B/s  %{size_download} B\n' "$URL"
# Doğrudan:
curl -s --noproxy '*' -o /dev/null -w 'direct %{speed_download} B/s  %{size_download} B\n' "$URL"
```
İki değeri not et (beklenen: bağlantının tam hızı, 1 MB/s'nin belirgin üstünde). `--limit-rate` KULLANMA.

## 3. curl'e ↓ 1 MB/s sınırı (belirleyici ölçüm)

curl'ün anahtarı `/usr/bin/curl`. 2. adımdan sonra bugünkü kullanım listesinde görünür.

1. Ayarlar'da hız sınırı bölümünü aç (`ThrottleSettingsPane`). Bölüm henüz kenar çubuğuna bağlı değilse
   ana oturum bağlayana kadar bu adımı panel/ayar entegrasyonundan sonra yap.
2. "Uygulama ekle" altında curl → "Uygulama ekle" (varsayılan ↓ 1 MB/s). ↓ = 1 MB/s, ↑ = Sınırsız.
3. **İlk sınırda macOS "Adalmon proxy yapılandırması eklemek istiyor" onayı sorar** → İzin ver.
4. Kontrol:
   - `scutil --nc list` → "Adalmon hız sınırı" `Connected`.
   - Log: `transparent proxy started`, `config: … limits=1`.
5. 2. adımdaki iki curl komutunu tekrar çalıştır. Beklenen:
   - Log'da her biri için `throttling /usr/bin/curl -> …` (proxy olanı için hedef `127.0.0.1:8080`).
   - `speed_download` ≈ 1 048 576 B/s (kabul: 0.9–1.15 MB/s; ilk 0.25 sn'lik patlama payı küçük sapma yapar).
   - Proxy'li ölçüm 1 MB/s civarındaysa **SpoofDPI loopback yakalaması çalışıyor** demektir (en büyük risk, bkz. Riskler).
     Proxy'li ölçüm tam hızdaysa ve log'da 8080 için `throttling` satırı yoksa loopback akışları
     saydam proxy'ye gelmiyor demektir → raporla.
6. Çift sayım kontrolü: sınırlıyken curl'ün indirdiği 50 MB'ın Adalmon'daki "bugün" listesinde curl'e
   ~50 MB olarak eklendiğini doğrula (yaklaşık 100 MB görünüyorsa filtre hem asıl akışı hem aktarım bağlantısını
   sayıyor → raporla; ~0 görünüyorsa hiçbirini görmüyor → raporla).

## 4. ↑ sınırı

↑ = 250 KB/s ayarla, sonra:
```
head -c 20000000 /dev/urandom > /tmp/up.bin
curl -s --noproxy '*' -o /dev/null -w 'up %{speed_upload} B/s\n' --data-binary @/tmp/up.bin https://speed.cloudflare.com/__up
```
Beklenen ≈ 256 000 B/s.

## 5. Sınırı canlı değiştirme / kaldırma

1. Uzun bir indirme başlat (`bytes=500000000`, proxy'li). Çalışırken ↓'yü 3 MB/s yap → hız birkaç saniye içinde
   ~3 MB/s'ye çıkmalı (kova hızı her parçada güncel ayardan okunur; açık akışlar da etkilenir).
2. curl'ün sınırını "Kaldır" → hız aynı indirmede tam hıza dönmeli.
3. Son sınır kalkınca: `scutil --nc list` → "Adalmon hız sınırı" `Disconnected` (ayar silinmez, yalnızca kapanır;
   bir sonraki sınırda tekrar onay istenmez).
4. 2. adımdaki ölçümleri tekrarla → temel çizgiye eşit olmalı.

## 6. Chrome ve YouTube

1. Chrome'a ↓ 1 MB/s ver.
2. **Chrome'u tamamen kapatıp yeniden aç** (Cmd+Q). Saydam proxy yalnızca yeni akışları yakalar; Chrome'un
   açık HTTP/2 bağlantıları sınırsız kalır.
3. `chrome://net-internals` gerekmez; log'da `throttling /Applications/Google Chrome.app -> 127.0.0.1:8080` görülmeli.
4. Chrome'da speed.cloudflare.com → indirme ≈ 8 Mbps (1 MB/s) civarında olmalı.
5. YouTube: bir videoyu "İstatistikler" (sağ tık → Stats for nerds) ile aç. "Connection Speed" ≈ 8000 Kbps
   civarında kalmalı; otomatik kalite 1 MB/s'ye uygun seviyeye inmeli (çoğunlukla 720p/1080p30 arası).
6. QUIC: sistem proxy'si varken Chrome QUIC kullanmaz (her şey 8080'e CONNECT). Proxy'yi geçici kapatıp
   Chrome'u yeniden başlatırsan log'da `quic dropped …Google Chrome.app` (debug seviyesi; `--level debug`) görülür
   ve YouTube yine sınırlı TCP ile oynamalı.
7. Chrome sınırını kaldır → Chrome'u yeniden başlat → tam hız.

## 7. "Sadece mobilde"

1. curl'e ↓ 1 MB/s + "Sadece mobilde" işaretle. Wi-Fi'de ölç → tam hız (log'da `throttling` yok).
2. Ayarlar → Mobil veri → "Bu ağı her zaman mobil veri say" aç → yeniden ölç → ~1 MB/s.
3. Kapat → tam hız.

## 8. Dayanıklılık

- Sınırlıyken SpoofDPI'yi durdur → proxy'li curl hemen "connection refused/failed" ile bitmeli, askıda kalmamalı
  (aktarım bağlantısı `failed/waiting` olunca akış kapatılır; en geç 15 sn bağlantı zaman aşımı).
- Sınırlıyken Wi-Fi'yi kapat/aç → açık indirmeler hata ile bitmeli, yeni bağlantılar çalışmalı.
- Ayarlar → Filtre → "Kaldır": filtre ve "Adalmon hız sınırı" yapılandırması birlikte silinmeli (`scutil --nc list`).

## Riskler / bilinen sınırlamalar

- **SpoofDPI loopback**: SDK başlığı (`NENetworkRule.h`) loopback'in açık 127.0.0.1/::1 kuralıyla eşleştiğini söylüyor
  ve saydam proxy bu kuralları içeriyor; ancak saydam proxy'nin loopback akışlarını gerçekten aldığı bu makinede
  henüz doğrulanmadı (3.5 adımı bunu ölçer). Yakalanmazsa proxy'li uygulamalar sınırlanamaz; olası B planı
  filtrede `NEFilterDataVerdict.pause()`/`resumeFlow` ile yavaşlatma.
- **Çift sayım**: aktarım bağlantısı `setMetadata(on:)` ile asıl uygulamaya atanır. Filtre hem asıl akışı hem
  aktarımı görürse kullanım iki kat sayılabilir (3.6 adımı ölçer). Kimliği sysext'in kendisi olan akışlar filtrede
  sayılmaz.
- **Açık bağlantılar**: sınır yalnızca yeni akışlara uygulanır (sınır kaldırma ise açık akışlarda da anında etkili).
- **UDP/QUIC**: UDP aktarılmaz. Sınırlı uygulamaların UDP/443'ü filtrede düşürülür (TCP'ye geri dönüş).
  Diğer UDP (ör. oyun, WebRTC, DNS) sınırsızdır.
- **On-demand kuralı**: `NETransparentProxyManager` üzerinde `isOnDemandEnabled` + `NEOnDemandRuleConnect`
  (yeniden başlatmada otomatik açılsın diye) bu proxy türünde doğrulanmadı. İlk kayıt hata verirse
  (`ExtensionInstaller.applyProxy`, ayarlardaki hata metni) önce bu kuralı şüphele.
- **"Açık" göstergesi iyimser**: `proxyActive`, `startVPNTunnel()` döner dönmez true olur; gerçek kontrol
  `scutil --nc list` ve log'daki `transparent proxy started`.
- **İlk onay**: ilk sınırda macOS proxy yapılandırması onayı ister; reddedilirse ayarlar bölümünde hata görünür.
- **Ek yük**: sınır yokken proxy kapalıdır. Sınır varken tüm giden TCP akışları `handleNewFlow`'a uğrar;
  sınırsız uygulamalar için anında `false` döner (kimlik önbellekli).
