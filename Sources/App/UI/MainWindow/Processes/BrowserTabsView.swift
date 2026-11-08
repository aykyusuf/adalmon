import AppKit
import SwiftUI

/// "Tarayıcılar": Safari sekme listesi (AppleScript, opt-in) + Safari Web İçeriği RAM'i (tahmini) ve gelişmiş Chrome
/// hata ayıklama modu (sekme başına JS belleği). Yoklama yalnızca bu sekme görünürken ve pencere öndeyken çalışır.
struct BrowserTabsView: View {
    let model: AppModel
    @State private var browser = BrowserTabsModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SafariTabsCard(browser: browser)
                ChromeDebugCard(browser: browser)
            }
            .padding(.bottom, 8)
        }
        .task(id: browser.safariEnabled) {
            guard browser.safariEnabled else { return }
            await browser.runSafari { [model] in model.mainWindowVisible && NSApp.isActive }
        }
        .task(id: browser.chromeEnabled) {
            guard browser.chromeEnabled else { return }
            await browser.runChrome { [model] in model.mainWindowVisible && NSApp.isActive }
        }
    }
}

// MARK: Safari

private struct SafariTabsCard: View {
    @Bindable var browser: BrowserTabsModel
    private static let maxTabs = 60
    private static let maxProcesses = 20

    var body: some View {
        ResourceCard(title: "Safari sekmeleri", systemImage: "safari") {
            Toggle("Safari sekme listesini göster", isOn: $browser.safariEnabled)
                .toggleStyle(.switch)
            if !browser.safariEnabled {
                BrowserNote(text: "Açınca Adalmon, Safari'deki açık sekmelerin başlık ve adreslerini AppleScript ile okur. İlk seferde macOS “Adalmon, Safari'yi denetlemek istiyor” diye izin sorar. Kapalıyken Safari'ye hiçbir istek gönderilmez.")
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch browser.safariState {
        case .off, .checking:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Safari denetleniyor…").foregroundStyle(.secondary) }
        case .notRunning:
            BrowserNote(text: "Safari açık değil. Safari açılınca sekmeler burada görünür (Adalmon Safari'yi kendisi başlatmaz).")
        case .needsPermission:
            VStack(alignment: .leading, spacing: 8) {
                BrowserNote(text: "Sekme listesini okumak için Otomasyon izni gerekiyor. Düğmeye basınca macOS bir izin penceresi gösterir; “İzin Ver”i seçin. Adalmon yalnızca sekme başlık ve adreslerini okur, Safari'de hiçbir şeyi değiştirmez.")
                Button("İzin ver ve sekmeleri oku", systemImage: "hand.raised") { Task { await browser.requestSafariPermission() } }
            }
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Label(SafariTabsError.permissionDenied.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                Button("Otomasyon ayarlarını aç", systemImage: "gear") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(url) }
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        case .loaded:
            loaded
        }
    }

    @ViewBuilder
    private var loaded: some View {
        let tabs = browser.safariTabs
        let windows = Set(tabs.map(\.window)).count
        let memory = browser.safariMemory
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            BrowserStat(title: "Sekme", value: "\(tabs.count)", detail: "\(windows) pencere")
            if let memory {
                BrowserStat(title: "Web İçeriği toplamı", value: ResourceFormat.bytes(Double(memory.total)),
                            detail: "\(memory.processes.count) süreç")
                if let average = memory.averagePerTab {
                    BrowserStat(title: "Sekme başına ortalama", value: ResourceFormat.bytes(Double(average)), detail: "tahmini")
                }
            }
            Spacer(minLength: 0)
        }
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) { tabList.frame(minWidth: 320); processList.frame(minWidth: 280) }
            VStack(alignment: .leading, spacing: 14) { tabList; processList }
        }
        Text("Safari sekme–süreç eşlemesini vermiyor; süreç sıralaması tahminidir ve bir süreç hangi sekmeye ait bilinmez. Ortalama = Web İçeriği toplamı ÷ tüm sekmeler (Safari arka plandaki sekmeleri boşaltabildiği için yüklü sekme sayısı bilinmiyor).")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var tabList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Açık sekmeler").font(.subheadline.weight(.semibold))
            let tabs = browser.safariTabs
            if tabs.isEmpty { BrowserNote(text: "Açık sekme yok.") }
            ForEach(tabs.prefix(Self.maxTabs)) { tab in
                BrowserTabRow(title: tab.title, url: tab.url, trailing: nil)
            }
            if tabs.count > Self.maxTabs { BrowserNote(text: "ve \(tabs.count - Self.maxTabs) sekme daha") }
        }
    }

    private var processList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Web İçeriği süreçleri").font(.subheadline.weight(.semibold))
                Text("RAM'e göre · tahmini").font(.caption).foregroundStyle(.secondary)
            }
            let processes = browser.safariMemory?.processes ?? []
            if processes.isEmpty { BrowserNote(text: "Safari Web İçeriği süreci bulunamadı.") }
            let peak = Double(max(1, processes.first?.footprint ?? 1))
            ForEach(processes.prefix(Self.maxProcesses)) { process in
                HStack(spacing: 8) {
                    Text("Web İçeriği · pid \(process.pid)").font(.callout).monospacedDigit().lineLimit(1)
                    Spacer(minLength: 6)
                    Capsule().fill(Color.accentColor.opacity(0.55))
                        .frame(width: max(2, 60 * Double(process.footprint) / peak), height: 5)
                    Text(ResourceFormat.bytes(Double(process.footprint))).font(.callout).monospacedDigit()
                        .frame(minWidth: 64, alignment: .trailing)
                }
            }
            if processes.count > Self.maxProcesses { BrowserNote(text: "ve \(processes.count - Self.maxProcesses) süreç daha") }
        }
    }
}

// MARK: Chrome

private struct ChromeDebugCard: View {
    @Bindable var browser: BrowserTabsModel

    var body: some View {
        ResourceCard(title: "Chrome sekme RAM'i (gelişmiş)", systemImage: "hammer") {
            Toggle("Gelişmiş Chrome modunu etkinleştir", isOn: $browser.chromeEnabled)
                .toggleStyle(.switch)
            BrowserNote(text: "Chrome, sekmelerin süreç bilgisini normal profilde vermez. Bu mod, Chrome'un ayrı bir kopyasını Adalmon'a ait boş bir profille ve yalnızca bu Mac'e (127.0.0.1) açık bir hata ayıklama portuyla başlatır; açık olan Chrome'unuz kapatılmaz.")
            Label("Yerel porta erişen her uygulama bu Chrome'u kontrol edebilir; ayrı profil kullanılır, oturumların taşınmaz. Bu pencerede hassas hesaplara giriş yapmayın.",
                  systemImage: "exclamationmark.shield.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            if browser.chromeEnabled { content }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch browser.chromeState {
        case .off, .idle:
            launchButton
        case .notInstalled:
            BrowserNote(text: "Google Chrome bulunamadı.")
        case .launching:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Chrome başlatılıyor ve bağlanılıyor…").foregroundStyle(.secondary) }
        case .disconnected(let message), .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            HStack {
                launchButton
                Button("Sıfırla") { browser.resetChromeConnection() }
            }
        case .connected:
            connected
        }
    }

    private var launchButton: some View {
        Button("Adalmon hata ayıklama profiliyle Chrome'u başlat", systemImage: "play.circle") {
            Task { await browser.launchChrome() }
        }
    }

    @ViewBuilder
    private var connected: some View {
        let tabs = browser.chromeTabs
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            BrowserStat(title: "Sekme", value: "\(tabs.count)", detail: "hata ayıklama Chrome'u")
            if let renderer = browser.chromeRenderer, renderer.count > 0 {
                BrowserStat(title: "Renderer süreçleri", value: ResourceFormat.bytes(Double(renderer.total)), detail: "\(renderer.count) süreç · toplam RAM")
            }
            Spacer(minLength: 0)
        }
        VStack(alignment: .leading, spacing: 4) {
            Text("Sekmeler · JS belleği").font(.subheadline.weight(.semibold))
            if tabs.isEmpty { BrowserNote(text: "Açık sekme yok.") }
            ForEach(tabs) { tab in
                BrowserTabRow(title: tab.title, url: tab.url, trailing: Self.metricsText(tab.metrics))
            }
        }
        Text("JS belleği yalnızca sayfanın JavaScript yığınıdır (kullanılan / ayrılan) ve DOM düğüm sayısıdır; sekmenin süreç RAM'i değildir. Chrome kararlı protokolde sekme–süreç eşlemesini vermez. Toplam renderer RAM'i \(browser.chromeRenderer == nil ? "için İşlemler sekmesindeki Google Chrome satırına bakın" : "bu Chrome'un renderer süreçlerinin toplamıdır").")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private static func metricsText(_ m: CDPTabMetrics?) -> String {
        guard let m else { return "—" }
        var parts: [String] = []
        if let used = m.jsHeapUsed {
            let total = m.jsHeapTotal.map { " / \(ResourceFormat.bytes($0))" } ?? ""
            parts.append("JS \(ResourceFormat.bytes(used))\(total)")
        }
        if let nodes = m.nodes { parts.append("\(Int(nodes)) düğüm") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

// MARK: Ortak parçalar

private struct BrowserStat: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct BrowserTabRow: View {
    let title: String
    let url: String
    let trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title.isEmpty ? "Adsız sekme" : title).font(.callout).lineLimit(1).truncationMode(.tail)
                Text(Self.host(url)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .help(url)
            Spacer(minLength: 6)
            if let trailing { Text(trailing).font(.callout).monospacedDigit().foregroundStyle(.secondary).lineLimit(1) }
        }
        .padding(.vertical, 2)
    }

    static func host(_ url: String) -> String { URL(string: url)?.host() ?? url }
}

private struct BrowserNote: View {
    let text: String
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
