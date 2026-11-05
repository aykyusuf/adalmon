# macOS'ta uygulama başına (ve alan adı başına) ağ kullanımı ölçümü, mobil veri uyarısı

Tarih: 2026-11-05 · Hedef: macOS 26+ (bu makine: macOS 27.2, build 26B123, arm64)
Kapsam: SpoofDPI/ByeDPI **yerel proxy** (sistem HTTP/HTTPS/SOCKS proxy ayarı) arkasında doğru uygulama atfı; iPhone Kişisel Erişim Noktası (Wi-Fi + USB) tespiti.

Etiketler: **[DOĞRULANDI]** = bu makinede komut çıktısında, xnu kaynak kodunda ya da Apple dokümanında/forumunda görüldü. **[ÇIKARIM]** = tasarım önerisi ya da doğrulanmamış varsayım. **[AÇIK]** = test edilmesi gereken nokta.

Not: İstenen yol (`.../scratchpad/r2-ag-olcum.md`) salt-okunur ajan kuralı nedeniyle engellendi; rapor bu dosyada.

---

## 1. Bu makinede yapılan yerel kontroller (salt okunur)

| Kontrol | Sonuç |
|---|---|
| `sw_vers` | macOS 27.2 (26B123), arm64 [DOĞRULANDI] |
| `ps aux` | `~/Desktop/spoofdpi` çalışıyor (PID 16296) [DOĞRULANDI] |
| `scutil --proxy` | HTTPProxy ve HTTPSProxy = 127.0.0.1:8080, istisnalar `*.local` ve `169.254/16` [DOĞRULANDI] |
| `route get default` / `scutil --nwi` | Birincil arayüz en0 (Wi-Fi), 192.168.x.x [DOĞRULANDI] |
| Arayüzler | en0 (Wi-Fi), en1-3 (Thunderbolt), en4-6 (Ethernet Adapter), bridge0, ap1, awdl0, llw0, utun0-9, anpi*, nan0. Şu an bağlı bir "iPhone USB" portu yok [DOĞRULANDI] |
| `codesign -d --entitlements - /usr/bin/nettop` | `com.apple.private.network.statistics = true` [DOĞRULANDI] |
| `sysctl net.statistics_privcheck` | `0` [DOĞRULANDI] |
| Ek gözlem | kurumsal bir VPN istemcisinin süreçleri var (kurumsal VPN/ajan olabilir) [ÇIKARIM] |

### 1.1 Kritik bulgu: nettop'ta çift sayım ve proxy'ye kayma [DOĞRULANDI]

`nettop -P -L 1 -x -J bytes_in,bytes_out` (süreç modu) sonuçları:
- `spoofdpi.16296` yaklaşık 2.545 GB giriş ve 2.545 GB çıkış gösteriyor. Aynı trafik iki kez sayılıyor: bir kez internetten **en0** üzerinden giriyor, bir kez de uygulamaya **lo0** üzerinden çıkıyor.
- `nsurlsessiond` 2.46 GB gösteriyor, ama bu trafiğin tamamı `tcp4 127.0.0.1:50059<->127.0.0.1:8080, lo0` akışında. Yani uygulama tarafındaki sayı aslında proxy'ye giden loopback trafiği.
- `Google Chrome H` (süreç adı 15 karakterde kesiliyor) hem `lo0 ->127.0.0.1:8080` akışları hem de doğrudan en0 akışları gösteriyor (ör. `108.177.96.188:5228`, GCM push; `34.54.194.141:443`). Bunlar proxy'yi kullanmayan bağlantılar (QUIC/UDP veya proxy'yi atlayan istemci).
- Akış modu (`nettop -L 1 -x -n -J bytes_in,bytes_out,interface`) her soketi arayüzüyle birlikte veriyor. spoofdpi tarafında çiftler şöyle görünüyor: `127.0.0.1:8080<->127.0.0.1:50397 (lo0)` ve `192.168.x.x:50398<->17.253.15.135:443 (en0)`.

**Sonuç:** `nettop -P` toplamları iki yönde de yanlış. Proxy iki kat sayılıyor, uygulamalar ise yalnızca loopback üzerinden görünüyor. Doğru hesap **akış (flow) düzeyinde** yapılmalı.

### 1.2 Muhasebe kuralı (önerilen) [ÇIKARIM, 1.1 verisine dayanıyor]

1. Uygulamanın `remote = 127.0.0.1:<proxyPort>` (veya ::1) akışları → **o uygulamanın WAN trafiği** sayılır. Proxy portu `scutil --proxy` / `SCDynamicStoreCopyProxies` üzerinden alınır, SOCKS da dahil.
2. Uygulamanın loopback olmayan akışları (en0, iPhone USB arayüzü vb.) → doğrudan uygulamaya sayılır. Proxy'yi yok sayan trafik budur: QUIC, CLI araçları, kendi ağ yığınını kullanan uygulamalar.
3. Proxy sürecinin (spoofdpi/ciadpi/byedpi) fiziksel arayüz akışları → **uygulamalara sayılmaz**. Bunlar yalnızca "toplam WAN" ve mutabakat için kullanılır.
4. Diğer bütün lo0 trafiği yok sayılır (proxy'nin 8080 tarafı dahil).
5. Mutabakat: `Σ(uygulama→proxy loopback) ≈ proxy'nin fiziksel arayüz toplamı`. Aradaki fark proxy ek yükü artı proxy'nin kendi DNS/DoH trafiğidir. Bu fark "SpoofDPI ek yükü" diye ayrı bir satırda gösterilir.
6. Gerçek arayüz toplamı için `getifaddrs` + `if_data` (ifi_ibytes/ifi_obytes) ile fiziksel arayüz sayaçları okunur. Uygulama toplamının kontrolü buna göre yapılır (bkz. §4.6).

Not: Uygulamanın loopback soketini proxy'nin hangi upstream soketine eşlediğini bilmek bayt sayımı için **gerekmez**. Yalnızca alan adı atfı için gerekir, o da §3'teki CONNECT yöntemiyle çözülüyor. Yukarıdaki 50397/50398 port bitişikliği tesadüftür, buna güvenilmemeli.

---

## 2. Mobil veri (hotspot) tespiti

### 2.1 NWPathMonitor
- `NWPath.isExpensive`: Apple dokümanına göre "Cellular veya Personal Hotspot gibi pahalı sayılan bir arayüz kullanılıyorsa" true döner [DOĞRULANDI: https://developer.apple.com/documentation/network/nwpath/isexpensive].
- `NWPath.isConstrained`: Düşük Veri Modu (Low Data Mode) açıksa true döner. macOS'ta ağ bazında açılabiliyor [DOĞRULANDI: Apple dokümanı ve docs.rs macstate-core özeti].
- Wi-Fi hotspot'ta arayüz tipi yine `.wifi` olarak görünüyor. Apple forumunda "hotspot mu, normal AP mi" sorusuna arayüz tipiyle cevap verilemeyeceği söyleniyor [DOĞRULANDI: https://developer.apple.com/forums/thread/128832]. Doğru sinyal `isExpensive`.
- macOS'un iPhone hotspot'u nasıl tanıdığı (Apple'ın beacon'daki vendor IE'si / DHCP seçeneği) [ÇIKARIM]. Bu davranış Apple'a ait, belgelenmemiş.

### 2.2 Çekirdek düzeyi sinyal (ntstat) [DOĞRULANDI: xnu bsd/net/ntstat.c]
- ntstat her akış için `ifnet_properties` alanında `NSTAT_IFNET_IS_EXPENSIVE`, `NSTAT_IFNET_IS_CELLULAR`, `NSTAT_IFNET_IS_LOOPBACK` ve `NSTAT_IFNET_VIA_CELLFALLBACK` bayraklarını taşıyor (ntstat.c satır ~963-1050, `IFNET_IS_EXPENSIVE(ifp)` kontrolü). Bu sayede ntstat istemcisi akış başına "pahalı arayüz" bilgisini doğrudan alabilir.

### 2.3 USB tethering [AÇIK]
- iPhone USB bağlandığında macOS genelde "iPhone USB" adlı bir hardware port ve yeni bir `enX` arayüzü oluşturur [ÇIKARIM, yaygın bilgi; bu makinede şu an yok].
- Bu arayüzün `isExpensive` olarak işaretlendiği beklenir, ama **doğrulanmadı**. NWInterface tipinin `.wiredEthernet` mi `.other` mı olduğu da doğrulanmadı.
- Tethering sırasında çalıştırılacak test komutları:
  - `networksetup -listallhardwareports` (port adı "iPhone USB" mi, hangi enX)
  - `scutil --nwi` (birincil arayüz)
  - `ioreg -p IOUSB -l | grep -i iphone` (USB cihazı)
  - Küçük bir Swift betiği: `NWPathMonitor` ile `isExpensive`, `isConstrained`, `availableInterfaces.map{($0.name,$0.type)}` loglanır.
  - `nettop -L 1 -x -n -J interface,bytes_in` ile o enX'in göründüğü doğrulanır.
- Bluetooth PAN: `bluetooth-pan` / `en` arayüzü. Aynı testler yapılmalı.

### 2.4 Önerilen karar mantığı [ÇIKARIM]
`mobil = path.isExpensive || path.isConstrained || birincilArayüz ∈ {iPhone USB portu} || SSID ∈ kullanıcı listesi`.
SSID (CoreWLAN) okumak macOS 14+ sürümlerde Konum izni ister. Yedek sinyal olarak kullanılabilir. Arayüz değişince (NWPathMonitor callback'i) "oturum" kaydı açılır ve o andan sonraki bütün baytlar bu arayüze etiketlenir.

---

## 3. Atıf: proxy arkasında uygulama ve alan adı

### 3.1 NEFilterDataProvider (içerik filtresi system extension'ı) — hedef mimari

**Doğrulanmış gerçekler:**
- Loopback akışları filtreye **yalnızca açık bir kuralla** gelir. Joker (`0.0.0.0`/`::`/nil) kurallar loopback'i kapsamaz. Apple DTS mühendisi Matt Eaton'ın testinde `127.0.0.1`'i hem local hem remote network olarak veren tek bir `NENetworkRule` kullanıldı. `curl 127.0.0.1:8080` akışı `sourceAppIdentifier=com.apple.curl`, `remoteEndpoint=127.0.0.1:8080`, outbound, TCP olarak filtreye düştü [DOĞRULANDI: https://developer.apple.com/forums/thread/668813].
- macOS 15 Sequoia'da eski `NWHostEndpoint` tabanlı init (deprecated) ile loopback akışları gelmez oldu. Yeni `NENetworkRule` init'iyle tekrar geldi [DOĞRULANDI (tek geliştirici raporu, Apple cevabı yok): https://developer.apple.com/forums/thread/762619]. macOS 26 hedefinde **yeni init** kullanılmalı (Network.framework `NWEndpoint` tabanlı).
- `NEFilterFlow.sourceAppAuditToken` + `sourceProcessAuditToken` (macOS 13+). Bir sistem süreci bir uygulama adına bağlantı açtığında bu ikisi farklı olur [DOĞRULANDI: https://developer.apple.com/documentation/networkextension/nefilterflow/sourceprocessaudittoken]. Bu sayede nsurlsessiond trafiği asıl uygulamaya atfedilebilir.
- `NEFilterReport`: `bytesInboundCount`, `bytesOutboundCount`, `event` (flowClosed / statistics), `flow` [DOĞRULANDI: docs.rs objc2-network-extension NEFilterReport].
- `NEFilterNewFlowVerdict.statisticsReportFrequency` (macOS 10.15.4+): `.low` ~5 sn, `.medium` ~1 sn, `.high` ~0.5 sn. Varsayılan `.none` [DOĞRULANDI: https://developer.apple.com/documentation/networkextension/nefilterreport/frequency]. "Son 60 saniyede 400 MB" hesabı için `.medium` yeterli.

**Tasarım (alan adı için) [ÇIKARIM]:**
- Proxy'ye giden akışta remote 127.0.0.1 olduğundan `remoteHostname` işe yaramaz. Çözüm: `handleNewFlow` içinde `filterDataVerdict(withFilterInbound:false, peekInboundBytes:0, filterOutbound:true, peekOutboundBytes:~1024)` döndürülür. `handleOutboundData` içinde ilk baytlar okunur:
  - HTTP proxy: `CONNECT www.youtube.com:443 HTTP/1.1` satırı ayrıştırılır (düz HTTP için `GET http://host/...`).
  - SOCKS5: el sıkışmadan sonraki CONNECT isteğindeki ATYP=0x03 alan adı okunur (ByeDPI/ciadpi SOCKS modu).
  - Ardından `.allow()` verdict'i verilir. Akış ömrü boyunca bayt sayımı statistics raporlarından gelir.
- Doğrudan (proxy'siz) akışlarda `remoteHostname` (Apple yığını hostname'i biliyorsa) kullanılır. Yoksa TLS ClientHello'daki SNI peek ile alınır. QUIC'te SNI şifreli Initial paket içinde olduğundan zordur. Bu durumda DNS korelasyonu (IP→son sorgulanan ad) yedek olarak kullanılır.
- Proxy sürecinin (spoofdpi) kendi en0 akışları da filtreye gelir (kaynak = spoofdpi). Bunlar §1.2 kural 3'e göre uygulamaya sayılmaz, yalnızca mutabakatta kullanılır.
- Arayüz bilgisi: `NEFilterFlow` arayüz/pahalılık bilgisi vermez (dokümanda görmedim) [AÇIK]. Akışlar, NWPathMonitor'dan alınan o anki "oturum" (Wi-Fi/hotspot) etiketiyle işaretlenir. Loopback akışında arayüz zaten lo0'dır. Proxy'nin çıktığı arayüz, birincil arayüzdür.

**Açık noktalar [AÇIK]:**
- Peek sonrasında `.allow()` dönülünce statistics raporlarının akış boyunca gelmeye devam edip etmediği test edilmeli. `statisticsReportFrequency` `NEFilterDataVerdict` üzerinde de var. Raporlar kesiliyorsa son data verdict'inde de ayarlanmalı.
- Loopback kuralının macOS 26/27'de yeni init ile çalıştığı bu makinede doğrulanmadı.
- Filtrenin akış başına CPU maliyeti: yalnızca ilk ~1 KB peek edilince düşük olur [ÇIKARIM].

**Gerekenler:** Developer ID ile `com.apple.developer.networking.networkextension` = `content-filter-provider-systemextension` (Developer ID dağıtımı için `-systemextension` sonekli değer), `com.apple.developer.system-extension.install`, host app `/Applications` içinde olmalı, kullanıcı System Settings'te uzantıyı onaylamalı, `NEFilterManager` yapılandırması yapılmalı. Açık kaynak iskelet: Objective-See **LuLu** (GPL-3.0, NEFilterDataProvider, 2026-11'de güncel) https://github.com/objective-see/LuLu [repo tazeliği DOĞRULANDI. Bayt sayımı yapmıyor, iskelet olarak kullanılır].

### 3.2 Chrome / PWA / helper toplama
- nettop'ta süreç adı kesiliyor ("Google Chrome H") [DOĞRULANDI]. PID → `proc_pidpath` → bundle → üst `.app` ile ya da `responsibility_get_pid_responsible_for_pid` (özel API) ile "Google Chrome"a toplanır. NE yolunda `sourceAppAuditToken` → `audit_token_to_pid` → `SecCodeCopyGuestWithAttributes` → imza kimliği (`com.google.Chrome`) kullanılır. Helper'lar da aynı team/imza ile görünür [ÇIKARIM].
- **Chrome PWA ayrımı süreç düzeyinde mümkün değil.** Bütün sekmeler ve PWA'lar tek "Network Service" helper süreci üzerinden çıkar. PWA shim'i (`app_mode_loader`) ağ trafiği yapmaz [ÇIKARIM, Chrome mimarisine dayanıyor]. Ayrım ancak **alan adı** (CONNECT host / SNI) ile yapılabilir: "Chrome → youtube.com / googlevideo.com".
- YouTube için `*.googlevideo.com`, `*.youtube.com`, `*.ytimg.com` tek grupta toplanmalı [ÇIKARIM].

### 3.3 Little Snitch / TripMode nasıl yapıyor?
- TripMode 3: Macworld incelemesi "network filter" yaklaşımı kullandığını, kernel eklentisi kullanmadığını yazıyor. Eski sürümde kext vardı (TidBITS 2015) [DOĞRULANDI (ikincil kaynak): https://www.macworld.com/article/344699/tripmode-3-review.html, https://tidbits.com/2015/07/22/tripmode-prevents-unwanted-internet-data-usage-on-a-tethered-mac/]. Kesin API (NEFilterDataProvider mı, packet mı) belgelenmemiş [ÇIKARIM: içerik filtresi].
- Little Snitch 5/6: NetworkExtension tabanlı. heise'ye göre sunucu adını bulmak için paket içeriğine de bakıyor [DOĞRULANDI (ikincil): https://heise.de/-9732997]. Yerel proxy arkasındaki atıf için resmi belge bulunamadı. 2020 tarihli bir V2EX raporu, yerel PAC proxy trafiğinin LS'de beklenen şekilde görünmediğini söylüyor (eski) [https://v2ex.com/t/638903]. LS 6.2.4 nightly, XPC helper bağlantılarını App Extension'a atfetmeye başladı [https://www.obdev.at/littlesnitch/download-nightly.html].

---

## 4. Aday mekanizmalar (artı/eksi)

### 4.1 `nettop` CLI ayrıştırma
- Artı: Root gerekmez. Apple imzalı ve `com.apple.private.network.statistics` yetkisine sahip [DOĞRULANDI], bu yüzden kullanıcı alanı yığını (Network.framework userland QUIC/TCP) akışlarını da görür. Akış başına arayüz ve 4'lü adres verir [DOĞRULANDI].
- Eksi: Metin çıktısı, kararlı bir arayüz değil. Süreç adı kesiliyor. Alan adı yok. `-L 1` kümülatif sayaç verir ve kısa ömürlü akışları kaçırabilir; sürekli mod (`-d -s 1`) ile delta alınmalı [AÇIK]. CPU maliyeti şikâyetleri var (exelban/stats #536) [https://github.com/exelban/stats/issues/536].
- MVP için en hızlı yol. exelban/stats ve macpow crate de nettop'u bu şekilde ayrıştırıyor.

### 4.2 Özel NetworkStatistics.framework / `com.apple.network.statistics` kernel control (ntstat)
- [DOĞRULANDI: xnu ntstat.c] macOS'ta `nstat_privcheck = 0` (sysctl `net.statistics_privcheck`, bu makinede 0). `add_all` için TCP/UDP sağlayıcıları **yetkisiz** çalışır. Ancak `NSTAT_PROVIDER_CONN_USERLAND` ve `NSTAT_PROVIDER_UDP_SUBFLOW` her zaman yetki kontrolüne tabi. Kod yorumu: "Extensions give away additional privacy information and are subject to unconditional privilege check".
- [DOĞRULANDI: xnu ntstat.h] Gizli uzantılar arasında `NSTAT_EXTENDED_UPDATE_TYPE_DOMAIN` (alan adı bilgisi) var, yani **Developer ID uygulaması ntstat'tan alan adı alamaz.**
- [ÇIKARIM] Sonuç olarak doğrudan ntstat istemcisi kernel TCP/UDP soketlerini (Chrome, spoofdpi, çoğu uygulama) görür, ama Network.framework'ün kullanıcı alanı yığınındaki akışları (bazı Apple süreçleri, Safari'nin bazı QUIC'leri) kaçırabilir. `epid` (delege eden PID) alanı var [DOĞRULANDI], bu nsurlsessiond delegasyonu için faydalı.
- Risk: sysctl RW. iOS'ta varsayılan 1. Apple macOS'ta da 1'e çevirebilir.
- Açık kaynak örnekler [gh code search ile DOĞRULANDI]:
  - https://github.com/fenek-dev/system-monitoring (`NStatManagerCreate` weak_import, 2026-10'da güncel)
  - https://github.com/kriztioan/MacOSSysStats (`NStatManager.h`, 2026-11'de güncel)
  - https://github.com/doug-leith/appFirewall (`C workers/netstats.h`, 2025-10)
  - https://github.com/hack-different/newosxbook-tools `src/netbottom.c` (J. Levin, entitlement plist dahil)
  - https://github.com/L1MeN9Yu/Marauders (Swift, MIT, 2022, eski)
  - Kernel başlığı: https://github.com/apple-oss-distributions/xnu/blob/main/bsd/net/ntstat.h

### 4.3 NetworkExtension
- **NEFilterDataProvider** (önerilen): yukarıda, §3.1.
- **NEFilterPacketProvider**: paket düzeyi, süreç atfı yok (yalnızca paket). Bayt sayımına uygun değil ve pahalı.
- **NETransparentProxyProvider**: akışı üstlenir ve trafiği kendin taşırsın. Bayt sayımı kesin olur, ama SpoofDPI ile zincirleme karmaşık; loopback akışlarını üstlenmek ve proxy ile etkileşmek riskli [ÇIKARIM]. Yalnızca ölçüm için gereksiz.
- **NEAppProxy / NEPacketTunnel**: VPN slotunu kullanır. DPI aracı VPN modunda çalışırsa çakışır. Gereksiz.
- **NEDNSProxyProvider**: DNS korelasyonu için mümkün, ama SpoofDPI DoH kullanıyorsa sistem DNS'ini görmez. Proxy modunda uygulamalar DNS'i zaten yapmaz (CONNECT host'u proxy çözer) [ÇIKARIM].

### 4.4 `proc_pid_rusage` / libproc
- `rusage_info_v*` içinde ağ bayt alanı yok (ri_diskio vardır, ağ yoktur) [ÇIKARIM, bilinen yapı]. Kullanılamaz.
- `sysctl net.inet.tcp.pcblist_n`: soket listesi verir, bayt sayacı ve PID atfı sınırlı. Önerilmez.

### 4.5 BPF (`/dev/bpf*`)
- netoproc (Rust, macOS 26+) BPF ile paket yakalayıp süreç tablosuyla eşliyor, root gerekiyor [DOĞRULANDI: https://docs.rs/crate/netoproc/0.2.0/source/CLAUDE.md]. Loopback'te de yakalanabilir ama atıf heuristic. Yedek seçenek.

### 4.6 `getifaddrs` / `if_data`
- Arayüz toplamları için güvenilir, yetki gerektirmez (32-bit sarma riskine karşı `sysctl NET_RT_IFLIST2` / `if_data64` kullanılmalı) [ÇIKARIM]. "Hotspot'ta bugün toplam X GB" ve günlük limit kontrolü için **gerçek referans** budur. Uygulama dağılımı bunun alt kırılımıdır.

### 4.7 Endpoint Security
- Bayt sayımı vermez. Yalnızca süreç ağacı ve responsible süreç bilgisi için yardımcı olur. Gerekmez.

---

## 5. Önerilen mimari

**Katman 0 — her zaman açık:**
- `NWPathMonitor` → mobil oturum tespiti (`isExpensive || isConstrained || iPhone USB || SSID listesi`).
- `if_data64` ile fiziksel arayüz sayaçları, 1 sn aralıkla → günlük toplam, limit (2-3 GB) ve bildirim (`UNUserNotificationCenter`).
- Kalıcı depolama: SQLite (GRDB), tablo `usage(day, app_bundle, domain_group, iface_kind, bytes_in, bytes_out)` artı dakikalık ring buffer (son 60 sn uyarısı için).

**Katman 1 — MVP (system extension'sız, hemen):**
- `nettop -L 0 -d -s 1 -x -n -J interface,bytes_in,bytes_out` sürekli modda, **akış düzeyinde** ayrıştırılır (`-P` kullanılmaz). §1.2 muhasebe kuralı uygulanır. PID → responsible app ile toplanır. Alan adı yok, ama uygulama başına doğru bayt verir. Mutabakat `if_data` ile yapılır.

**Katman 2 — Hedef (maksimum doğruluk):**
- NEFilterDataProvider system extension'ı:
  - Kurallar: loopback (127.0.0.1, ::1, yeni init) + bütün TCP/UDP outbound, `.filterData`.
  - `handleNewFlow`: audit token → bundle/imza. Loopback ve proxy portuysa ilk ~1 KB outbound peek → CONNECT/SOCKS host. Değilse `remoteHostname` / SNI peek.
  - Verdict'te `statisticsReportFrequency = .medium`. `handle(_ report:)` ile delta baytlar hesaplanır ve XPC ile ana uygulamaya gönderilir.
  - Proxy süreci akışları yalnızca mutabakat için kullanılır.
- Fail-open: uzantı çökerse trafik kesilmemeli. Bunun için `defaultAction` allow ve hızlı verdict verilmeli.

**Katman 3 — Yedek:** Doğrudan ntstat istemcisi (CONN_USERLAND boşluğu kabul edilerek) veya BPF (root).

**Neden bu sıra:** nettop yaklaşımı bugün bu makinede doğru akış verisi gösterdi. NE filtresi ise alan adını (CONNECT host) ve audit token'ı (nsurlsessiond delegasyonu dahil) sunan **tek** resmi ve kararlı API.

---

## 6. macOS 15/26 kırılma notları
- macOS 15: `NWHostEndpoint` tabanlı `NENetworkRule` init'leri deprecated oldu. Loopback filtrelemesi eski init ile bozuldu (forum raporu).
- `com.apple.private.network.statistics` hâlâ özel. Üçüncü taraf alamaz. macOS 27.0 beta'larında bu entitlement'ın yeni ikililere eklendiği görülüyor (blacktop/ipsw-diffs) [gh arama sonucu].
- `net.statistics_privcheck` macOS'ta 0, ama çalışma zamanında değiştirilebilir ve Apple ileride 1 yapabilir.
- Kullanıcı yorumlarına göre TripMode'un network filtresi yeni macOS sürümlerinde Wi-Fi kopmalarına yol açabiliyor [anekdot, Setapp yorumları]. İçerik filtresi yazarken fail-open ve hızlı verdict önemli.

## 7. Açık noktalar / test listesi
1. iPhone USB tethering: port adı, enX, `isExpensive`, NWInterface tipi.
2. Wi-Fi hotspot'ta `isExpensive` değerinin true olduğunun bu Mac'te doğrulanması.
3. Yeni `NENetworkRule` init'i ile macOS 27'de loopback akışlarının filtreye geldiği.
4. Peek + allow sonrasında statistics raporlarının akış boyunca devam ettiği.
5. ByeDPI'ın SOCKS modunda SOCKS5 alan adı mı yoksa IP mi gönderildiği (istemci Chrome ise `socks5h` davranışı).
6. nettop sürekli modda kısa ömürlü akışların kaçırılıp kaçırılmadığı ve CPU maliyeti.
7. Makinedeki kurumsal VPN istemcisi NE filtresiyle etkileşimi.

## Kaynaklar
- https://developer.apple.com/documentation/network/nwpath/isexpensive
- https://developer.apple.com/forums/thread/128832
- https://developer.apple.com/forums/thread/668813
- https://developer.apple.com/forums/thread/762619
- https://developer.apple.com/documentation/networkextension/nefilterflow/sourceprocessaudittoken
- https://developer.apple.com/documentation/networkextension/nefilternewflowverdict/statisticsreportfrequency
- https://developer.apple.com/documentation/networkextension/nefilterreport/frequency
- https://docs.rs/objc2-network-extension/latest/objc2_network_extension/struct.NEFilterReport.html
- https://github.com/apple-oss-distributions/xnu/blob/main/bsd/net/ntstat.c (satır 97-102, 876, 963-1050, 4279, 6864, 6897-6901)
- https://github.com/apple-oss-distributions/xnu/blob/main/bsd/net/ntstat.h (satır 829-916)
- https://github.com/exelban/stats/issues/536
- https://github.com/objective-see/LuLu
- https://www.macworld.com/article/344699/tripmode-3-review.html
- https://heise.de/-9732997
- https://docs.rs/crate/netoproc/0.2.0/source/CLAUDE.md
