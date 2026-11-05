# Adalmon: macOS menü çubuğu monitörü için metrik API'leri (Apple Silicon, macOS 26/27)

Tarih: 2026-11-05. Test makinesi: macOS 27.2, `hw.perflevel0` = Performance (4 çekirdek), `hw.perflevel1` = Efficiency (6), `hw.nperflevels` = 2 (yerelde `sysctl` ile doğrulandı).

Etiketler: **[DOĞRULANDI]** = açık kaynak kodda/çıktıda gördüm. **[ÇIKARIM]** = hafızadan/genel bilgi, bu oturumda doğrulanmadı; kodlamadan önce küçük deneyle teyit et.

Okunan kaynaklar:
- Stats: https://github.com/exelban/stats (Modules/CPU|GPU|RAM|Disk|Net|Sensors, SMC/smc.swift)
- macmon: https://github.com/vladkens/macmon (src/sources.rs, src/metrics.rs, issue #76, #78, release v0.9.0)
- asitop: https://github.com/tlkh/asitop (utils.py; `sudo powermetrics` kullanır, uygun değil)
- Okunmayanlar (yalnızca bağlantı): NeoAsitop https://github.com/op06072/NeoAsitop, socpowerbud https://github.com/dehydratedpotato/socpowerbud, SMCKit https://github.com/beltex/SMCKit (Intel odaklı, eski), iStats https://github.com/Chris911/iStats (Ruby, Intel SMC).

## 0. Mimari özet
- Tek `Sampler` + tek `DispatchSourceTimer`; popover kapalıyken yalnızca menü çubuğunda görünen metrikler okunur.
- Public API (CPU, RAM, disk, ağ, swap, basınç): sandbox/sudo gerekmez.
- Private API: IOReport (GPU frekansı, watt), IOHIDEventSystemClient (sensör sıcaklığı). `dlopen`/`dlsym` ile yükle, sembol yoksa metriği sessizce kapat.
- `ps`, `top`, `nettop`, `uptime` spawn etme. Stats bunları kullanıyor [DOĞRULANDI: CPU top `ps -Aceo pid,pcpu,comm -r`; RAM top `top -l 1 -o mem`; ağ process modu `nettop`; load `uptime` 15 sn'de bir]. fork+exec maliyeti %0.5 hedefiyle uyumsuz.

## 1. CPU
### 1.1 Toplam ve çekirdek başına
Stats `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` + `host_statistics(HOST_CPU_LOAD_INFO)`, önceki snapshot ile fark, busy = user+system+nice [DOĞRULANDI].
```swift
var count: natural_t = 0
var info: processor_info_array_t? = nil
var infoCount: mach_msg_type_number_t = 0
guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS, let info else { return }
defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
        vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)) }
for i in 0..<Int(count) {
    let b = i * Int(CPU_STATE_MAX)
    let user = UInt32(bitPattern: info[b + Int(CPU_STATE_USER)])   // system/idle/nice benzer
    // delta = cur &- prev  (32-bit tick, wrap güvenli)
}
```
Busy oranı = (u+s+n)/(u+s+n+idle) Δ'ları üzerinden. `vm_deallocate` unutulursa sızar.

### 1.2 P/E ayrımı
- Sayılar: `sysctlbyname("hw.perflevel0.logicalcpu")` (P), `hw.perflevel1.logicalcpu` (E); `hw.perflevelN.name` [DOĞRULANDI yerelde]. M5 Pro/Max ve M6'da 3 katman var (macmon ECPU/MCPU/PCPU, PR #85 "three CPU tiers on M6") [DOĞRULANDI]: `hw.nperflevels` kadar döngü kur.
- `host_processor_info` indeks → P/E eşlemesi [ÇIKARIM]: E çekirdekler genelde düşük indekste. Stats `hw.perflevel` kullanmıyor, kendi `SystemKit` topolojisini kullanıyor [DOĞRULANDI]. Sırayı açılışta yük testiyle ölç, sabit varsayma.

### 1.3 Frekans (opsiyonel)
IOReport "CPU Stats"/"CPU Core Performance States" residency + DVFS tablosu (`pmgr` `voltage-states1-sram`, `voltage-states5-sram`; M1-M3 Hz, M4+ kHz) [DOĞRULANDI macmon]. UYARI macmon #78: M4'te IOReport istenen DVFS durumunu gösteriyor, gerçek frekansı değil (powermetrics 3936 MHz, IOReport 4464 MHz) [DOĞRULANDI issue, tek rapor]. "Yaklaşık" diye etiketle.

### 1.4 Load average
`getloadavg(&d, 3)` [ÇIKARIM, standart libc].

### 1.5 Process başına CPU
```swift
let n = proc_listallpids(nil, 0)
var pids = [pid_t](repeating: 0, count: Int(n) + 64)
_ = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
var ru = rusage_info_current()
_ = withUnsafeMutablePointer(to: &ru) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0) } }
// ri_user_time + ri_system_time (mach ticks), ri_phys_footprint, ri_diskio_bytesread/byteswritten
```
- CPU% = Δ(user+system) → ns için `mach_timebase_info` (Apple Silicon 125/3, tick != ns) / Δduvar süresi [ÇIKARIM, klasik hata].
- Stats `proc_pid_rusage`'ı disk okuma için kullanıyor, CPU için `ps` [DOĞRULANDI].
- Maliyet: ~500-800 PID × çağrı birkaç ms; yalnız popover açıkken 2-3 sn'de bir. Başka kullanıcı/root süreçlerinde EPERM olabilir, atla [ÇIKARIM].

## 2. GPU, güç, frekans
### 2.1 Kullanım
IOKit `IOAccelerator` → `PerformanceStatistics`. Stats anahtarları [DOĞRULANDI Modules/GPU/reader.swift]: `"Device Utilization %"` (yedek `"GPU Activity(%)"`), `"Renderer Utilization %"`, `"Tiler Utilization %"`, `"Temperature(C)"`, `"Fan Speed(%)"`, `"Core Clock(MHz)"`, `"Memory Clock(MHz)"`. Apple Silicon'da kullanım aynı anahtardan, IOReport'tan değil [DOĞRULANDI].
```swift
var it: io_iterator_t = 0
IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOAcceleratorClassName), &it)
while case let s = IOIteratorNext(it), s != 0 {
    let p = IORegistryEntryCreateCFProperty(s, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? [String: Any]
    let util = (p?["Device Utilization %"] as? Int) ?? (p?["GPU Activity(%)"] as? Int)
    IOObjectRelease(s)
}
IOObjectRelease(it)
```
### 2.2 GPU belleği
[ÇIKARIM] `PerformanceStatistics` içinde `"In use system memory"` / `"Alloc system memory"` (birleşik bellek). Stats okumuyor [DOĞRULANDI: yalnızca memory clock]. `ioreg -r -c IOAccelerator -w0` ile doğrula.
### 2.3 Frekans
macmon: IOReport "GPU Stats"/"GPU Performance States", kanal `GPUPH`, tablo `voltage-states9`, index 0 = OFF [DOĞRULANDI].
### 2.4 Güç (sudo'suz)
- asitop `sudo powermetrics --samplers cpu_power,gpu_power,thermal` [DOĞRULANDI], root ister, uygun değil.
- macmon/Stats IOReport [DOĞRULANDI]: `IOReportCopyAllChannels(0,0)` veya `IOReportCopyChannelsInGroup("Energy Model", nil,0,0,0)`, `IOReportCreateSubscription(nil, chan, &sub, 0, nil)`, `IOReportCreateSamples`, `IOReportCreateSamplesDelta(a,b,nil)`, `IOReportSimpleGetIntegerValue(item,0)`, birim mJ/uJ/nJ; watt = Δenerji/Δsüre. Kanallar: `*CPU Energy`, `GPU Energy`, `ANE*`, `DRAM*`, `GPU SRAM*`. Sistem gücü SMC `PSTR`. Stats ANE% = güç/maks (varsayılan 8 W); FPS = IOReport `DCP*`/`swap` Δsayaç.
- **macOS 27 KIRILMASI** [DOĞRULANDI]: macmon #76 (M3 Max 27.0 beta; M3 Pro 27.0/27.0.1 release): "Energy Model" CPU/DRAM/ANE kanalları 0 W; yalnız `GPU Energy (nJ)` çalışıyor; donan sayaç bir örnekte birikmiş değeri atabiliyor (3564 W). Stats #3621 (M5 Air, macOS 27) CPU Power 0.00 W. macmon v0.9.0 "AppleCLPC sayaçlarıyla sudo'suz çözüm" (`find-clpc` teşhis). sources.rs: AppleCLPC servislerinden sentetik nJ kanalları, öncelik CLPC > Energy Model > PMP [DOĞRULANDI].
- Öneri: CLPC öncelikli; Δ<0 veya fiziksel tavan üstü (>500 W) örnekleri at; uzun süre sıfırsa "veri yok" göster.

## 3. RAM
`host_statistics64(HOST_VM_INFO64)`; Stats formülü [DOĞRULANDI]:
```
used = active + inactive + speculative + wired + compressed - purgeable - external
app = used - wired - compressed ; cache = purgeable + external ; free = total - used
(wired=wire_count, compressed=compressor_page_count, external=external_page_count)
```
macmon aynı toplam [DOĞRULANDI]. Activity Monitor ile birebir olmayabilir [ÇIKARIM]. Sayfa 16 KB: `vm_page_size` kullan.
- Toplam: `hw.memsize`.
- Basınç: (1) `DispatchSource.makeMemoryPressureSource(eventMask:[.normal,.warning,.critical])` olay tabanlı, önerilen [ÇIKARIM]; (2) `sysctl kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical [DOĞRULANDI Stats]; UInt32 buffer kullan (Stats Int/uint karışıklığı yapıyor).
- Swap: `vm.swapusage` → `xsw_usage` [DOĞRULANDI]. Hiç swap yoksa total=0 olabilir.
- Top bellek: `ri_phys_footprint` [ÇIKARIM: Activity Monitor ile aynı kavram]. Stats `top -l 1` + private `responsibility_get_pid_responsible_for_pid` (dlsym) ile gruplama [DOĞRULANDI].

## 4. Disk
- Boş alan: Stats önce `statfs` (+APFS purgeable tahmini, 60 sn cache), `volumeAvailableCapacityForImportantUsage` yedek [DOĞRULANDI]. Finder ile eşleşen değer için `resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey,.volumeTotalCapacityKey])` (purgeable'ı boş sayar); `statfs.f_bavail` saf boş. İkisini göstermek iyi [ÇIKARIM]. `/System/Volumes/Data` kullan [ÇIKARIM]. 30-60 sn aralık yeter.
- Hız: IOMedia → `IOBlockStorageDriver` → `kIOBlockStorageDriverStatisticsKey` → `...BytesReadKey/BytesWrittenKey` kümülatif; sürücüye göre tekilleştir; geri giden sayaç → 0; uyanışta geçmişi sıfırla [DOĞRULANDI Stats]. Dahili NVMe'de çalışıyor (Stats kullanıyor).
- Process başına: `ri_diskio_bytesread/byteswritten` Δ; yeni PID ilk tick 0 [DOĞRULANDI; Stats yalnız okumayı gösteriyor].

## 5. Ağ
- Sayaç: `sysctl([CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, ifindex])` → `if_msghdr2` (`RTM_IFINFO2`) → `ifm_data.ifi_ibytes/obytes` [DOĞRULANDI Stats]. `getifaddrs` AF_LINK `if_data` 32-bit sayaç (4 GB'ta sarar) [ÇIKARIM, iyi bilinen]; Stats getifaddrs'ı yalnız bayrak/baud için kullanıyor [DOĞRULANDI].
- Anomali: negatif Δ → 0; Δ > linkhızı×1.5×aralık → 0 (fallback 100 Gbps) [DOĞRULANDI Stats].
- Birincil arayüz: `SCDynamicStore` `State:/Network/Global/IPv4` `PrimaryInterface`; sanal önek (`utun, ipsec, ppp, tun, tap, gif, stf, wg`) ise `Setup:/Network/Global/IPv4` `ServiceOrder` ile Router'ı olan fiziksel servis; son çare getifaddrs UP+RUNNING+IPv4, non-loopback/p2p/sanal [DOĞRULANDI]. Ek dışlama [ÇIKARIM]: `lo0, awdl0, llw0, ap1, anpi*, bridge*`.
- VPN'de trafik utun'dan geçer; gerçek trafik için fiziksel arayüz sayacı. Seçenek sun.
- Process başına ağ: public hafif API yok; Stats `nettop -P -L 1` [DOĞRULANDI]. MVP dışı.

## 6. Sıcaklık / fan / batarya (opsiyonel)
- IOHID (private): matching `PrimaryUsagePage=0xff00`, `PrimaryUsage=0x0005`; `IOHIDServiceClientCopyEvent(svc, 15, 0, 0)`; `IOHIDEventGetFloatValue(ev, IOHIDEventFieldBase(15))`; ad `Product`; 0<T≤150 [DOĞRULANDI macmon]. Stats servisleri 60 sn'de (olay kaçırırsa 5 sn) yeniden keşfediyor [DOĞRULANDI]. macmon yedek adlar: "pACC MTR Temp Sensor", "eACC MTR Temp Sensor", "GPU MTR Temp Sensor".
- SMC: `AppleSMC` servisi (macmon `AppleSMCKeysEndpoint`), `IOServiceOpen`, `IOConnectCallStructMethod` selector 2, `data8`: 9 keyinfo, 5 read, 8 index; tipler `flt `, `sp78`, `fpe2` [DOĞRULANDI]. macmon CPU `Tp*/Te*/Ts*`, GPU `Tg*` önekleri [DOĞRULANDI]. Anahtarlar model/çip bazında değişir (Asahi/OSHI notları, ikincil): `#KEY` + index ile tara, `T` ile başlayanları filtrele, cache'le. macmon #12 (M4 sıcaklık yanlış), Stats #3625/#3659 (A18 Pro/Neo) [DOĞRULANDI başlık]: ham sensör listesi + max göstermek güvenli.
- Fan: `FNum`, `F0Mx` [DOĞRULANDI Stats], `F0Ac` flt anlık RPM [ÇIKARIM/arama]. Okuma root istemez [ÇIKARIM; macmon PSTR'yi sudo'suz okuyor DOĞRULANDI]. Fan KONTROLÜ ayrıcalıklı helper ister; Stats #3716: macOS 27.0'da `SMAppService.daemon` `.notFound` + `register()` EPERM [DOĞRULANDI issue]. Yalnız okuma yap.
- Batarya: `IOPSCopyPowerSourcesInfo` (public) veya `AppleSmartBattery` [ÇIKARIM; Stats Battery okunmadı]. Termal durum: `ProcessInfo.thermalState` [ÇIKARIM].

## 7. macOS 15/26/27 değişiklikleri
| Alan | Durum | Kaynak |
|---|---|---|
| IOReport Energy Model CPU/DRAM/ANE macOS 27'de 0 W | Doğrulandı; macmon 0.9.0 AppleCLPC ile çözdü | macmon #76, v0.9.0 |
| Stats CPU Power 0.00 W (macOS 27) | Doğrulandı | Stats #3621 |
| M4 IOReport frekans = istenen durum | Tek rapor, macOS 26 | macmon #78 |
| 3 katmanlı CPU (M5 Pro/Max, M6) | Doğrulandı | macmon metrics.rs, #85 |
| A18 Pro/MacBook Neo sensör tanıma | Doğrulandı (başlık) | Stats #3625, #3659 |
| SMC fan helper SMAppService macOS 27.0 | Doğrulandı | Stats #3716 |
| Stats 3.0.24 macOS 27.2'de çöküyor | Açık issue | Stats #3725 |
| Menü çubuğu widget genişlik/çizim sorunları | Yalnız başlık okundu | Stats #3216, #3708 |
| Stats ayar sayfaları ~160 MB | Açık issue | Stats #3713 |
| `kIOMasterPortDefault` → `kIOMainPortDefault` | macOS 12+ [ÇIKARIM] | |
| Bresink Mac Power Monitor 2.9: macOS 26 Liquid Glass etiket ve tutarsız cluster frekans düzeltmesi | İkincil | https://www.bresink.com/osx/301025408/history.html |

`host_processor_info`, `host_statistics64`, `getifaddrs`, `proc_pid_rusage`, `PerformanceStatistics` için macOS 26'da kırılma raporu BULUNAMADI (kırılmadığının kanıtı değil). macOS 27.2'de smoke test yaz.

## 8. Örnekleme maliyeti (<%0.5 CPU)
1. Tek `DispatchSourceTimer` (utility QoS), `leeway` = aralığın %10-20'si [ÇIKARIM].
2. Aralıklar [ÇIKARIM]: CPU/ağ/GPU 1-2 sn; RAM/swap 2-5 sn, basınç olay tabanlı; disk alanı 30-60 sn; disk IO 1-2 sn; sıcaklık/fan 3-5 sn; process listeleri yalnız popover açıkken 2-3 sn.
3. IOReport: tek abonelik, önceki ham örnekle Δ (macmon böyle [DOĞRULANDI]); Stats her read'de ~500 ms'de 4 örnek alıyor [DOĞRULANDI], gereksiz.
4. Görünürlük/uyku: gizli metrik örneklenmez; sleep/screensDidSleep'te dur, uyanışta taban çizgisini sıfırla.
5. Subprocess yok; buffer yeniden kullan; `vm_deallocate`/`CFRelease`/`IOObjectRelease` disiplini.
6. UI maliyeti okumadan büyük olabilir [ÇIKARIM]: `NSStatusItem` başlığını yalnız değişince güncelle; popover görünürken güncelle.
7. Ölçüm: `top -pid <pid> -stats cpu -l 10`, Instruments Time Profiler.
8. En pahalı kalem: `proc_listallpids` + N×`proc_pid_rusage`.

## 9. Açık noktalar
- `host_processor_info` indeks → P/E eşlemesi ölçülmedi.
- GPU bellek anahtarları ve Apple Silicon'da `Core Clock(MHz)` varlığı doğrulanmadı.
- macmon AppleCLPC servis/kanal ayrıntıları yalnız özet okundu; port için sources.rs tam okunmalı.
- Stats Sensors `values.swift` ve Battery okuyucu okunmadı. NeoAsitop, socpowerbud, SMCKit, iStats okunmadı.
- macmon 0.9.0 düzeltmesi "desteklenen Mac'lerde" deniyor; her çipte garanti yok.

## 10. Sonraki adım
Implementer: önce public API'lerle (CPU, RAM, swap, disk, ağ) `Sampler`; sonra GPU `PerformanceStatistics`; en son IOReport/CLPC güç ve IOHID sıcaklık, `dlopen` + fail-soft. Güç modülünü (macmon sources.rs tam okuyarak) implementer-hard portlasın.
