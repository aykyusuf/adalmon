# Windows portu ve çok-PC ajan paylaşımı: araştırma raporu

Tarih: 2026-11-09. Durum: **yalnızca analiz, kod yok.** Karar bekleyen noktalar en altta (bölüm 8).

## 0. Özet

| Soru | Cevap |
|---|---|
| Adalmon'u Windows'a taşımak ne kadar zor? | **Tüm uygulama: haftalar-aylar** (Mac'e özel API'lere bağlı ~54 bin satır Swift). **Yalnızca ajan ofisi: kolay**, çünkü tarayıcı istemcisi (~2000 satır JS canvas) zaten var. |
| Tüm oturumları sunucuya paylaşmak kolay mı? | **Evet.** Claude Code hook'ları bunun için yeterli. İlk çalışan sürüm ~1-2 gün (tahmin). |
| 3 PC farklı ağlarda sorun mu? | Hayır. PC'ler yalnızca dışarı HTTPS çıkış yapar, port açmak ya da VPN gerekmez. |
| "Claude aboneliğimdeki tüm oturumlar" | **Resmi bir "hesabın oturumlarını listele" API'si yok.** Pratikte "hesabın oturumları = hook'un çalıştığı her yer". Web (cloud) oturumları ayrı bir kenar durum. |
| Önerilen yol | Faz 1: plugin + küçük sunucu + Mac Adalmon aboneliği. Faz 2 (istenirse): planlayıcıyı JS'e taşıyıp Windows/telefon/tarayıcıda görmek. |

Süre tahminleri benimdir, ölçülmüş değildir.

## 1. İstek ve kısıtlar (kullanıcının sözleriyle özet)

- Uygulama Windows'ta da olsun.
- 3 farklı PC'deki Claude oturumları (ajanlar) tek yerde görünsün. PC'ler **farklı ağlarda**, aynı LAN'da değil.
- Kapsam "Claude aboneliğimdekiler" yani hesaba bağlı oturumlar.
- Kullanıcı izin verecek (opt-in).
- Kendi sunucusu var.
- **Over-engineering istemiyor**, abartılmasın.
- Bu belge dahil: sadece analiz, uygulama sonraki oturumda.

## 2. Mevcut durum (envanter)

Ölçüm: `find ... | xargs cat | wc -l`, 2026-11-09.

| Bölüm | Satır | Not |
|---|---|---|
| `Sources/App` (tüm uygulama) | ~54 400 | SwiftUI + AppKit + SpriteKit + IOKit |
| `Sources/App/Agents` | ~3 400 | hook alıcı, durum makinesi, plugin üretici, web sunucu |
| `Sources/App/Office` | ~7 700 | ofis sahnesi (SpriteKit), planlayıcı, vektör sanat |
| `Sources/App/UI/MainWindow/AgentOffice` | ~1 500 | ofis penceresi, pano, dock |
| `Sources/App/Process` | ~3 200 | süreç listesi, tarayıcı sekmeleri |
| `Sources/App/Network` | ~1 200 | uygulama/site bazlı ağ ölçümü |
| `Sources/App/Battery` | ~3 000 | pil, güç akışı |
| `Sources/App/Metrics` | ~1 300 | CPU/GPU/RAM/sıcaklık |
| `Sources/App/Wallpaper` | ~2 800 | canlı duvar kâğıdı |
| `Sources/Filter` | ~760 | NetworkExtension filtre |
| `Sources/Saver` + `SaverShared` | ~1 400 | ekran koruyucu |
| `Sources/Widgets` + `WidgetShared` | ~1 400 | WidgetKit |
| `Tests` | ~21 000 | |
| `Resources/Web/app.js` + `style.css` | ~2 000 | tarayıcı ofis istemcisi |

### 2.1 Ajan hattı bugün nasıl çalışıyor

```
Claude Code ──hook──► forward.py (Python 3) ──HTTP POST──► 127.0.0.1:<port>/v1/event
                                                           (X-Adalmon-Token)
   AgentEventServer ──► AgentMonitorModel (AgentState reducer) ──► SwiftUI/SpriteKit ofisi
                                              └──► AgentWebSnapshotBuilder ──► /v1/state + SSE ──► tarayıcı (app.js)
```

- Plugin `adalmon-agents` (yerel marketplace `adalmon-local`), hook'lar `~/Library/Application Support/Adalmon/ClaudePlugin/`.
- `config.json` = port + token (0600). Betik her olayda bunu okur.
- Betik yalnızca izinli alanları iletir: `event, session_id, agent_id, agent_type, tool_name, source, model, from_model, to_model, notification_type, reason, permission_mode, session_title, project (cwd klasör adı), pid, resolved_model, resolved_agent_id, target (opt-in), ts`. **İstem, komut, araç girdisi/çıktısı, dosya içeriği hiçbir zaman gönderilmez.**
- Durum makinesi `AgentState` (450 satır): olay → oturum ağacı. Ek mantık: `SessionDormancy` (30 dk boşta → uykuya), bilinmeyen alt ajanı olaydan evlat edinme, bayat alt ajan temizliği (45 dk), süreç taramasıyla "bekleyen oturum" keşfi (yalnızca yerel).
- **Sunucuya taşınması gereken mantık**: `AgentState` + `AgentEvent` + `SessionDormancy` ≈ 640 satır. Ofis planlayıcısı (koltuk, davranış, balon): `OfficePlanner` 391, `OfficeRoomPlanner` 124, `OfficeRoomArrangement` 138, `OfficeRoomTemplates` 94, `OfficeV3Logic` 267, `OfficeWebLayout` 285, `AgentWebSnapshot` 156 ≈ **1 450 satır**. Web istemcisi bu planı hazır JSON olarak alıyor (oda, koltuk, davranış, balon metni), kendisi planlamıyor.

## 3. Windows portu

### 3.1 Parça parça

| Parça | Mac'te | Windows'ta | Zorluk |
|---|---|---|---|
| Ajan ofisi görseli | SpriteKit sahnesi + tarayıcı istemcisi | **Tarayıcı istemcisi olduğu gibi çalışır** | Kolay |
| Tray / menü çubuğu | AppKit `NSStatusItem` | Tauri, Electron ya da .NET tray; baştan yazılır | Orta |
| CPU, RAM, disk | mach/sysctl | PDH / WMI / `GetSystemTimes` | Orta |
| GPU yükü, sıcaklık | IOReport, IOHID, SMC (özel API) | LibreHardwareMonitor ya da üretici SDK'ları, sürücü gerektirebilir | Zor |
| Uygulama/site bazlı ağ | `NEFilterDataProvider` (system extension) | **WFP (Windows Filtering Platform)**: çekirdek sürücüsü ya da ETW; imzalı sürücü şart | Çok zor |
| Hız sınırı (proxy) | `NETransparentProxyProvider` | WFP callout ya da kullanıcı alanı proxy | Çok zor |
| Pil | IOKit `AppleSmartBattery` | `GetSystemPowerStatus`, WMI `BatteryStatus` | Orta |
| Ekran koruyucu | `.saver` paketi | `.scr` dosyası | Ayrı proje |
| Widget | WidgetKit | Windows Widgets (ayrı SDK) | Ayrı proje |
| Canlı duvar kâğıdı | masaüstü penceresi + AVPlayer | Win32 WorkerW hilesi ya da Wallpaper Engine | Ayrı proje |
| Swift'i Windows'ta çalıştırmak | – | Swift for Windows var, ama SwiftUI/AppKit/SpriteKit/IOKit **yok**; sadece Foundation ve saf mantık taşınır | Sınırlı kazanç |

### 3.2 Seçenekler

| Seçenek | İçerik | Süre (tahmin) | Yorum |
|---|---|---|---|
| **A. Tam port** | Sistem monitörünün tamamı Windows'ta | Haftalar-aylar | İstenen şey bu değil: istek ajan görünürlüğü. WFP sürücüsü tek başına büyük iş. |
| **B. Yalnızca ajan ofisi** | Tarayıcı sekmesi (PWA) ya da küçük tray | 2-5 gün (planlayıcı JS'e taşınırsa) | **Önerilen.** |
| C. Mac'te kal, Windows'tan sadece gönder | Windows PC'ler sadece olay yollar | 1-2 gün | Faz 1 ile aynı: görmek Mac'te olur. |

Sonuç: "Adalmon for Windows" yerine **"Ajan Ofisi her yerde"** hedeflenmeli. Sistem monitörünün Windows'a ihtiyacı varsa ayrı ve sonraya bırakılacak bir proje.

## 4. Çok-PC ajan paylaşımı: doğrulanmış bilgiler

Kaynaklar sonda. "Doğrulandı" = resmi dokümanda yazıyor. "Tahmin" = çıkarım.

### 4.1 Hook'lar ([doküman](https://code.claude.com/docs/en/hooks))

- İşleyici tipleri: `command`, `http`, `mcp_tool`, `prompt`, `agent` (agent deneysel).
- **`http` tipi**: Claude olayın JSON girdisini `POST` gövdesi olarak `Content-Type: application/json` ile gönderir. Alanlar: `url` (zorunlu), `headers` (değerlerde `$VAR`/`${VAR}`), `allowedEnvVars` (yalnızca listedekiler enterpolasyona girer), `timeout` (sn), `onFailure` (`continue` varsayılan, `block`; v2.1.295+).
- `http` hook **varsayılan zaman aşımı 600 sn** (bazı olaylarda 30/10). Senkron: yavaş ya da erişilemez sunucu Claude'u bekletir. Hata (bağlantı hatası, non-2xx, zaman aşımı) varsayılanda **engellemez**.
- 2xx ve **boş gövde** = başarı. Düz metin gövde (`ok`) non-blocking hata sayılır ve debug log'u kirletir: sunucu boş gövde dönmeli.
- **`SessionStart` yalnızca `command` ve `mcp_tool` destekler**, `http` desteklemez.
- **`async: true` yalnızca `command` hook alanı olarak belgelenmiş**; HTTP için belgede async alanı yok (dokümanın "Run hooks in the background" bölümü okunamadı, **doğrulanmadı**).
- Girdi (ortak): `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `prompt_id`, `permission_mode` (her olayda yok), `effort`. Ajan alanları: `agent_id`, `agent_type` (alt ajan içinden tetiklenen olaylarda).
- `session_title`: `SessionStart` ve `UserPromptSubmit`'te, **yalnızca özel başlık varsa**. `model`: yalnızca `SessionStart`'ta, bazen yok (`/clear` sonrası). **pid yok.**
- Yapılandırma yerleri: `~/.claude/settings.json`, `.claude/settings.json`, `.claude/settings.local.json`, yönetilen politika, **plugin `hooks/hooks.json`**, skill/agent frontmatter. Katmanlar birleşir.
- **Cloud (claude.ai/code web) oturumlarında hook'lar çalışır**, ama "cloud sessions don't read your local `~/.claude/settings.json`". `CLAUDE_CODE_REMOTE=true` ortam değişkeni var. `CLAUDE_CODE_BRIDGE_SESSION_ID` (v2.1.199+) Remote Control oturum kimliğini taşır.
- Olay listesi (özet): SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, PostToolUseFailure, Notification, SubagentStart, SubagentStop, Stop, StopFailure, SessionEnd, PreCompact/PostCompact, PostModelSwitch, TaskCreated/Completed ve diğerleri.

### 4.2 Windows'ta hook çalıştırma ([hooks](https://code.claude.com/docs/en/hooks), [setup](https://code.claude.com/docs/en/setup))

- Native Windows desteği var (Windows 10 1809+). Git for Windows **opsiyonel**; yoksa Claude PowerShell aracını kullanır.
- Command hook'ta `shell` alanı `"bash"` ya da `"powershell"`. Varsayılan `bash`; Windows'ta Git Bash yoksa `powershell`.
- `args` (exec form) gerçek bir `.exe` ister; `.cmd`/`.bat` shim'leri çalıştırılamaz.
- Windows'ta `/dev/tty` yok.
- **Python Windows'ta garanti değil** → bugünkü `forward.py` Windows'ta varsayılamaz.
- Windows 10+ ile `curl.exe` yerleşik gelir (tahmin: 1803 sonrası sürümlerde var; doğrulanmalı). PowerShell'de `curl` takma ad olarak `Invoke-WebRequest`'e gider, bu yüzden açık `curl.exe` yazılmalı.
- Windows'ta oturumlar `%USERPROFILE%\.claude` altında.

### 4.3 OpenTelemetry ([doküman](https://code.claude.com/docs/en/monitoring-usage))

- `CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_LOGS_EXPORTER=otlp`, `OTEL_EXPORTER_OTLP_PROTOCOL=http/json`, `OTEL_EXPORTER_OTLP_ENDPOINT=...`, `OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer ...`.
- `~/.claude/settings.json` içindeki `env` ile verilebilir → **plugin gerekmez**. Proje ayarlarında OTEL değişkenleri yok sayılır. Cloud'da sunucu yönetimli ayar/ortam değişkeni.
- Olaylar: `user_prompt`, `tool_decision`, `tool_result`, `api_request`, `assistant_response`... `session.id`, `prompt.id`, `agent_id`, `parent_agent_id` (v2.1.310+).
- **Gerçek zamanlı değil**: log'lar 5 sn'de bir toplu (1 sn'ye indirilebilir), `tool_result` araç **bitince** gelir. "Düşünüyor / izin bekliyor / boşta" durumları yok.
- Gizlilik: istem metni, araç girdileri, komutlar **varsayılan kapalı** (`OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_TOOL_DETAILS`).
- Yargı: hook'lar çok daha zengin ve gerçek zamanlı; OTel yedek/tamamlayıcı olabilir.

### 4.4 "Hesaptaki tüm oturumlar" için resmi API ([issue #58039](https://github.com/anthropics/claude-code/issues/58039))

- Claude Code 5 yüzeyde (terminal, IDE, Desktop, web, mobil/Remote Control) çalışıyor; her yüzeyin kendi oturum listesi var, **birleşik görünüm resmi olarak yok** (özellik isteği açık).
- Claude'un web arayüzünün kullandığı belgesiz API'yi OAuth token ile çağıran topluluk araçları var ([cc-tap](https://glama.ai/mcp/servers/es617/cc-tap)). **Önerilmez**: belgesiz, kimlik bilgisi (OAuth token) ister, hizmet şartları riski, kırılgan.
- Yerel salt-okunur araçlar (ccsinfo vb.) yalnızca tek makinenin `~/.claude/projects` dosyalarını okur.

## 5. Mimari seçenekleri

| | M1: Hook → sunucu (doğrudan) | M2: Hook → yerel iletici → sunucu | M3: OTel → sunucu | M4: Hesap API |
|---|---|---|---|---|
| Kurulum | Plugin | Plugin + küçük yerel süreç | Tek `env` satırı | Token paylaşımı |
| Gerçek zamanlı | Evet | Evet | Hayır (5 sn+, bitişte) | Bilinmiyor |
| Durumlar (düşünüyor/izin/boşta) | Evet | Evet | Hayır | Bilinmiyor |
| Claude'u yavaşlatma riski | HTTP hook senkron → yavaş sunucu bekletir; **command+async+curl** ile yok | Yok (yerel 127.0.0.1) | Yok | – |
| Windows | `curl.exe` ya da PowerShell | Küçük binary | Çalışır | – |
| Cloud oturumları | Proje ayarına hook gerekir | – | Ortam değişkeni ile mümkün | – |
| Öneri | **Evet (async command)** | İhtiyaç olursa | Yedek | **Hayır** |

### 5.1 Önerilen: M1 ama "async command + curl"

Neden `http` tipi değil: `SessionStart` desteklemiyor, belgelenmiş async yok, zaman aşımı 600 sn. Ekstra bir yerel iletici (M2) ancak şu durumda gerekir: `curl` ile her olayda süreç başlatmak sorun olursa (olay başına ~20-50 ms CPU, tahmin) ya da çevrimdışı kuyruklama istenirse.

Taslak `hooks.json` girdisi (**doğrulanmadı, denenmeli**):

```json
{
  "type": "command",
  "shell": "powershell",
  "command": "$input | curl.exe -s -m 3 -X POST -H 'Content-Type: application/json' -H \"X-Adalmon-Token: $env:ADALMON_TOKEN\" --data-binary '@-' https://SUNUCU/v1/event",
  "async": true
}
```

Mac/Linux için bash karşılığı `curl -s -m 3 ... --data-binary @-`. Plugin'de iki giriş (OS'a göre) ya da tek komut gerekebilir. Token'ı dosyadan ya da `allowedEnvVars` ile geçmek ayrı karar.

## 6. Önerilen sistem (abartısız)

```
PC-1 (Mac)  ┐
PC-2 (Win)  ├─ Claude hook (plugin, async curl) ─► HTTPS ─► SUNUCU ─► SSE ─► Mac Adalmon (ofis, makine rozetli)
PC-3 (Win)  ┘                                      (token)   │                └► Tarayıcı/PWA (Faz 2)
```

### 6.1 Olay şeması

Bugünkü izinli alanlar + iki ekleme: `machine` (makine adı, plugin ayarından), `server_ts` (sunucu alım zamanı, saat kaymasına karşı). **`pid` yok** (hook girdisinde yok).

### 6.2 Sunucu (tek küçük servis)

- `POST /v1/event`: cihaz başına token → makine kimliği; gövdeyi doğrula, izinli olmayan alanı at, boş 204 dön (boş gövde şart).
- Bellekte durum: oturum ağacı (`AgentState` mantığı). Kalıcı log **yok** (gizlilik + basitlik). Yeniden başlatmada boş başlar, olaylar geldikçe dolar.
- `GET /v1/state` + `GET /v1/stream` (SSE): token'lı; en fazla N istemci.
- TLS: nginx/Caddy arkasında. Rate limit, gövde boyutu sınırı.
- Dil seçimi açık soru (bölüm 8).

### 6.3 Uzak oturum kuralları (pid olmadığı için)

| Konu | Kural |
|---|---|
| Canlılık | `SessionEnd` + **TTL**: boşta oturum için 30 dk uykuya, 12 saat sonra listeden düşme; çalışan alt ajan için bugünkü 45 dk bayat kuralı |
| Süreç keşfi ("bekleyen oturum") | **Yalnızca yerel** (pid + cwd + transkript zaman damgası). Uzak PC'de keşif için küçük bir yerel ajan gerekir (kapsam dışı, sonra) |
| Oturum adı | Yalnızca özel başlık varsa gelir; yoksa proje klasörü adı |
| Model | Yalnızca `SessionStart`/`PostModelSwitch`; yoksa bilinmiyor |
| Aynı `session_id` iki PC'de | Yok sayılır; anahtar = `machine + session_id` |
| Saat kayması | Sunucu kendi `server_ts`'sini kullanır |

### 6.4 Görüntüleyiciler

- **Faz 1:** Mac Adalmon sunucu akışına abone olur, uzak oturumları kendi `AgentState`'ine makine etiketiyle ekler. Planlayıcı Swift'te kaldığı için **hiçbir şey taşınmaz**. Windows PC'ler sadece gönderir.
- **Faz 2:** Windows/telefon/tarayıcıda görmek için planlayıcıyı (~1 450 satır) JS'e taşı, sunucu aynı `app.js`'i servis etsin. Mac Adalmon isterse oradan da beslenebilir.

### 6.5 Gizlilik ve güvenlik

- Alan beyaz listesi bugünkü gibi; istem/komut/içerik asla.
- Proje klasörü adı ve oturum başlığı yine de hassas olabilir → makine başına "adları gizle" (sunucuya gitmeden önce `Proje 1` gibi maskeleme) seçeneği.
- Kullanıcı izni: plugin kurulumu + ayarlarda açık anahtar + hangi makinenin gönderdiği listede görünür.
- Cihaz başına ayrı token, iptal edilebilir. Token düz metin dosyada tutulursa 0600 / kullanıcı dizini.
- Sunucu salt gösterim: oturumu kontrol etme yok.

### 6.6 Hata davranışı

- Sunucu kapalı: `curl -m 3` zaman aşımına uğrar, hook sessiz başarısız (engellemez), olay kaybolur. Kuyruklama yok (abartı olur).
- Olay hacmi: her araç çağrısı iki olay; 3 PC × yoğun çalışma = dakikada yüzlerce olay (tahmin). Küçük bir süreç için sorun değil.

## 7. Cloud (web) oturumları: kenar durum

Hook'lar orada çalışır (`CLAUDE_CODE_REMOTE=true`) ama yerel kullanıcı ayarı okunmaz. Dahil etmek için projenin `.claude/settings.json`'ına hook/plugin koymak **ve** cloud ortamının ağ izninde sunucu alan adını açmak gerekir. Her repoya dokunmayı gerektirdiği için **ilk aşamadan dışarıda** bırakılması önerilir. OTel `env` yolu cloud'da ortam değişkeniyle de mümkün ama gerçek zamanlı değil.

## 8. Karar bekleyenler

1. **Sunucu ortamı:** Node, Go ya da Python? (Hangisi sunucuda rahat ve bakımı kolay.)
2. **Windows'ta görünüm:** tarayıcı sekmesi/PWA yeter mi, yoksa tray uygulaması mı? (Tray istenirse Faz 2'ye ek 2-3 gün tahmin.)
3. **Cloud oturumları** ilk aşamaya dahil mi? (Önerilen: hayır.)
4. Windows'ta komut kabuğu: `curl.exe` (PowerShell hook) mı, küçük bir iletici binary mi? (Önerilen: önce `curl.exe`, sorun çıkarsa iletici.)

## 9. Doğrulanmayanlar (uygulamadan önce denenmeli)

- `http` hook'un async/arka plan çalıştırma desteği (dokümanın ilgili bölümü okunamadı).
- Plugin `hooks.json` içinde OS'a göre farklı komut tanımlanabiliyor mu (ya da `shell` alanı yeterli mi).
- `curl.exe` ve PowerShell stdin aktarımı (`$input | curl.exe --data-binary '@-'`) gerçek Windows'ta çalışıyor mu.
- Hook'un ortam değişkenlerine (`ADALMON_TOKEN`) Windows'ta nasıl erişileceği.
- Cloud oturumlarında plugin/proje hook taşınması (dokümanda "what carries over" bölümü okunmadı).
- Olay başına `curl` süreç maliyeti (ölçülmedi).

## 10. Fazlar

| Faz | İş | Tahmin | Kazanç |
|---|---|---|---|
| 0 | Karar noktaları (bölüm 8) + Windows'ta bir PC'de hook komutunu elle deneme | yarım gün | Doğrulanmayanları kapatır |
| 1 | Plugin'e uzak hedef, sunucu (olay al, durum tut, SSE), Mac Adalmon aboneliği + makine rozeti, `AgentState`'in sunucu diline portu (~640 satır), testler | 1-2 gün | 3 PC'nin ajanları Mac'te görünür |
| 2 | Planlayıcıyı JS'e taşı (~1 450 satır + test), sunucuda web sayfası | 3-5 gün | Windows/telefon/tarayıcıda ofis |
| 3 (isteğe bağlı) | Windows tray (Tauri), uzak keşif ajanı | 2-4 gün | Daha iyi Windows deneyimi |

## 11. Kaynaklar

- Hooks dokümanı: https://code.claude.com/docs/en/hooks
- Monitoring / OpenTelemetry: https://code.claude.com/docs/en/monitoring-usage
- Kurulum ve Windows: https://code.claude.com/docs/en/setup
- Birleşik oturum görünümü isteği: https://github.com/anthropics/claude-code/issues/58039
- Topluluk aracı (belgesiz API, önerilmez): https://glama.ai/mcp/servers/es617/cc-tap
- Repo içi: `Sources/App/Agents/*`, `Sources/App/Office/*`, `Resources/Web/app.js`, `docs/OFFICE-V3.md`, `docs/OFFICE-V4.md`
