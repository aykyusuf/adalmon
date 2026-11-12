import AppKit
import SwiftUI

/// Ayarlar › Claude ajanları: özelliği aç, plugin'i kur/kaldır, durum satırları, gizlilik notu.
struct AgentsSettingsPane: View {
    let model: AppModel
    @Bindable var prefs: Preferences

    init(model: AppModel) {
        self.model = model
        self.prefs = model.prefs
    }

    private var agents: AgentService { model.agents }

    var body: some View {
        Form {
            Section {
                Text("Claude Code oturumlarını ve alt ajanlarını Adalmon'da canlı gösterir (menü çubuğundaki \"Ajanlar\" öğesi ve paneli). Bir Claude Code plugin'i, olay adlarını bu Mac'te 127.0.0.1 üzerindeki yerel bir dinleyiciye iletir. ~/.claude/settings.json dosyanıza Adalmon yalnızca aşağıdaki \"Claude limitlerini bağla\" düğmesine basarsanız (yedek alarak) dokunur.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Özelliği aç", isOn: Binding(get: { prefs.agentsEnabled }, set: { agents.setEnabled($0) }))
                Toggle("Menü çubuğunda \"Ajanlar\" öğesini göster", isOn: $prefs.agentsInMenuBar)
                    .disabled(!prefs.agentsEnabled)
                Toggle("Ofis balonlarında hedefi de göster (dosya adı / komut adı)", isOn: Binding(get: { prefs.agentsShowTargets }, set: { agents.setShowTargets($0) }))
                    .disabled(!prefs.agentsEnabled)
                Text("Kapalıyken balonlar yalnızca araç türünü söyler (\"Dosya düzenliyor\"). Açıkken \"main.swift düzenliyor\" gibi yalnızca dosya adı ya da komutun ilk kelimesi gösterilir.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Tarayıcı görünümü") {
                Toggle("Tarayıcı görünümünü etkinleştir", isOn: Binding(get: { prefs.agentsWebEnabled }, set: { agents.setWebEnabled($0) }))
                    .disabled(!prefs.agentsEnabled)
                Text("Ofisi bu Mac'teki tarayıcıda canlı izlersiniz (piksel-art sahne). Sayfa yalnızca 127.0.0.1 üzerinden, token ile açılır; kapalıyken bu adresler 404 verir. Sayfa kapalıyken uygulama tarafında hiçbir iş yapılmaz.")
                    .font(.caption).foregroundStyle(.secondary)
                if prefs.agentsWebEnabled, let address = agents.webDisplayAddress {
                    LabeledContent("Adres") {
                        Text("\(address)?t=••••••••").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Tarayıcıda aç") {
                            if let url = agents.webURL { NSWorkspace.shared.open(url) }
                        }
                        Button("Kopyala") {
                            if let url = agents.webURL {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                            }
                        }
                    }
                    .disabled(agents.webURL == nil)
                }
                Text("Yalnızca bu Mac'ten erişilir (ağdaki diğer cihazlar bağlanamaz). Adres bir token içerir: gizli tutun, başkalarıyla paylaşmayın.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Plugin") {
                LabeledContent("Dinleyici", value: listenerText)
                LabeledContent("Plugin", value: pluginText)
                if agents.pluginStatus == .installed, let version = agents.installedVersion {
                    LabeledContent("Betik") {
                        if agents.scriptsOutdated {
                            Text("Betik güncellendi: eklentiyi yeniden kur (\(version) → \(AgentPluginGenerator.version))").foregroundStyle(.orange)
                        } else {
                            Text("güncel (\(version))").foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Son olay") {
                    if let last = agents.monitor.lastEventAt { Text(last, style: .relative) } else { Text("henüz yok").foregroundStyle(.secondary) }
                }
                HStack {
                    if agents.pluginStatus == .installed {
                        if agents.scriptsOutdated {
                            Button("Güncelle") { Task { await agents.updatePlugin() } }
                                .disabled(!prefs.agentsEnabled || agents.port == nil)
                        }
                        Button("Kaldır", role: .destructive) { Task { await agents.uninstallPlugin() } }
                    } else {
                        Button("Plugin'i kur") { Task { await agents.installPlugin() } }
                            .disabled(!prefs.agentsEnabled || agents.port == nil)
                    }
                    if agents.isBusy { ProgressView().controlSize(.small) }
                }
                .disabled(agents.isBusy)
                Text("Önemli: açık olan Claude Code oturumları plugin'i görmez. Kurulumdan sonra yeni bir Claude Code oturumu açın (ya da oturumu yeniden başlatın).")
                    .font(.caption).foregroundStyle(agents.needsNewSession ? .orange : .secondary)
                if let message = agents.errorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                    ForEach(agents.manualCommands, id: \.self) { command in
                        Text(command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }

            controlSection

            SubscriptionLimitsSettingsSection(model: agents.limits, listenerRunning: agents.port != nil)

            Section("Gizlilik") {
                Text("İletilir: olay adı, oturum ve ajan kimliği, ajan türü, araç adı, model adı, bildirim türü, proje klasörünün adı (yolun son parçası), oturum adı (session_title; /rename ile verdiğiniz ya da otomatik başlık), izin modu ve zaman. \"Hedefi de göster\" açıkken ek olarak yalnızca dosya adı (yolun son parçası) ya da komutun ilk kelimesi iletilir; içerik ve argüman asla.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("İletilmez: istem/komut argümanları/dosya içeriği (istemleriniz, araç girdi ve çıktıları, Claude'un yanıtları, dosya içerikleri), transkript. (\"Ofisten cevapla\" açıkken tek istisna: bekleyen izin/soru ayrıntısı yalnızca ofis kartı için bellekte tutulur; ayrıca araç sonuç olaylarında istem kimliği ve araç girdisinin kısa bir SHA-256 özeti iletilir, kartı eşlemek için.) Dinleyici yalnızca bu Mac'ten, rastgele bir token ile erişilebilir; özellik kapalıyken hiç çalışmaz. Eski oturumların modeli, konuşma dosyasının yalnızca model alanı okunarak bulunur; içerik okunmaz/saklanmaz.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await agents.refreshPluginStatus() }
    }

    /// Ofisten izin/soru cevapla (OFFICE-CTRL-01). Varsayılan KAPALI; Python gerekir.
    private var controlSection: some View {
        Section("Ofisten cevapla (deneysel)") {
            Toggle("Ofisten izin isteklerini ve soruları cevapla", isOn: Binding(
                get: { agents.isControlEnabled },
                set: { agents.setControlEnabled($0) }))
                .disabled(!prefs.agentsEnabled || !agents.controlAvailable)
            if !agents.controlAvailable {
                Text("Python 3 bulunamadı (Komut Satırı Araçları kurulu değil): bu özellik kapalı kalır. Terminal komutu: xcode-select --install")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("Açıkken Claude Code'un izin istekleri ve AskUserQuestion soruları ofis kartında görünür; İzin ver, Reddet, Hep izin ver ya da cevap seçeneğine tıklayarak cevaplarsınız. Terminaldeki diyalog yine açılır; ikisinden hangisini önce cevaplarsanız o geçerlidir.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Dikkat: bu özellik Claude Code'a vereceğiniz izinleri uygulamadan verebilmenizi sağlar. Kartta komut, dosya yolu, plan ve soru metni gösterilir (yalnızca bu Mac'te, bellekte; olay akışına, tarayıcı görünümüne ve loglara yazılmaz). \"Tüm oturumlarda (kalıcı)\" seçeneği kuralı Claude Code'un kendisine ~/.claude/settings.json içine yazdırır; Adalmon o dosyaya yazmaz. Tüm izinleri atlayan mod sunulmaz. Adalmon kapalıyken ya da hata olursa normal terminal diyaloğu çalışır.")
                .font(.caption).foregroundStyle(.secondary)
            if agents.isControlEnabled, agents.pluginStatus != .installed || agents.scriptsOutdated {
                Text("Bu özellik için eklentiyi kurun ya da güncelleyin (sürüm \(AgentPluginGenerator.version)); ardından açık Claude Code oturumlarını yeniden başlatın.")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("Denetim kaydını göster") { revealAuditLog() }
                    .help("Verilen kararların kaydı (zaman, oturum, proje, araç adı, karar). İçerik yazılmaz.")
                if agents.decisions.items.count > 0 {
                    Text("\(agents.decisions.items.count) bekleyen istek").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func revealAuditLog() {
        let url = agents.auditLogURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    private var listenerText: String {
        switch agents.listener {
        case .off: "kapalı"
        case .starting: "başlıyor…"
        case .running(let port): "çalışıyor (127.0.0.1:\(port))"
        case .failed(let reason): "hata: \(reason)"
        }
    }

    private var pluginText: String {
        switch agents.pluginStatus {
        case .installed: "yüklü"
        case .notInstalled: "yüklü değil"
        case .unknown: "bilinmiyor (claude komutu bulunamadı ya da yanıt vermedi)"
        }
    }
}
