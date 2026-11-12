import AppKit
import SwiftUI

/// Ayarlar › Claude ajanları › "Abonelik limitleri": Claude statusLine bağlantısı (isteğe bağlı), Codex okuma anahtarı, uyarı eşikleri.
struct SubscriptionLimitsSettingsSection: View {
    @Bindable var model: SubscriptionLimitsModel
    let listenerRunning: Bool
    @State private var confirmConnect = false

    var body: some View {
        Section("Abonelik limitleri") {
            Text("Claude ve Codex aboneliklerinizin 5 saatlik ve haftalık kullanımını \"Ajanlar\" panelinde gösterir; eşik aşılınca bir kez bildirim gönderir. API kredi bakiyesi için resmi bir uç nokta olmadığından gösterilmez.")
                .font(.caption).foregroundStyle(.secondary)

            LabeledContent("Claude Code") {
                Text(model.claudeConnected ? "bağlı" : "bağlı değil").foregroundStyle(model.claudeConnected ? .primary : .secondary)
            }
            HStack {
                if model.claudeConnected {
                    Button("Bağlantıyı kaldır") { model.disconnectClaude() }
                } else {
                    Button("Claude limitlerini bağla") { confirmConnect = true }
                }
                Button("Yedekleri göster") { NSWorkspace.shared.open(model.backupDirectory) }
                    .disabled(!FileManager.default.fileExists(atPath: model.backupDirectory.path))
            }
            if let message = model.lastMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if model.claudeConnected && !listenerRunning {
                Text("Dinleyici kapalı: değerlerin gelmesi için yukarıdaki \"Özelliği aç\" anahtarını açın. Durum satırınız etkilenmez.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("Bağlarken ~/.claude/settings.json yedeklenir ve statusLine komutu küçük bir sarmalayıcıyla değiştirilir. Sarmalayıcı mevcut durum satırı komutunuzu aynen çalıştırır (çıktısı değişmez) ve yalnızca dört sayıyı (kullanılan yüzde ve yenilenme anı) bu Mac'teki Adalmon'a iletir. Değerler yalnızca claude.ai aboneliğinde ve oturumdaki ilk yanıttan sonra gelir. \"Bağlantıyı kaldır\" eski statusLine'ı geri koyar.")
                .font(.caption).foregroundStyle(.secondary)

            Toggle("Codex limitlerini göster", isOn: $model.codexEnabled)
            Text("~/.codex/sessions altındaki en yeni oturum dosyasının yalnızca sonu okunur (salt okunur, ağ yok). Biçim belgelenmemiştir; okunamazsa gösterge gizlenir. Hesap ve plan bilgisi okunmaz.")
                .font(.caption).foregroundStyle(.secondary)

            Toggle("Limit bildirimleri", isOn: $model.thresholds.notificationsEnabled)
            thresholdStepper("5 saat: uyarı", value: $model.thresholds.fiveHourWarn)
            thresholdStepper("5 saat: kritik", value: $model.thresholds.fiveHourCritical)
            thresholdStepper("Haftalık: uyarı", value: $model.thresholds.weeklyWarn)
            thresholdStepper("Haftalık: kritik", value: $model.thresholds.weeklyCritical)
            Text("Her limit penceresinde uyarı ve kritik bildirimi en çok birer kez gelir; pencere yenilenince sıfırlanır.")
                .font(.caption).foregroundStyle(.secondary)

            Picker("Erken dolma uyarısı", selection: $model.forecastSensitivity) {
                ForEach(LimitForecastSensitivity.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(!model.thresholds.notificationsEnabled)
            Text(forecastExplanation)
                .font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog("Claude limitleri bağlansın mı?", isPresented: $confirmConnect) {
            Button("Bağla") { model.connectClaude() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("~/.claude/settings.json yedeklenecek ve statusLine komutu Adalmon sarmalayıcısıyla değiştirilecek. Mevcut durum satırınız aynen görünmeye devam eder. Açık Claude Code oturumları değişikliği bir sonraki yenilemede görür.")
        }
    }

    /// Seçili duyarlılığın koşulları (ayar değişince metin de değişir).
    private var forecastExplanation: String {
        let five = LimitForecastRule.rule(.fiveHour, model.forecastSensitivity)
        let week = LimitForecastRule.rule(.weekly, model.forecastSensitivity)
        return "Tüketim hızı sürerse limit yenilenmeden belirgin şekilde önce dolacaksa pencere başına bir kez uyarır: "
            + "5 saatlikte kullanım \(LimitFormat.percent(five.minUsedPercent)) ve üstündeyken, en az \(LimitFormat.duration(minutes: Int(five.minMargin / 60))) erken dolacaksa; "
            + "haftalıkta \(LimitFormat.percent(week.minUsedPercent)) ve üstündeyken, en az \(LimitFormat.duration(minutes: Int(week.minMargin / 60))) erken dolacaksa. "
            + "Hız yalnızca yeterli veri birikince (5 saatlikte en az \(LimitFormat.duration(minutes: Int(five.minSpan / 60))), haftalıkta en az \(LimitFormat.duration(minutes: Int(week.minSpan / 60)))) hesaplanır; tahmin panel kartında da görünür."
    }

    private func thresholdStepper(_ title: String, value: Binding<Double>) -> some View {
        Stepper(value: value, in: LimitAlertThresholds.range, step: 5) {
            LabeledContent(title) { Text(LimitFormat.percent(value.wrappedValue)).monospacedDigit() }
        }
        .disabled(!model.thresholds.notificationsEnabled)
    }
}
